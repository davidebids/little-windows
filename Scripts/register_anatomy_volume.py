#!/usr/bin/env python3
"""Register a Z-Anatomy system to the complete 3D HRA body volume.

The older registration script compared axis-aligned envelopes. That can hide
large depth errors: a vertex may be inside the front silhouette while sitting
outside the body at a side or oblique view. This script transports the source
atlas with a smooth volumetric cage and then measures every output vertex
against the actual skin triangles.

Requires numpy, scipy, trimesh, and rtree. The input is the output of the
component-preserving skeleton or vascular generator, before any later pose
correction.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from scipy.interpolate import RBFInterpolator
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
import trimesh


NUMBER_PATTERN = re.compile(
    rb"-?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?",
    re.IGNORECASE,
)

AFFINE_TRANSFORMS = {
    "female": {
        "scale": np.array([1.4025410479674654, 0.9753050896750797, 1.0994547118840001]),
        "translation": np.array([-0.004938842076231464, -0.7972659181835451, -0.07208135471513982]),
    },
    "male": {
        "scale": np.array([1.543802131255959, 1.0705058736700754, 1.0416830285459215]),
        "translation": np.array([-0.0003712963140640735, -0.9165427949470785, -0.009672623622318854]),
    },
}

SURFACE_MARGINS = {
    "muscles": 0.0015,
    "skeleton": 0.0045,
    "joints": 0.0035,
    "nerves": 0.0015,
    "arterial": 0.0025,
    "venous": 0.0025,
}


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("skin", type=Path)
    parser.add_argument("controls", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("variant", choices=AFFINE_TRANSFORMS)
    parser.add_argument("layer", choices=SURFACE_MARGINS)
    parser.add_argument("--already-registered", action="store_true")
    parser.add_argument("--outside-only", action="store_true")
    parser.add_argument("--preserve-components", action="store_true")
    parser.add_argument("--warp-only", action="store_true")
    return parser.parse_args()


def usd_to_mesh(path: Path, temporary_directory: Path) -> trimesh.Trimesh:
    usda = temporary_directory / f"{path.stem}-{len(list(temporary_directory.iterdir()))}.usda"
    subprocess.run(
        ["/usr/bin/usdcat", str(path.resolve()), "-o", str(usda)],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    source = usda.read_bytes()
    points_match = re.search(
        rb"point3f\[\] points\s*=\s*\[([\s\S]*?)\]",
        source,
    )
    indices_match = re.search(
        rb"int\[\] faceVertexIndices\s*=\s*\[([\s\S]*?)\]",
        source,
    )
    if not points_match or not indices_match:
        raise RuntimeError(f"Missing triangle mesh data in {path}")
    vertices = np.fromiter(
        (float(value) for value in NUMBER_PATTERN.findall(points_match.group(1))),
        dtype=np.float64,
    ).reshape((-1, 3))
    indices = np.fromiter(
        (int(value) for value in NUMBER_PATTERN.findall(indices_match.group(1))),
        dtype=np.int64,
    ).reshape((-1, 3))
    return trimesh.Trimesh(
        vertices=vertices,
        faces=indices,
        process=False,
        validate=False,
    )


def restore_source_atlas(vertices: np.ndarray, variant: str) -> np.ndarray:
    transform = AFFINE_TRANSFORMS[variant]
    result = (vertices - transform["translation"]) / transform["scale"]
    result[:, 1] -= 0.835
    result[:, 2] -= 0.02
    return result


def make_interpolators(
    source_controls: np.ndarray,
    target_controls: np.ndarray,
) -> tuple[RBFInterpolator, RBFInterpolator, RBFInterpolator, RBFInterpolator]:
    source_cages = source_controls.reshape((-1, 9, 3))
    target_cages = target_controls.reshape((-1, 9, 3))

    source_planar = source_cages[:, [0, 1, 2], :2].reshape((-1, 2))
    target_planar = target_cages[:, [0, 1, 2], :2].reshape((-1, 2))
    rounded = np.round(source_planar, 6)
    unique, inverse = np.unique(rounded, axis=0, return_inverse=True)
    destinations = np.zeros_like(unique)
    counts = np.zeros(len(unique), dtype=np.float64)
    for index, group in enumerate(inverse):
        destinations[group] += target_planar[index]
        counts[group] += 1
    destinations /= counts[:, None]
    planar = RBFInterpolator(
        unique,
        destinations - unique,
        kernel="thin_plate_spline",
        smoothing=1.0e-5,
        degree=1,
        neighbors=min(32, len(unique)),
    )

    cage_xy = source_cages[:, 0, :2]
    source_center_z = source_cages[:, 0, 2]
    target_center_z = target_cages[:, 0, 2]
    source_half_depth = (source_cages[:, 4, 2] - source_cages[:, 3, 2]) * 0.5
    target_half_depth = (target_cages[:, 4, 2] - target_cages[:, 3, 2]) * 0.5
    depth_scale = np.clip(target_half_depth / source_half_depth, 0.72, 1.65)
    neighbors = min(24, len(cage_xy))
    interpolation_options = {
        "kernel": "thin_plate_spline",
        "smoothing": 2.0e-5,
        "degree": 1,
        "neighbors": neighbors,
    }
    return (
        planar,
        RBFInterpolator(cage_xy, source_center_z, **interpolation_options),
        RBFInterpolator(cage_xy, target_center_z, **interpolation_options),
        RBFInterpolator(cage_xy, np.log(depth_scale), **interpolation_options),
    )


def warp_vertices(
    vertices: np.ndarray,
    interpolators: tuple[
        RBFInterpolator,
        RBFInterpolator,
        RBFInterpolator,
        RBFInterpolator,
    ],
) -> np.ndarray:
    planar, source_center, target_center, depth_scale = interpolators
    result = np.empty_like(vertices)
    for start in range(0, len(vertices), 25_000):
        stop = min(start + 25_000, len(vertices))
        source = vertices[start:stop]
        source_xy = source[:, :2]
        result[start:stop, :2] = source_xy + planar(source_xy)
        source_cz = source_center(source_xy)
        target_cz = target_center(source_xy)
        scale_z = np.exp(depth_scale(source_xy)) * 0.84
        result[start:stop, 2] = target_cz + (source[:, 2] - source_cz) * scale_z
    return result


def signed_surface_distance(
    skin: trimesh.Trimesh,
    vertices: np.ndarray,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    distances = np.empty(len(vertices), dtype=np.float64)
    closest = np.empty_like(vertices)
    triangle_ids = np.empty(len(vertices), dtype=np.int64)
    for start in range(0, len(vertices), 20_000):
        stop = min(start + 20_000, len(vertices))
        nearest, _, triangles = skin.nearest.on_surface(vertices[start:stop])
        normals = skin.face_normals[triangles]
        distances[start:stop] = np.einsum(
            "ij,ij->i",
            nearest - vertices[start:stop],
            normals,
        )
        closest[start:stop] = nearest
        triangle_ids[start:stop] = triangles
    return distances, closest, triangle_ids


def fit_inside_surface(
    skin: trimesh.Trimesh,
    vertices: np.ndarray,
    margin: float,
    faces: np.ndarray | None = None,
    preserve_components: bool = False,
    outside_only: bool = False,
) -> tuple[np.ndarray, dict[str, float | int]]:
    result = vertices.copy()
    before, _, _ = signed_surface_distance(skin, result)
    maximum_correction = 0.0

    if preserve_components:
        if faces is None:
            raise ValueError("Connected-component fitting requires triangle faces")
        result, component_report = fit_connected_components(
            skin,
            result,
            faces,
            margin,
        )
        maximum_correction = component_report["maximum_component_translation"]

    # Projection is repeated because the closest triangle can change around
    # fingers, the axilla, the groin, and between adjacent vascular branches.
    projection_threshold = 0.0 if preserve_components or outside_only else margin
    for _ in range(10):
        distances, closest, triangle_ids = signed_surface_distance(skin, result)
        outside = distances < projection_threshold
        if not np.any(outside):
            break
        destination = (
            closest[outside]
            - skin.face_normals[triangle_ids[outside]] * margin
        )
        correction = destination - result[outside]
        maximum_correction = max(
            maximum_correction,
            float(np.linalg.norm(correction, axis=1).max()),
        )
        result[outside] = destination

    after, _, _ = signed_surface_distance(skin, result)
    return result, {
        "outside_before": int(np.count_nonzero(before < 0.0)),
        "outside_before_percent": float(np.mean(before < 0.0) * 100),
        "minimum_before": float(before.min()),
        "outside_after": int(np.count_nonzero(after < 0.0)),
        "minimum_after": float(after.min()),
        "maximum_correction": maximum_correction,
    }


def fit_connected_components(
    skin: trimesh.Trimesh,
    vertices: np.ndarray,
    faces: np.ndarray,
    margin: float,
) -> tuple[np.ndarray, dict[str, float | int]]:
    edges = np.concatenate(
        [faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]],
        axis=0,
    )
    graph = coo_matrix(
        (np.ones(len(edges), dtype=np.uint8), (edges[:, 0], edges[:, 1])),
        shape=(len(vertices), len(vertices)),
    )
    component_count, labels = connected_components(graph, directed=False)
    members = [np.flatnonzero(labels == label) for label in range(component_count)]
    result = vertices.copy()
    maximum_translation = 0.0
    scaled_components: set[int] = set()

    # Whole bones, ligaments, and capsules move together. This keeps the shape
    # of phalanges, carpals, ribs, and joint surfaces intact instead of
    # flattening individual vertices onto the skin.
    for iteration in range(18):
        distances, closest, triangle_ids = signed_surface_distance(skin, result)
        outside_count = int(np.count_nonzero(distances < 0.0))
        if outside_count == 0:
            break
        changed = False
        for label, indices in enumerate(members):
            violating = indices[distances[indices] < 0.0]
            if len(violating) == 0:
                continue
            normals = skin.face_normals[triangle_ids[violating]]
            corrections = (
                closest[violating]
                - normals * margin
                - result[violating]
            )
            weights = np.square(np.maximum(margin - distances[violating], 0.0001))
            translation = np.average(corrections, axis=0, weights=weights)
            length = float(np.linalg.norm(translation))
            if length > 0.018:
                translation *= 0.018 / length
                length = 0.018
            if length > 0.00002:
                result[indices] += translation
                maximum_translation = max(maximum_translation, length)
                changed = True

            # If translation alone cannot fit a component after several
            # passes, reduce it uniformly by tiny increments. Uniform scaling
            # preserves its anatomy and is reserved for genuine atlas/body
            # size mismatches.
            if iteration >= 7:
                center = result[indices].mean(axis=0)
                result[indices] = center + (result[indices] - center) * 0.992
                scaled_components.add(label)
                changed = True
        if not changed:
            break

    return result, {
        "components": component_count,
        "scaled_components": len(scaled_components),
        "maximum_component_translation": maximum_translation,
    }


def write_usda(mesh: trimesh.Trimesh, destination: Path, name: str) -> None:
    vertices = np.asarray(mesh.vertices)
    faces = np.asarray(mesh.faces)
    normals = smooth_vertex_normals(vertices, faces)

    def vectors(values: np.ndarray) -> str:
        return ", ".join(
            f"({value[0]:.8g}, {value[1]:.8g}, {value[2]:.8g})"
            for value in values
        )

    minimum = vertices.min(axis=0)
    maximum = vertices.max(axis=0)
    counts = ", ".join("3" for _ in faces)
    indices = ", ".join(str(int(value)) for value in faces.reshape(-1))
    destination.write_text(
        "#usda 1.0\n"
        "(\n"
        f"    defaultPrim = \"{name}\"\n"
        "    metersPerUnit = 1\n"
        "    upAxis = \"Y\"\n"
        ")\n\n"
        f"def Xform \"{name}\"\n"
        "{\n"
        "    def Mesh \"Anatomy\"\n"
        "    {\n"
        f"        float3[] extent = [{vectors(np.array([minimum, maximum]))}]\n"
        f"        int[] faceVertexCounts = [{counts}]\n"
        f"        int[] faceVertexIndices = [{indices}]\n"
        f"        normal3f[] normals = [{vectors(normals)}] (\n"
        "            interpolation = \"vertex\"\n"
        "        )\n"
        f"        point3f[] points = [{vectors(vertices)}]\n"
        "        uniform token subdivisionScheme = \"none\"\n"
        "    }\n"
        "}\n"
    )


def smooth_vertex_normals(vertices: np.ndarray, faces: np.ndarray) -> np.ndarray:
    normals = np.zeros_like(vertices)
    first = vertices[faces[:, 1]] - vertices[faces[:, 0]]
    second = vertices[faces[:, 2]] - vertices[faces[:, 0]]
    face_normals = np.cross(first, second)
    for corner in range(3):
        np.add.at(normals, faces[:, corner], face_normals)
    lengths = np.linalg.norm(normals, axis=1)
    lengths[lengths == 0] = 1
    return normals / lengths[:, None]


def main() -> None:
    arguments = parse_arguments()
    with tempfile.TemporaryDirectory(prefix="littlewindows-volume-registration-") as value:
        temporary_directory = Path(value)
        source = usd_to_mesh(arguments.input, temporary_directory)
        skin = usd_to_mesh(arguments.skin, temporary_directory)
        if arguments.already_registered:
            warped = np.asarray(source.vertices).copy()
        else:
            controls = np.load(arguments.controls)
            interpolators = make_interpolators(controls["source"], controls["target"])
            source_atlas = restore_source_atlas(
                np.asarray(source.vertices),
                arguments.variant,
            )
            warped = warp_vertices(source_atlas, interpolators)
        if arguments.warp_only:
            fitted = warped
            report = {
                "outside_before": 0,
                "outside_before_percent": 0.0,
                "minimum_before": 0.0,
                "outside_after": 0,
                "minimum_after": 0.0,
                "maximum_correction": 0.0,
            }
        else:
            fitted, report = fit_inside_surface(
                skin,
                warped,
                SURFACE_MARGINS[arguments.layer],
                np.asarray(source.faces),
                arguments.preserve_components,
                arguments.outside_only,
            )
        source.vertices = fitted
        usda = temporary_directory / "registered.usda"
        prim_name = re.sub(r"[^A-Za-z0-9_]", "_", arguments.output.stem)
        write_usda(source, usda, prim_name)
        subprocess.run(
            ["/usr/bin/usdcat", str(usda), "-o", str(arguments.output.resolve())],
            check=True,
        )
        print(
            {
                "variant": arguments.variant,
                "layer": arguments.layer,
                "vertices": len(source.vertices),
                "triangles": len(source.faces),
                **report,
            }
        )


if __name__ == "__main__":
    main()
