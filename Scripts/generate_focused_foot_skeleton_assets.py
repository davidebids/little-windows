#!/usr/bin/env python3
"""Generate clean focused foot bones and joint markers from Z-Anatomy."""

from __future__ import annotations

import argparse
import tempfile
import urllib.request
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from scipy.spatial import cKDTree
import trimesh

from generate_foot_surface_assets import internal_sole_presentation, write_usdc
from fit_focused_foot_assets import fit_face_interiors
from register_anatomy_volume import (
    AFFINE_TRANSFORMS,
    fit_inside_surface,
    signed_surface_distance,
    usd_to_mesh,
)


SKELETON_URL = (
    "https://raw.githubusercontent.com/DrMuratAltun/"
    "anatomi-simulatoru/main/systems/iskelet.glb"
)

FOOT_BONE_PATTERN = (
    "metatarsal",
    "finger of foot",
    "sesamoid bones of foot",
    "calcaneus",
    "talus",
    "navicular",
    "cuboid",
    "cuneiform",
)

REQUIRED_FOOT_BONES = {
    "Talus",
    "Navicular bone",
    "Medial cuneiform bone",
    "Intermediate cuneiform bone",
    "Lateral cuneiform bone",
    "Cuboid bone",
    "Calcaneus",
    "Sesamoid bones of foot",
    *(f"{ordinal.title()} metatarsal bone" for ordinal in (
        "first", "second", "third", "fourth", "fifth"
    )),
    "Proximal phalanx of first finger of foot",
    "Distal phalanx of first finger of foot",
    *(f"{segment} phalanx of {ordinal} finger of foot"
      for ordinal in ("second", "third", "fourth", "fifth")
      for segment in ("Proximal", "Middle", "Distal")),
}


@dataclass(frozen=True)
class GeneratedSystem:
    skeleton: trimesh.Trimesh
    joints: trimesh.Trimesh


def local_source(source: str, temporary_directory: Path) -> Path:
    path = Path(source)
    if path.exists():
        return path
    if source.startswith(("https://", "http://")):
        destination = temporary_directory / "z-anatomy-skeleton.glb"
        urllib.request.urlretrieve(source, destination)
        return destination
    raise FileNotFoundError(source)


def canonical_name(node_name: str) -> str:
    return node_name.rsplit(".", 1)[0]


def is_foot_bone(node_name: str, include_lower_leg: bool) -> bool:
    lowered = node_name.lower()
    return any(value in lowered for value in FOOT_BONE_PATTERN) or (
        include_lower_leg and (lowered.startswith("tibia.") or lowered.startswith("fibula."))
    )


def transformed_bones(
    scene: trimesh.Scene,
    variant: str,
    side: str,
    include_lower_leg: bool,
    upper_y: float,
) -> list[tuple[str, trimesh.Trimesh]]:
    suffix = ".l" if side == "Left" else ".r"
    transform = AFFINE_TRANSFORMS[variant.lower()]
    result: list[tuple[str, trimesh.Trimesh]] = []
    for node_name in scene.graph.nodes_geometry:
        if not node_name.endswith(suffix) or not is_foot_bone(node_name, include_lower_leg):
            continue
        node_transform, geometry_name = scene.graph[node_name]
        mesh = scene.geometry[geometry_name].copy()
        mesh.apply_transform(node_transform)
        vertices = np.asarray(mesh.vertices).copy()
        vertices = vertices * transform["scale"] + transform["translation"]
        mesh.vertices = vertices
        selected_faces = np.asarray(mesh.faces)[
            np.all(vertices[np.asarray(mesh.faces), 1] <= upper_y, axis=1)
        ]
        if len(selected_faces) == 0:
            continue
        mesh = trimesh.Trimesh(vertices, selected_faces, process=True)
        mesh.remove_unreferenced_vertices()
        result.append((canonical_name(node_name), mesh))
    return result


def fit_bones_to_skin(
    bones: list[tuple[str, trimesh.Trimesh]],
    skin: trimesh.Trimesh,
) -> tuple[list[tuple[str, trimesh.Trimesh]], dict[str, float | int]]:
    source = trimesh.util.concatenate([mesh for _, mesh in bones])
    source_min, source_max = source.bounds
    skin_min, skin_max = skin.bounds
    skin_extent = skin_max - skin_min
    target_min = skin_min + skin_extent * np.asarray((0.095, 0.012, 0.045))
    target_max = skin_max - skin_extent * np.asarray((0.095, 0.006, 0.055))
    scale = (target_max - target_min) / (source_max - source_min)

    fitted_bones: list[tuple[str, trimesh.Trimesh]] = []
    for name, mesh in bones:
        fitted = mesh.copy()
        source_vertices = np.asarray(mesh.vertices)
        fitted_vertices = target_min + (source_vertices - source_min) * scale
        fitted.vertices = fitted_vertices
        fitted_bones.append((name, fitted))

    combined = trimesh.util.concatenate([mesh for _, mesh in fitted_bones])
    fitted_vertices, report = fit_inside_surface(
        skin,
        np.asarray(combined.vertices),
        margin=0.00045,
        faces=np.asarray(combined.faces),
        preserve_components=True,
    )
    offset = 0
    final_bones: list[tuple[str, trimesh.Trimesh]] = []
    for name, mesh in fitted_bones:
        count = len(mesh.vertices)
        fitted = mesh.copy()
        fitted.vertices = fitted_vertices[offset : offset + count]
        final_bones.append((name, fitted))
        offset += count
    return final_bones, report


def center_hindfoot_assembly(
    bones: list[tuple[str, trimesh.Trimesh]],
    skin: trimesh.Trimesh,
) -> list[tuple[str, trimesh.Trimesh]]:
    """Center the heel smoothly while leaving the five fitted rays unchanged."""
    by_name = dict(bones)
    calcaneus = by_name.get("Calcaneus")
    if calcaneus is None:
        return bones

    calcaneus_z = float(calcaneus.centroid[2])
    shell_center_x = shell_center_x_at_z(skin, calcaneus_z)
    shift_x = shell_center_x - float(calcaneus.centroid[0])
    minimum_z = float(skin.bounds[0, 2])
    length = float(skin.extents[2])

    result: list[tuple[str, trimesh.Trimesh]] = []
    for name, mesh in bones:
        centered = mesh.copy()
        vertices = np.asarray(centered.vertices).copy()
        longitudinal = np.clip((vertices[:, 2] - minimum_z) / length, 0.0, 1.0)
        transition = np.clip((longitudinal - 0.30) / 0.32, 0.0, 1.0)
        smooth_transition = transition * transition * (3.0 - 2.0 * transition)
        vertices[:, 0] += shift_x * (1.0 - smooth_transition)
        centered.vertices = vertices
        centered.fix_normals()
        result.append((name, centered))
    return result


def transform_bone_assembly(
    bones: list[tuple[str, trimesh.Trimesh]],
    matrix: np.ndarray,
) -> list[tuple[str, trimesh.Trimesh]]:
    """Apply one anatomical presentation transform without refitting components."""
    result: list[tuple[str, trimesh.Trimesh]] = []
    for name, mesh in bones:
        transformed = mesh.copy()
        transformed.apply_transform(matrix)
        transformed.fix_normals()
        result.append((name, transformed))
    return result


def cross_section_center(
    vertices: np.ndarray,
    y: float,
    sample_count: int,
) -> np.ndarray:
    """Return a robust X/Z center close to one vertical position."""
    count = min(sample_count, len(vertices))
    sample = vertices[
        np.argpartition(np.abs(vertices[:, 1] - y), count - 1)[:count]
    ]
    return np.asarray(
        (
            (
                np.quantile(sample[:, 0], 0.06)
                + np.quantile(sample[:, 0], 0.94)
            )
            * 0.5,
            (
                np.quantile(sample[:, 2], 0.06)
                + np.quantile(sample[:, 2], 0.94)
            )
            * 0.5,
        )
    )


def register_lower_leg_to_skin(
    bones: list[tuple[str, trimesh.Trimesh]],
    foot_bones: list[tuple[str, trimesh.Trimesh]],
    skin: trimesh.Trimesh,
) -> tuple[list[tuple[str, trimesh.Trimesh]], list[dict[str, float | int]]]:
    """Register tibia/fibula along the real leg centerline without swapping them."""
    by_name = dict(bones)
    tibia = by_name.get("Tibia")
    talus = dict(foot_bones).get("Talus")
    if tibia is None or talus is None:
        raise ValueError("Focused side skeleton requires a tibia and talus")

    leg_vertices = np.concatenate([np.asarray(mesh.vertices) for _, mesh in bones])
    tibia_vertices = np.asarray(tibia.vertices)
    talus_vertices = np.asarray(talus.vertices)
    talus_cutoff = np.quantile(talus_vertices[:, 1], 0.86)
    proximal_talus_y = float(
        talus_vertices[talus_vertices[:, 1] >= talus_cutoff, 1].mean()
    )

    # The fibula extends below the tibial plafond. Anchor vertical scaling to
    # the tibia so that this real anatomical difference is retained.
    source_min_y = float(tibia_vertices[:, 1].min())
    source_max_y = float(leg_vertices[:, 1].max())
    target_min_y = proximal_talus_y - 0.001
    target_max_y = float(skin.bounds[1, 1] - 0.003)
    y_scale = (target_max_y - target_min_y) / (source_max_y - source_min_y)

    source_sample_y = np.linspace(float(leg_vertices[:, 1].min()), source_max_y, 18)
    source_centers = np.asarray(
        [cross_section_center(leg_vertices, y, 56) for y in source_sample_y]
    )
    target_sample_y = target_min_y + (source_sample_y - source_min_y) * y_scale
    skin_vertices = np.asarray(skin.vertices)
    target_centers = np.asarray(
        [cross_section_center(skin_vertices, y, 128) for y in target_sample_y]
    )

    registered_bones: list[tuple[str, trimesh.Trimesh]] = []
    reports: list[dict[str, float | int]] = []
    for name, mesh in bones:
        registered = mesh.copy()
        vertices = np.asarray(registered.vertices).copy()
        source_center_x = np.interp(
            vertices[:, 1], source_sample_y, source_centers[:, 0]
        )
        source_center_z = np.interp(
            vertices[:, 1], source_sample_y, source_centers[:, 1]
        )
        target_y = target_min_y + (vertices[:, 1] - source_min_y) * y_scale
        target_center_x = np.interp(
            target_y, target_sample_y, target_centers[:, 0]
        )
        target_center_z = np.interp(
            target_y, target_sample_y, target_centers[:, 1]
        )
        # Leave a small soft-tissue margin around both shafts. This reduces
        # corrective deformation at the malleoli while retaining their true
        # medial/lateral ordering and relative spacing.
        cross_section_scale = 0.93
        vertices[:, 0] = target_center_x + (
            vertices[:, 0] - source_center_x
        ) * cross_section_scale
        vertices[:, 2] = target_center_z + (
            vertices[:, 2] - source_center_z
        ) * cross_section_scale
        vertices[:, 1] = target_y
        registered.vertices = vertices

        fitted_vertices, report = fit_face_interiors(
            skin,
            np.asarray(registered.vertices),
            np.asarray(registered.faces),
        )
        registered.vertices = fitted_vertices
        registered.fix_normals()
        if int(report["outside_after"]) != 0:
            raise ValueError(f"{name} remains outside the focused foot shell")
        if float(report["maximum_iteration_correction"]) > 0.005:
            raise ValueError(
                f"{name} needs excessive lower-leg correction: "
                f"{float(report['maximum_iteration_correction']):.6f}m"
            )
        registered_bones.append((name, registered))
        reports.append(report)
    return registered_bones, reports


def shell_center_x_at_z(skin: trimesh.Trimesh, z: float) -> float:
    """Return a robust shell centerline sample at one plantar position."""
    skin_vertices = np.asarray(skin.vertices)
    sample_count = min(128, len(skin_vertices))
    sample = skin_vertices[
        np.argpartition(np.abs(skin_vertices[:, 2] - z), sample_count - 1)[
            :sample_count
        ]
    ]
    return float(
        (np.quantile(sample[:, 0], 0.08) + np.quantile(sample[:, 0], 0.92))
        * 0.5
    )


def validate_bone_inventory(bones: list[tuple[str, trimesh.Trimesh]]) -> None:
    """Fail generation if any named component of the foot is missing."""
    names = {name for name, _ in bones}
    missing = sorted(REQUIRED_FOOT_BONES - names)
    if missing:
        raise ValueError(f"Focused foot skeleton is missing: {', '.join(missing)}")


def validate_plantar_landmarks(
    bones: list[tuple[str, trimesh.Trimesh]],
    skin: trimesh.Trimesh,
    side: str,
) -> dict[str, float | int]:
    """Reject contained but mirrored, compressed, or off-center assemblies."""
    validate_bone_inventory(bones)
    by_name = dict(bones)
    hallux_x = float(
        by_name["Distal phalanx of first finger of foot"].centroid[0]
    )
    fifth_x = float(
        by_name["Distal phalanx of fifth finger of foot"].centroid[0]
    )
    medial_delta = hallux_x - fifth_x
    minimum_medial_delta = float(skin.extents[0] * 0.38)
    # Global X increases toward the body's left. The hallux must therefore be
    # closer to the midline than the fifth toe: lower X on the left foot and
    # higher X on the right foot.
    medial_is_correct = (
        medial_delta <= -minimum_medial_delta
        if side == "Left"
        else medial_delta >= minimum_medial_delta
    )
    if not medial_is_correct:
        raise ValueError(
            f"{side} plantar skeleton has a mirrored or compressed toe fan: "
            f"hallux/fifth delta={medial_delta:.6f}"
        )

    calcaneus = by_name["Calcaneus"]
    heel_offset = abs(
        float(calcaneus.centroid[0])
        - shell_center_x_at_z(skin, float(calcaneus.centroid[2]))
    )
    maximum_heel_offset = float(skin.extents[0] * 0.08)
    if heel_offset > maximum_heel_offset:
        raise ValueError(
            f"{side} plantar calcaneus is off the heel centerline by "
            f"{heel_offset:.6f}m"
        )

    assembly = trimesh.util.concatenate([mesh for _, mesh in bones])
    width_fill = float(assembly.extents[0] / skin.extents[0])
    length_fill = float(assembly.extents[2] / skin.extents[2])
    if width_fill < 0.70 or length_fill < 0.84:
        raise ValueError(
            f"{side} plantar skeleton is compressed: "
            f"width={width_fill:.3f}, length={length_fill:.3f}"
        )
    return {
        "named_bones": len(bones),
        "medial_delta_mm": medial_delta * 1000.0,
        "heel_offset_mm": heel_offset * 1000.0,
        "width_fill": width_fill,
        "length_fill": length_fill,
    }


def validate_side_landmarks(
    bones: list[tuple[str, trimesh.Trimesh]],
    side: str,
) -> dict[str, float | int]:
    """Reject a contained side assembly with swapped shafts or a detached ankle."""
    by_name = dict(bones)
    tibia = by_name.get("Tibia")
    fibula = by_name.get("Fibula")
    talus = by_name.get("Talus")
    if tibia is None or fibula is None or talus is None:
        raise ValueError("Focused side skeleton is missing tibia, fibula, or talus")

    shaft_delta = float(tibia.centroid[0] - fibula.centroid[0])
    shaft_order_is_correct = shaft_delta < 0 if side == "Left" else shaft_delta > 0
    if not shaft_order_is_correct:
        raise ValueError(
            f"{side} tibia/fibula are laterally swapped: delta={shaft_delta:.6f}"
        )

    tibia_vertices = np.asarray(tibia.vertices)
    talus_vertices = np.asarray(talus.vertices)
    tibia_to_talus, _ = cKDTree(talus_vertices).query(tibia_vertices, k=1)
    ankle_gap = float(tibia_to_talus.min())
    if ankle_gap > 0.006:
        raise ValueError(
            f"{side} tibia is detached from the talus by {ankle_gap:.6f}m"
        )
    return {
        "shaft_delta_mm": shaft_delta * 1000.0,
        "ankle_gap_mm": ankle_gap * 1000.0,
    }


def closest_joint_center(first: trimesh.Trimesh, second: trimesh.Trimesh) -> np.ndarray:
    first_vertices = np.asarray(first.vertices)
    second_vertices = np.asarray(second.vertices)
    distances, indices = cKDTree(second_vertices).query(first_vertices, k=1)
    first_index = int(np.argmin(distances))
    return (first_vertices[first_index] + second_vertices[int(indices[first_index])]) * 0.5


def joint_system(
    bones: list[tuple[str, trimesh.Trimesh]],
    skin: trimesh.Trimesh,
) -> trimesh.Trimesh:
    by_name = dict(bones)
    pairs: list[tuple[str, str, float]] = [
        ("Tibia", "Talus", 0.0072),
        ("Talus", "Calcaneus", 0.0052),
        ("Talus", "Navicular bone", 0.0045),
        ("Calcaneus", "Cuboid bone", 0.0045),
        ("Navicular bone", "Medial cuneiform bone", 0.0038),
        ("Navicular bone", "Intermediate cuneiform bone", 0.0035),
        ("Navicular bone", "Lateral cuneiform bone", 0.0035),
        ("Medial cuneiform bone", "First metatarsal bone", 0.0035),
        ("Intermediate cuneiform bone", "Second metatarsal bone", 0.0032),
        ("Lateral cuneiform bone", "Third metatarsal bone", 0.0032),
        ("Cuboid bone", "Fourth metatarsal bone", 0.0032),
        ("Cuboid bone", "Fifth metatarsal bone", 0.0032),
    ]
    ordinals = ("first", "second", "third", "fourth", "fifth")
    for ordinal in ordinals:
        pairs.append(
            (
                f"{ordinal.title()} metatarsal bone",
                f"Proximal phalanx of {ordinal} finger of foot",
                0.0028,
            )
        )
    pairs.append(
        (
            "Proximal phalanx of first finger of foot",
            "Distal phalanx of first finger of foot",
            0.0025,
        )
    )
    for ordinal in ordinals[1:]:
        pairs.extend(
            (
                (
                    f"Proximal phalanx of {ordinal} finger of foot",
                    f"Middle phalanx of {ordinal} finger of foot",
                    0.0022,
                ),
                (
                    f"Middle phalanx of {ordinal} finger of foot",
                    f"Distal phalanx of {ordinal} finger of foot",
                    0.0020,
                ),
            )
        )

    size_scale = float(skin.extents[0] / 0.12)
    spheres: list[trimesh.Trimesh] = []
    for first_name, second_name, radius in pairs:
        if first_name not in by_name or second_name not in by_name:
            continue
        center = closest_joint_center(by_name[first_name], by_name[second_name])
        signed_distance, nearest, triangle_ids = signed_surface_distance(
            skin,
            center.reshape(1, 3),
        )
        if signed_distance[0] <= 0:
            center = (
                nearest[0]
                - skin.face_normals[triangle_ids[0]] * 0.0008
            )
        _, clearance, _ = skin.nearest.on_surface(center.reshape(1, 3))
        fitted_radius = min(radius * size_scale, max(0.00055, clearance[0] * 0.68))
        sphere = trimesh.creation.icosphere(subdivisions=2, radius=fitted_radius)
        sphere.apply_translation(center)
        spheres.append(sphere)
    return trimesh.util.concatenate(spheres)


def generate(source: str, resources: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="littlewindows-focused-skeleton-") as value:
        temporary_directory = Path(value)
        scene = trimesh.load(
            local_source(source, temporary_directory),
            force="scene",
        )
        for variant in ("Female", "Male"):
            for side in ("Left", "Right"):
                skin = usd_to_mesh(
                    resources / f"FootSurface{variant}{side}.usdc",
                    temporary_directory,
                )
                bones = transformed_bones(
                    scene,
                    variant,
                    side,
                    include_lower_leg=True,
                    upper_y=skin.bounds[1, 1] + 0.0001,
                )
                source_foot_bones = [
                    (name, mesh.copy())
                    for name, mesh in bones
                    if name not in {"Tibia", "Fibula"}
                ]
                source_lower_leg_bones = [
                    (name, mesh.copy())
                    for name, mesh in bones
                    if name in {"Tibia", "Fibula"}
                ]
                validate_bone_inventory(source_foot_bones)

                target_sole_skin = usd_to_mesh(
                    resources / f"FootSoleSurface{variant}{side}.usdc",
                    temporary_directory,
                )
                sole_skin, sole_warp = internal_sole_presentation(
                    skin,
                    target_sole_skin,
                    variant,
                )
                # The side-view skin affine can be fully contained while still
                # leaving the plantar skeleton short and shifted to one side.
                # Fit the complete named foot-bone assembly directly to the
                # actual sole shell without mirroring it. The source already
                # has the hallux on the medial side of each foot; mirroring the
                # assembly places the great-toe bones under the little-toe skin.
                sole_bones, sole_report = fit_bones_to_skin(
                    source_foot_bones,
                    sole_skin,
                )
                sole_bones = center_hindfoot_assembly(sole_bones, sole_skin)
                face_fitted_sole_bones: list[tuple[str, trimesh.Trimesh]] = []
                sole_face_reports: list[dict[str, float | int]] = []
                for bone_name, bone in sole_bones:
                    fitted_vertices, face_report = fit_face_interiors(
                        sole_skin,
                        np.asarray(bone.vertices),
                        np.asarray(bone.faces),
                    )
                    fitted = bone.copy()
                    fitted.vertices = fitted_vertices
                    face_fitted_sole_bones.append((bone_name, fitted))
                    sole_face_reports.append(face_report)
                sole_bones = face_fitted_sole_bones
                sole_landmark_report = validate_plantar_landmarks(
                    sole_bones,
                    sole_skin,
                    side,
                )

                # Use the validated plantar assembly as the canonical foot for
                # the side view. Inverting the exact shell presentation warp
                # preserves all five rays and their depth when the user drags
                # away from the default lateral camera.
                side_foot_bones = transform_bone_assembly(
                    sole_bones,
                    np.linalg.inv(sole_warp.matrix),
                )
                registered_lower_leg_bones, lower_leg_reports = (
                    register_lower_leg_to_skin(
                        source_lower_leg_bones,
                        side_foot_bones,
                        skin,
                    )
                )
                side_bones = side_foot_bones + registered_lower_leg_bones
                side_landmark_report = validate_side_landmarks(side_bones, side)
                side_report = {
                    "inverse_plantar_registration": 1,
                    "lower_leg_face_fits": len(lower_leg_reports),
                    "lower_leg_outside_after": sum(
                        int(report["outside_after"])
                        for report in lower_leg_reports
                    ),
                    "lower_leg_maximum_correction": max(
                        float(report["maximum_iteration_correction"])
                        for report in lower_leg_reports
                    ),
                    **side_landmark_report,
                }

                for prefix, presentation_bones, presentation_skin, report in (
                    ("Foot", side_bones, skin, side_report),
                    ("FootSole", sole_bones, sole_skin, sole_report),
                ):
                    skeleton = trimesh.util.concatenate(
                        [mesh for _, mesh in presentation_bones]
                    )
                    joints = joint_system(presentation_bones, presentation_skin)
                    for system_name, mesh in (
                        ("SkeletonSystem", skeleton),
                        ("JointSystem", joints),
                    ):
                        if prefix == "Foot":
                            fitted_vertices, face_report = fit_face_interiors(
                                presentation_skin,
                                np.asarray(mesh.vertices),
                                np.asarray(mesh.faces),
                            )
                            mesh.vertices = fitted_vertices
                        else:
                            face_report = {
                                "direct_plantar_registration": 1,
                                "bone_face_fits": len(sole_face_reports),
                                **sole_landmark_report,
                            }
                        name = f"{prefix}{system_name}{variant}{side}"
                        destination = resources / f"{name}.usdc"
                        write_usdc(mesh, destination, name)
                        print(
                            f"{destination}: {len(mesh.vertices)} vertices, "
                            f"{len(mesh.faces)} faces, fit={report}, "
                            f"faces={face_report}"
                        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default=SKELETON_URL)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parents[1]
        / "LittleWindows"
        / "Resources"
        / "BodyAnatomy",
    )
    arguments = parser.parse_args()
    generate(arguments.source, arguments.output)


if __name__ == "__main__":
    main()
