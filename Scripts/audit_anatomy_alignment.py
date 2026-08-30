#!/usr/bin/env python3
"""Measure bundled anatomy and focused extremity faces against rendered skin."""

from __future__ import annotations

import argparse
import json
import tempfile
from pathlib import Path

import numpy as np

from register_anatomy_volume import signed_surface_distance, usd_to_mesh
from generate_full_body_hand_lod import REGISTRATIONS


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "resource_directory",
        nargs="?",
        type=Path,
        default=Path("LittleWindows/Resources/BodyAnatomy"),
    )
    parser.add_argument(
        "--focused-feet-only",
        action="store_true",
        help="Skip the slower whole-body and full-body hand audits.",
    )
    return parser.parse_args()


def assets_for_variant(resource_directory: Path, variant: str) -> list[Path]:
    names = [
        f"MuscularSystem{variant}FullBodyLOD.usdc",
        f"HandMuscularSystem{variant}FullBodyLOD.usdc",
        f"HandTendonSystem{variant}FullBodyLOD.usdc",
        f"SkeletonSystem{variant}FullBodyLOD.usdc",
        f"HandSkeletonSystem{variant}FullBodyLOD.usdc",
        f"JointSystem{variant}FullBodyLOD.usdc",
        f"HandJointSystem{variant}FullBodyLOD.usdc",
        f"NervousSystem{variant}FullBodyLOD.usdc",
        f"HandNerveSheathSystem{variant}FullBodyLOD.usdc",
        f"HandNervousSystem{variant}FullBodyLOD.usdc",
        f"VascularArterial{variant}FullBodyLOD.usdc",
        f"VascularVenous{variant}FullBodyLOD.usdc",
    ]
    names.extend(
        path.name
        for path in sorted(resource_directory.glob(f"Organ*{variant}.usdc"))
    )
    return [resource_directory / name for name in names]


def surface_samples(
    vertices: np.ndarray,
    faces: np.ndarray,
    included_vertices: np.ndarray | None = None,
) -> np.ndarray:
    """Sample mesh interiors so a face cannot bridge outside a narrow finger gap."""
    face_vertices = vertices[faces]
    base_vertices = vertices if included_vertices is None else included_vertices
    return np.concatenate(
        (
            base_vertices,
            face_vertices.mean(axis=1),
            (face_vertices[:, 0] + face_vertices[:, 1]) * 0.5,
            (face_vertices[:, 1] + face_vertices[:, 2]) * 0.5,
            (face_vertices[:, 2] + face_vertices[:, 0]) * 0.5,
        )
    )


def main() -> None:
    arguments = parse_arguments()
    resource_directory = arguments.resource_directory.resolve()
    reports: list[dict[str, float | int | str]] = []
    with tempfile.TemporaryDirectory(prefix="littlewindows-anatomy-audit-") as value:
        temporary_directory = Path(value)
        for variant in ("Female", "Male"):
            skin_path = resource_directory / f"BodySkin{variant}Medium.usdc"
            if not arguments.focused_feet_only:
                skin = usd_to_mesh(skin_path, temporary_directory)
                for asset_path in assets_for_variant(resource_directory, variant):
                    mesh = usd_to_mesh(asset_path, temporary_directory)
                    distances, _, _ = signed_surface_distance(
                        skin,
                        np.asarray(mesh.vertices),
                    )
                    negative = distances < 0.0
                    report = {
                        "variant": variant.lower(),
                        "asset": asset_path.name,
                        "vertices": len(mesh.vertices),
                        "outside": int(np.count_nonzero(negative)),
                        "outside_percent": float(np.mean(negative) * 100),
                        "minimum_signed_distance_m": float(distances.min()),
                    }
                    reports.append(report)
                    print(json.dumps(report, sort_keys=True))

            for side in ("Left", "Right"):
                foot_presentations = (
                    (
                        "focused_foot_side",
                        f"FootSurface{variant}{side}.usdc",
                        (
                            f"FootMuscularSystem{variant}{side}.usdc",
                            f"FootSkeletonSystem{variant}{side}.usdc",
                            f"FootJointSystem{variant}{side}.usdc",
                            f"FootNerveSheathSystem{variant}{side}.usdc",
                            f"FootNervousSystem{variant}{side}.usdc",
                        ),
                    ),
                    (
                        "focused_foot_sole",
                        f"FootInternalSoleSurface{variant}{side}.usdc",
                        (
                            f"FootSoleMuscularSystem{variant}{side}.usdc",
                            f"FootSoleTendonSystem{variant}{side}.usdc",
                            f"FootSoleSkeletonSystem{variant}{side}.usdc",
                            f"FootSoleJointSystem{variant}{side}.usdc",
                            f"FootSoleNerveSheathSystem{variant}{side}.usdc",
                            f"FootSoleNervousSystem{variant}{side}.usdc",
                        ),
                    ),
                )
                for presentation, skin_name, asset_names in foot_presentations:
                    foot_skin = usd_to_mesh(
                        resource_directory / skin_name,
                        temporary_directory,
                    )
                    for name in asset_names:
                        mesh = usd_to_mesh(resource_directory / name, temporary_directory)
                        vertices = np.asarray(mesh.vertices)
                        faces = np.asarray(mesh.faces)
                        samples = surface_samples(vertices, faces)
                        distances, closest, _ = signed_surface_distance(foot_skin, samples)
                        negative = distances < 0.0
                        worst_index = int(np.argmin(distances))
                        report = {
                            "variant": variant.lower(),
                            "side": side.lower(),
                            "surface": presentation,
                            "asset": name,
                            "vertices": len(vertices),
                            "surface_samples": len(samples),
                            "outside_vertices": int(
                                np.count_nonzero(negative[: len(vertices)])
                            ),
                            "outside": int(np.count_nonzero(negative)),
                            "outside_percent": float(np.mean(negative) * 100),
                            "minimum_signed_distance_m": float(distances.min()),
                            "minimum_sample_position": samples[worst_index].tolist(),
                            "minimum_surface_position": closest[worst_index].tolist(),
                        }
                        reports.append(report)
                        print(json.dumps(report, sort_keys=True))

            if arguments.focused_feet_only:
                continue

            ghost_skin = usd_to_mesh(
                resource_directory / f"BodySkin{variant}Low.usdc",
                temporary_directory,
            )
            hand_names = [
                f"HandMuscularSystem{variant}FullBodyLOD.usdc",
                f"HandTendonSystem{variant}FullBodyLOD.usdc",
                f"HandSkeletonSystem{variant}FullBodyLOD.usdc",
                f"HandJointSystem{variant}FullBodyLOD.usdc",
                f"HandNerveSheathSystem{variant}FullBodyLOD.usdc",
                f"HandNervousSystem{variant}FullBodyLOD.usdc",
                f"VascularArterial{variant}FullBodyLOD.usdc",
                f"VascularVenous{variant}FullBodyLOD.usdc",
            ]
            registration = REGISTRATIONS[variant]
            for name in hand_names:
                mesh = usd_to_mesh(resource_directory / name, temporary_directory)
                vertices = np.asarray(mesh.vertices)
                faces = np.asarray(mesh.faces)
                if name.startswith("Vascular"):
                    distal_distance = (
                        (np.abs(vertices[:, 0]) - registration.wrist[0])
                        * registration.distal_axis[0]
                        + (vertices[:, 1] - registration.wrist[1])
                        * registration.distal_axis[1]
                    )
                    hand = (
                        (np.abs(vertices[:, 0]) > registration.wrist[0] - 0.05)
                        & (vertices[:, 1] > -0.14)
                        & (vertices[:, 1] < 0.22)
                        & (distal_distance > -0.03)
                    )
                    hand_faces = faces[np.all(hand[faces], axis=1)]
                    samples = surface_samples(vertices, hand_faces, vertices[hand])
                    vertex_count = int(np.count_nonzero(hand))
                elif name.startswith("HandMuscular"):
                    samples = vertices
                    vertex_count = len(vertices)
                else:
                    samples = surface_samples(vertices, faces)
                    vertex_count = len(vertices)
                distances, _, _ = signed_surface_distance(ghost_skin, samples)
                negative = distances < 0.0
                report = {
                    "variant": variant.lower(),
                    "surface": "rendered_ghost_hand",
                    "asset": name,
                    "vertices": vertex_count,
                    "surface_samples": len(samples),
                    "outside": int(np.count_nonzero(negative)),
                    "outside_percent": float(np.mean(negative) * 100),
                    "minimum_signed_distance_m": float(distances.min()),
                }
                reports.append(report)
                print(json.dumps(report, sort_keys=True))

    violations = sum(int(report["outside"]) for report in reports)
    print(json.dumps({"assets": len(reports), "outside_vertices": violations}))
    raise SystemExit(1 if violations else 0)


if __name__ == "__main__":
    main()
