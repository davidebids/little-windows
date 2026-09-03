#!/usr/bin/env python3
"""Fit focused foot face interiors inside their registered skin shells."""

from __future__ import annotations

import argparse
import subprocess
import tempfile
from pathlib import Path

import numpy as np

from register_anatomy_volume import (
    signed_surface_distance,
    usd_to_mesh,
    write_usda,
)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "resource_directory",
        nargs="?",
        type=Path,
        default=Path("LittleWindows/Resources/BodyAnatomy"),
    )
    return parser.parse_args()


def samples_and_owners(
    vertices: np.ndarray,
    faces: np.ndarray,
) -> tuple[np.ndarray, list[np.ndarray]]:
    face_vertices = vertices[faces]
    samples = np.concatenate(
        (
            vertices,
            face_vertices.mean(axis=1),
            (face_vertices[:, 0] + face_vertices[:, 1]) * 0.5,
            (face_vertices[:, 1] + face_vertices[:, 2]) * 0.5,
            (face_vertices[:, 2] + face_vertices[:, 0]) * 0.5,
        )
    )
    owners = [
        *[np.asarray((index,), dtype=np.int64) for index in range(len(vertices))],
        *[face for face in faces],
        *[face[[0, 1]] for face in faces],
        *[face[[1, 2]] for face in faces],
        *[face[[2, 0]] for face in faces],
    ]
    return samples, owners


def fit_face_interiors(
    skin,
    vertices: np.ndarray,
    faces: np.ndarray,
    margin: float = 0.00015,
) -> tuple[np.ndarray, dict[str, float | int]]:
    result = vertices.copy()
    maximum_correction = 0.0
    initial_outside = 0

    for iteration in range(18):
        samples, owners = samples_and_owners(result, faces)
        distances, closest, triangle_ids = signed_surface_distance(skin, samples)
        outside_indices = np.flatnonzero(distances < margin)
        if iteration == 0:
            initial_outside = int(np.count_nonzero(distances < 0.0))
            if initial_outside == 0:
                return result, {
                    "outside_before": 0,
                    "outside_after": 0,
                    "minimum_after": float(distances.min()),
                    "maximum_iteration_correction": 0.0,
                }
        if len(outside_indices) == 0:
            break

        corrections = np.zeros_like(result)
        counts = np.zeros(len(result), dtype=np.float64)
        normals = skin.face_normals[triangle_ids[outside_indices]]
        targets = closest[outside_indices] - normals * margin
        deltas = targets - samples[outside_indices]
        for sample_index, delta in zip(outside_indices, deltas):
            indices = owners[int(sample_index)]
            corrections[indices] += delta
            counts[indices] += 1.0

        changed = counts > 0
        corrections[changed] /= counts[changed, None]
        lengths = np.linalg.norm(corrections, axis=1)
        over_limit = lengths > 0.003
        corrections[over_limit] *= (0.003 / lengths[over_limit])[:, None]
        result[changed] += corrections[changed]
        maximum_correction = max(
            maximum_correction,
            float(lengths[changed].max(initial=0.0)),
        )

    final_samples, _ = samples_and_owners(result, faces)
    final_distances, _, _ = signed_surface_distance(skin, final_samples)
    return result, {
        "outside_before": initial_outside,
        "outside_after": int(np.count_nonzero(final_distances < 0.0)),
        "minimum_after": float(final_distances.min()),
        "maximum_iteration_correction": maximum_correction,
    }


def main() -> None:
    arguments = parse_arguments()
    resources = arguments.resource_directory.resolve()
    with tempfile.TemporaryDirectory(prefix="littlewindows-focused-foot-fit-") as value:
        temporary_directory = Path(value)
        for variant in ("Female", "Male"):
            for side in ("Left", "Right"):
                skin = usd_to_mesh(
                    resources / f"FootSurface{variant}{side}.usdc",
                    temporary_directory,
                )
                for system in (
                    "MuscularSystem",
                    "SkeletonSystem",
                    "JointSystem",
                    "NerveSheathSystem",
                    "NervousSystem",
                ):
                    path = resources / f"Foot{system}{variant}{side}.usdc"
                    mesh = usd_to_mesh(path, temporary_directory)
                    vertices, report = fit_face_interiors(
                        skin,
                        np.asarray(mesh.vertices),
                        np.asarray(mesh.faces),
                    )
                    if report["outside_before"] == 0:
                        print({"asset": path.name, **report})
                        continue

                    mesh.vertices = vertices
                    usda = temporary_directory / f"{path.stem}-fitted.usda"
                    write_usda(mesh, usda, path.stem)
                    subprocess.run(
                        ("/usr/bin/usdcat", str(usda), "-o", str(path)),
                        check=True,
                        capture_output=True,
                        text=True,
                    )
                    print({"asset": path.name, **report})


if __name__ == "__main__":
    main()
