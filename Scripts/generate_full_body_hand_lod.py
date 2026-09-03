#!/usr/bin/env python3
"""Build clean, skin-fitted hand anatomy for every full-body layer.

The registered whole-body systems have crowded or fused extremity geometry and
were fitted against a denser skin than the translucent ghost shell rendered by
the app. This generator removes the atlas hand geometry, installs compact
NIMBLE muscles, tendons, bones, joints, and nerves, and insets hand vessels
against that exact rendered ghost shell.
"""

from __future__ import annotations

import argparse
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import trimesh
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

from register_anatomy_volume import (
    fit_inside_surface,
    signed_surface_distance,
    usd_to_mesh,
    write_usda,
)


@dataclass(frozen=True)
class HandLODRegistration:
    wrist: np.ndarray
    distal_axis: np.ndarray
    center: np.ndarray
    rotation: float
    muscle_scale: float
    tendon_scale: float
    skeleton_scale: float
    joint_scale: float
    nerve_scale: float


REGISTRATIONS = {
    "Female": HandLODRegistration(
        wrist=np.array([0.380, 0.120]),
        distal_axis=np.array([0.291, -0.957]),
        center=np.array([0.408, 0.030, -0.022]),
        rotation=-2.847,
        muscle_scale=0.240,
        tendon_scale=0.280,
        skeleton_scale=0.280,
        joint_scale=0.280,
        nerve_scale=0.280,
    ),
    "Male": HandLODRegistration(
        wrist=np.array([0.420, 0.125]),
        distal_axis=np.array([0.353, -0.936]),
        center=np.array([0.448, 0.038, 0.015]),
        rotation=-2.781,
        muscle_scale=0.230,
        tendon_scale=0.270,
        skeleton_scale=0.270,
        joint_scale=0.270,
        nerve_scale=0.270,
    ),
}


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "resource_directory",
        nargs="?",
        type=Path,
        default=Path("LittleWindows/Resources/BodyAnatomy"),
    )
    parser.add_argument(
        "--source-directory",
        type=Path,
        default=Path(__file__).resolve().parent / "BodyAnatomySource",
        help="Source-only whole-body meshes that must not ship in the app bundle.",
    )
    return parser.parse_args()


def compact_mesh(vertices: np.ndarray, faces: np.ndarray) -> trimesh.Trimesh:
    used = np.unique(faces.reshape(-1))
    remap = np.full(len(vertices), -1, dtype=np.int64)
    remap[used] = np.arange(len(used), dtype=np.int64)
    return trimesh.Trimesh(
        vertices=vertices[used],
        faces=remap[faces],
        process=False,
        validate=False,
    )


def clipped_body_system(
    mesh: trimesh.Trimesh,
    registration: HandLODRegistration,
) -> trimesh.Trimesh:
    vertices = np.asarray(mesh.vertices)
    faces = np.asarray(mesh.faces)
    face_vertices = vertices[faces]
    centers = face_vertices.mean(axis=1)
    distal_distance = (
        (np.abs(face_vertices[:, :, 0]) - registration.wrist[0])
        * registration.distal_axis[0]
        + (face_vertices[:, :, 1] - registration.wrist[1])
        * registration.distal_axis[1]
    )
    hand_faces = (
        (np.abs(centers[:, 0]) > registration.wrist[0] - 0.035)
        & (centers[:, 1] > -0.10)
        & (centers[:, 1] < 0.18)
        & (np.max(distal_distance, axis=1) > 0.0)
    )
    return compact_mesh(vertices, faces[~hand_faces])


def inset_hand_vertices(
    mesh: trimesh.Trimesh,
    skin: trimesh.Trimesh,
    registration: HandLODRegistration,
    margin: float,
) -> tuple[trimesh.Trimesh, dict[str, float | int]]:
    vertices = np.asarray(mesh.vertices).copy()
    faces = np.asarray(mesh.faces)
    hand_indices = np.flatnonzero(hand_vertex_mask(vertices, registration))
    original_hand = vertices[hand_indices].copy()
    distances, _, _ = signed_surface_distance(skin, vertices[hand_indices])
    outside_before = int(np.count_nonzero(distances < 0.0))
    minimum_before = float(distances.min())

    # Move toward the local interior in sub-millimeter steps and keep only
    # corrections that improve signed depth. Directly snapping to a nearest
    # triangle can jump across the narrow gap between adjacent fingers.
    for _ in range(40):
        distances, _, triangle_ids = signed_surface_distance(
            skin,
            vertices[hand_indices],
        )
        shallow = np.flatnonzero(distances < margin)
        if len(shallow) == 0:
            break
        step = np.clip(margin - distances[shallow], 0.0001, 0.0006)
        normals = skin.face_normals[triangle_ids[shallow]]
        candidate = vertices[hand_indices[shallow]] - normals * step[:, None]
        candidate_distances, _, _ = signed_surface_distance(skin, candidate)
        improves = candidate_distances > distances[shallow] + 1.0e-8
        if not np.any(improves):
            break
        vertices[hand_indices[shallow[improves]]] = candidate[improves]

    after, _, _ = signed_surface_distance(skin, vertices[hand_indices])
    maximum_correction = float(
        np.linalg.norm(vertices[hand_indices] - original_hand, axis=1).max()
    )
    return (
        trimesh.Trimesh(
            vertices=vertices,
            faces=faces,
            process=False,
            validate=False,
        ),
        {
            "hand_vertices": len(hand_indices),
            "outside_before": outside_before,
            "minimum_before": minimum_before,
            "outside_after": int(np.count_nonzero(after < 0.0)),
            "minimum_after": float(after.min()),
            "maximum_correction": maximum_correction,
        },
    )


def hand_vertex_mask(
    vertices: np.ndarray,
    registration: HandLODRegistration,
) -> np.ndarray:
    distal_distance = (
        (np.abs(vertices[:, 0]) - registration.wrist[0])
        * registration.distal_axis[0]
        + (vertices[:, 1] - registration.wrist[1])
        * registration.distal_axis[1]
    )
    return (
        (np.abs(vertices[:, 0]) > registration.wrist[0] - 0.05)
        & (vertices[:, 1] > -0.14)
        & (vertices[:, 1] < 0.22)
        & (distal_distance > -0.03)
    )



def split_hand_surface_network(
    mesh: trimesh.Trimesh,
    front_half: bool,
) -> trimesh.Trimesh:
    """Split paired palmar/dorsal routes into distinct vascular networks."""
    vertices = np.asarray(mesh.vertices)
    faces = np.asarray(mesh.faces)
    edges = np.concatenate(
        (faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]])
    )
    _, labels = connected_components(
        coo_matrix(
            (np.ones(len(edges), dtype=np.uint8), (edges[:, 0], edges[:, 1])),
            shape=(len(vertices), len(vertices)),
        ),
        directed=False,
    )
    selected_labels: list[int] = []
    for side in (1, -1):
        side_labels = np.unique(labels[vertices[:, 0] * side > 0.0])
        depths = np.asarray(
            [vertices[labels == label, 2].mean() for label in side_labels]
        )
        depth_split = float(np.median(depths))
        if front_half:
            selected_labels.extend(side_labels[depths >= depth_split].tolist())
        else:
            selected_labels.extend(side_labels[depths < depth_split].tolist())
    selected_faces = np.isin(labels[faces[:, 0]], selected_labels)
    return compact_mesh(vertices, faces[selected_faces])


def merged_mesh(*meshes: trimesh.Trimesh) -> trimesh.Trimesh:
    vertices: list[np.ndarray] = []
    faces: list[np.ndarray] = []
    offset = 0
    for mesh in meshes:
        mesh_vertices = np.asarray(mesh.vertices)
        vertices.append(mesh_vertices)
        faces.append(np.asarray(mesh.faces) + offset)
        offset += len(mesh_vertices)
    return trimesh.Trimesh(
        vertices=np.concatenate(vertices),
        faces=np.concatenate(faces),
        process=False,
        validate=False,
    )


def transform_hand(
    vertices: np.ndarray,
    faces: np.ndarray,
    registration: HandLODRegistration,
    scale: float,
    side: int,
) -> tuple[np.ndarray, np.ndarray]:
    result = vertices.copy()
    # NIMBLE's thumb is on its positive-X side. The whole-body wrist transform
    # turns the longitudinal finger axis toward the matching arm, so its local
    # lateral axis must be reflected to keep the thumb facing away from the
    # body's midline instead of folding it invisibly into the palm.
    result[:, 0] *= -side
    result *= scale

    angle = registration.rotation * side
    cosine = np.cos(angle)
    sine = np.sin(angle)
    x = result[:, 0] * cosine - result[:, 1] * sine
    y = result[:, 0] * sine + result[:, 1] * cosine
    result[:, 0] = x
    result[:, 1] = y
    result += registration.center * np.array([side, 1, 1])

    transformed_faces = faces.copy()
    if side < 0:
        transformed_faces = transformed_faces[:, [0, 2, 1]]
    return result, transformed_faces


def bilateral_hand_system(
    source: trimesh.Trimesh,
    skin: trimesh.Trimesh,
    registration: HandLODRegistration,
    scale: float,
    preserve_components: bool,
) -> tuple[trimesh.Trimesh, dict[str, float | int]]:
    vertices: list[np.ndarray] = []
    faces: list[np.ndarray] = []
    offset = 0
    for side in (1, -1):
        transformed_vertices, transformed_faces = transform_hand(
            np.asarray(source.vertices),
            np.asarray(source.faces),
            registration,
            scale,
            side,
        )
        vertices.append(transformed_vertices)
        faces.append(transformed_faces + offset)
        offset += len(transformed_vertices)

    combined_vertices = np.concatenate(vertices)
    combined_faces = np.concatenate(faces)
    fitted, report = fit_inside_surface(
        skin,
        combined_vertices,
        margin=0.002,
        faces=combined_faces,
        preserve_components=preserve_components,
    )
    return (
        trimesh.Trimesh(
            vertices=fitted,
            faces=combined_faces,
            process=False,
            validate=False,
        ),
        report,
    )


def thumb_lateral_offsets(
    source: trimesh.Trimesh,
    fitted: trimesh.Trimesh,
    registration: HandLODRegistration,
) -> tuple[float, float]:
    """Confirm that NIMBLE's positive-X thumb anatomy faces away from the body."""
    source_vertices = np.asarray(source.vertices)
    fitted_vertices = np.asarray(fitted.vertices)
    thumb_vertices = source_vertices[:, 0] > np.quantile(source_vertices[:, 0], 0.82)
    vertices_per_hand = len(source_vertices)
    offsets = (
        float(
            fitted_vertices[:vertices_per_hand][thumb_vertices, 0].mean()
            - registration.center[0]
        ),
        float(
            -fitted_vertices[vertices_per_hand:][thumb_vertices, 0].mean()
            - registration.center[0]
        ),
    )
    if min(offsets) <= 0.0:
        raise RuntimeError(
            "Full-body hand transform placed thumb anatomy toward the body's midline"
        )
    return offsets


def write_usdc(
    mesh: trimesh.Trimesh,
    destination: Path,
    name: str,
    temporary_directory: Path,
) -> None:
    source = temporary_directory / f"{name}.usda"
    write_usda(mesh, source, name)
    subprocess.run(
        ["/usr/bin/usdcat", str(source), "-o", str(destination)],
        check=True,
    )
    destination.chmod(0o644)


def main() -> None:
    arguments = parse_arguments()
    resource_directory = arguments.resource_directory.resolve()
    source_directory = arguments.source_directory.resolve()
    with tempfile.TemporaryDirectory(prefix="littlewindows-hand-lod-") as value:
        temporary_directory = Path(value)
        for variant, registration in REGISTRATIONS.items():
            rendered_ghost_skin = usd_to_mesh(
                resource_directory / f"BodySkin{variant}Low.usdc",
                temporary_directory,
            )
            body = usd_to_mesh(
                source_directory / f"MuscularSystem{variant}Medium.usdc",
                temporary_directory,
            )
            body_lod = clipped_body_system(body, registration)
            write_usdc(
                body_lod,
                resource_directory / f"MuscularSystem{variant}FullBodyLOD.usdc",
                f"MuscularSystem{variant}FullBodyLOD",
                temporary_directory,
            )

            for system, scale, preserve_components in (
                ("Muscular", registration.muscle_scale, False),
                ("Tendon", registration.tendon_scale, True),
                ("Skeleton", registration.skeleton_scale, True),
                ("Joint", registration.joint_scale, True),
                ("NerveSheath", registration.nerve_scale, True),
                ("Nervous", registration.nerve_scale, True),
            ):
                source = usd_to_mesh(
                    resource_directory / f"Hand{system}System{variant}.usdc",
                    temporary_directory,
                )
                hand_lod, report = bilateral_hand_system(
                    source,
                    rendered_ghost_skin,
                    registration,
                    scale,
                    preserve_components=preserve_components,
                )
                hand_lod, inset_report = inset_hand_vertices(
                    hand_lod,
                    rendered_ghost_skin,
                    registration,
                    margin=0.0035,
                )
                orientation_report = {}
                if system == "Skeleton":
                    right_offset, left_offset = thumb_lateral_offsets(
                        source,
                        hand_lod,
                        registration,
                    )
                    orientation_report = {
                        "right_thumb_lateral_offset": right_offset,
                        "left_thumb_lateral_offset": left_offset,
                    }
                write_usdc(
                    hand_lod,
                    resource_directory / f"Hand{system}System{variant}FullBodyLOD.usdc",
                    f"Hand{system}System{variant}FullBodyLOD",
                    temporary_directory,
                )
                print({
                    "variant": variant,
                    "system": system,
                    **report,
                    "ghost_outside_after": inset_report["outside_after"],
                    "ghost_minimum_after": inset_report["minimum_after"],
                    "ghost_maximum_correction": inset_report["maximum_correction"],
                    **orientation_report,
                })

            for system, source_name in (
                ("Skeleton", f"SkeletonSystem{variant}.usdc"),
                ("Joint", f"JointSystem{variant}.usdc"),
                ("Nervous", f"NervousSystem{variant}Medium.usdc"),
            ):
                source = usd_to_mesh(
                    source_directory / source_name,
                    temporary_directory,
                )
                clipped = clipped_body_system(source, registration)
                write_usdc(
                    clipped,
                    resource_directory / f"{system}System{variant}FullBodyLOD.usdc",
                    f"{system}System{variant}FullBodyLOD",
                    temporary_directory,
                )

            for vascular_kind in ("Arterial", "Venous"):
                source = usd_to_mesh(
                    source_directory / f"Vascular{vascular_kind}{variant}.usdc",
                    temporary_directory,
                )
                body_vascular = clipped_body_system(source, registration)
                hand_routes = usd_to_mesh(
                    resource_directory
                    / f"HandNervousSystem{variant}FullBodyLOD.usdc",
                    temporary_directory,
                )
                hand_vascular = split_hand_surface_network(
                    hand_routes,
                    front_half=vascular_kind == "Arterial",
                )
                inset = merged_mesh(body_vascular, hand_vascular)
                hand_vertices = np.asarray(hand_vascular.vertices)
                hand_faces = np.asarray(hand_vascular.faces)
                face_vertices = hand_vertices[hand_faces]
                samples = np.concatenate(
                    (
                        hand_vertices,
                        face_vertices.mean(axis=1),
                        (face_vertices[:, 0] + face_vertices[:, 1]) * 0.5,
                        (face_vertices[:, 1] + face_vertices[:, 2]) * 0.5,
                        (face_vertices[:, 2] + face_vertices[:, 0]) * 0.5,
                    )
                )
                distances, _, _ = signed_surface_distance(
                    rendered_ghost_skin,
                    samples,
                )
                report = {
                    "hand_vertices": len(hand_vertices),
                    "surface_samples": len(samples),
                    "outside_after": int(np.count_nonzero(distances < 0.0)),
                    "minimum_after": float(distances.min()),
                }
                write_usdc(
                    inset,
                    resource_directory / f"Vascular{vascular_kind}{variant}FullBodyLOD.usdc",
                    f"Vascular{vascular_kind}{variant}FullBodyLOD",
                    temporary_directory,
                )
                print({"variant": variant, "system": vascular_kind, **report})


if __name__ == "__main__":
    main()
