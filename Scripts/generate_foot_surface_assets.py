#!/usr/bin/env python3
"""Generate registered side-profile and high-detail plantar foot shells."""

from __future__ import annotations

import argparse
import re
import subprocess
import tempfile
import urllib.request
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import trimesh


MAKEHUMAN_BASE_URL = (
    "https://raw.githubusercontent.com/makehumancommunity/makehuman/"
    "master/makehuman/data/3dobjs/base.obj"
)

# The full focused-foot shell includes enough lower leg for the side view. In a
# plantar view that same ankle geometry projects beside the heel and reads as a
# large deformity. Keep the complete side asset, but crop the plantar-only
# presentation immediately above the tarsal bones.
INTERNAL_SOLE_UPPER_Y = {
    "Female": -0.705,
    "Male": -0.814,
}


@dataclass(frozen=True)
class TargetFrame:
    center_x: float
    width: float
    sole_y: float
    top_y: float
    toe_z: float
    heel_z: float


@dataclass(frozen=True)
class PlantarWarp:
    matrix: np.ndarray
    target_center: np.ndarray

    def transform_points(
        self,
        points: np.ndarray,
        inset: float = 0.0,
    ) -> np.ndarray:
        result = trimesh.transformations.transform_points(
            np.asarray(points, dtype=np.float64),
            self.matrix,
        )
        if inset > 0:
            result = self.target_center + (
                result - self.target_center
            ) * (1.0 - inset * 2.0)
        return result


def load_obj_text(source: str) -> str:
    path = Path(source)
    if path.exists():
        return path.read_text(encoding="utf-8")
    if source.startswith(("https://", "http://")):
        with urllib.request.urlopen(source) as response:
            return response.read().decode("utf-8")
    raise FileNotFoundError(source)


def load_makehuman_body(source: str) -> tuple[np.ndarray, np.ndarray]:
    lines = load_obj_text(source).splitlines()
    vertices = np.asarray(
        [
            [float(value) for value in line.split()[1:4]]
            for line in lines
            if line.startswith("v ")
        ],
        dtype=np.float64,
    )
    body_start = lines.index("g body") + 1
    body_end = lines.index("g helper-tights")
    triangles: list[tuple[int, int, int]] = []
    for line in lines[body_start:body_end]:
        if not line.startswith("f "):
            continue
        face = [int(value.split("/")[0]) - 1 for value in line.split()[1:]]
        triangles.extend((face[0], face[index], face[index + 1]) for index in range(1, len(face) - 1))
    return vertices, np.asarray(triangles, dtype=np.int64)


def usd_array(text: str, declaration: str, value_type: type = float) -> list:
    match = re.search(re.escape(declaration) + r"\s*=\s*\[([\s\S]*?)\]", text)
    if match is None:
        raise ValueError(f"Missing {declaration}")
    values = re.findall(
        r"-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?",
        match.group(1),
    )
    return [value_type(value) for value in values]


def load_usd_mesh(source: Path) -> tuple[np.ndarray, np.ndarray]:
    text = subprocess.run(
        ("/usr/bin/usdcat", str(source)),
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    vertices = np.asarray(
        usd_array(text, "point3f[] points"),
        dtype=np.float64,
    ).reshape((-1, 3))
    counts = usd_array(text, "int[] faceVertexCounts", int)
    indices = usd_array(text, "int[] faceVertexIndices", int)
    triangles: list[tuple[int, int, int]] = []
    offset = 0
    for count in counts:
        polygon = indices[offset : offset + count]
        triangles.extend(
            (polygon[0], polygon[index], polygon[index + 1])
            for index in range(1, count - 1)
        )
        offset += count
    return vertices, np.asarray(triangles, dtype=np.int64)


def clip_polygon_below(vertices: np.ndarray, upper_y: float) -> list[np.ndarray]:
    result: list[np.ndarray] = []
    previous = vertices[-1]
    previous_inside = previous[1] <= upper_y
    for current in vertices:
        current_inside = current[1] <= upper_y
        if current_inside != previous_inside:
            fraction = (upper_y - previous[1]) / (current[1] - previous[1])
            result.append(previous + fraction * (current - previous))
        if current_inside:
            result.append(current)
        previous = current
        previous_inside = current_inside
    return result


def crop_foot(
    vertices: np.ndarray,
    faces: np.ndarray,
    side_sign: float,
    upper_y: float = -2.80,
    side_minimum: float = 0.35,
) -> trimesh.Trimesh:
    triangles: list[np.ndarray] = []
    for face in faces:
        source_triangle = vertices[face]
        if np.max(source_triangle[:, 0] * side_sign) <= side_minimum:
            continue
        if np.min(source_triangle[:, 1]) > upper_y:
            continue
        polygon = clip_polygon_below(source_triangle, upper_y)
        if len(polygon) < 3:
            continue
        for index in range(1, len(polygon) - 1):
            triangles.append(np.asarray((polygon[0], polygon[index], polygon[index + 1])))

    triangle_array = np.asarray(triangles, dtype=np.float64)
    mesh = trimesh.Trimesh(
        vertices=triangle_array.reshape((-1, 3)),
        faces=np.arange(triangle_array.size // 3).reshape((-1, 3)),
        process=True,
    )
    mesh.merge_vertices(digits_vertex=6)
    mesh.remove_unreferenced_vertices()

    return mesh


def clip_mesh_below(mesh: trimesh.Trimesh, upper_y: float) -> trimesh.Trimesh:
    """Clip an already registered mesh at a horizontal plantar-view boundary."""
    triangles: list[np.ndarray] = []
    vertices = np.asarray(mesh.vertices)
    for face in np.asarray(mesh.faces):
        polygon = clip_polygon_below(vertices[face], upper_y)
        if len(polygon) < 3:
            continue
        for index in range(1, len(polygon) - 1):
            triangles.append(
                np.asarray((polygon[0], polygon[index], polygon[index + 1]))
            )

    triangle_array = np.asarray(triangles, dtype=np.float64)
    clipped = trimesh.Trimesh(
        vertices=triangle_array.reshape((-1, 3)),
        faces=np.arange(triangle_array.size // 3).reshape((-1, 3)),
        process=True,
    )
    clipped.merge_vertices(digits_vertex=6)
    clipped.remove_unreferenced_vertices()
    clipped.fix_normals()
    return clipped


@dataclass(frozen=True)
class PlantarAnatomyFrame:
    """Sample a medial/lateral point safely inside the exact plantar shell."""

    mesh: trimesh.Trimesh
    side: str

    @property
    def minimum_z(self) -> float:
        return float(self.mesh.bounds[0, 2])

    @property
    def length(self) -> float:
        return float(self.mesh.extents[2])

    def section(self, longitudinal: float) -> tuple[float, float, float, float]:
        z = self.minimum_z + np.clip(longitudinal, 0.0, 1.0) * self.length
        vertices = np.asarray(self.mesh.vertices)
        distances = np.abs(vertices[:, 2] - z)
        count = min(96, len(vertices))
        sample = vertices[np.argpartition(distances, count - 1)[:count]]
        return (
            float(np.quantile(sample[:, 0], 0.08)),
            float(np.quantile(sample[:, 0], 0.92)),
            float(np.quantile(sample[:, 1], 0.10)),
            float(np.quantile(sample[:, 1], 0.90)),
        )

    def point(
        self,
        medial: float,
        longitudinal: float,
        depth: float,
    ) -> np.ndarray:
        minimum_x, maximum_x, minimum_y, maximum_y = self.section(longitudinal)
        margin = (maximum_x - minimum_x) * 0.15
        lateral_x = maximum_x - margin if self.side == "Left" else minimum_x + margin
        medial_x = minimum_x + margin if self.side == "Left" else maximum_x - margin
        return np.asarray(
            (
                lateral_x + (medial_x - lateral_x) * medial,
                minimum_y + (maximum_y - minimum_y) * depth,
                self.minimum_z + longitudinal * self.length,
            ),
            dtype=np.float64,
        )

    def width(self, longitudinal: float) -> float:
        minimum_x, maximum_x, _, _ = self.section(longitudinal)
        return (maximum_x - minimum_x) * 0.70

    def depth(self, longitudinal: float) -> float:
        _, _, minimum_y, maximum_y = self.section(longitudinal)
        return maximum_y - minimum_y


def chaikin(points: np.ndarray, iterations: int = 2) -> np.ndarray:
    result = np.asarray(points, dtype=np.float64)
    for _ in range(iterations):
        smoothed = [result[0]]
        for first, second in zip(result[:-1], result[1:]):
            smoothed.extend((first * 0.75 + second * 0.25, first * 0.25 + second * 0.75))
        smoothed.append(result[-1])
        result = np.asarray(smoothed)
    return result


def sweep_path(
    points: np.ndarray,
    widths: np.ndarray,
    depths: np.ndarray,
    radial_segments: int = 14,
    ridge_count: int = 0,
    ridge_strength: float = 0.0,
) -> trimesh.Trimesh:
    """Build a smooth elliptical bundle around a curved centerline.

    Muscle bellies use very shallow longitudinal ridges so they read as soft
    fascicles rather than glossy capsules. Tubular anatomy leaves the ridge
    controls at zero for a round epineurial or tendon profile.
    """
    points = np.asarray(points, dtype=np.float64)
    vertices: list[np.ndarray] = []
    for index, point in enumerate(points):
        previous = points[max(0, index - 1)]
        following = points[min(len(points) - 1, index + 1)]
        tangent = following - previous
        planar_normal = np.asarray((-tangent[2], 0.0, tangent[0]))
        planar_length = float(np.linalg.norm(planar_normal))
        if planar_length < 1e-8:
            planar_normal = np.asarray((1.0, 0.0, 0.0))
        else:
            planar_normal /= planar_length
        for segment in range(radial_segments):
            angle = 2.0 * np.pi * segment / radial_segments
            progression = index / max(len(points) - 1, 1)
            ridge_scale = 1.0
            if ridge_count > 0:
                ridge_scale += (
                    ridge_strength
                    * np.cos(ridge_count * angle + progression * 0.7)
                    * np.sin(np.pi * progression) ** 0.45
                )
            vertices.append(
                point
                + planar_normal * np.cos(angle) * widths[index] * ridge_scale
                + np.asarray((0.0, 1.0, 0.0))
                * np.sin(angle)
                * depths[index]
                * ridge_scale
            )

    faces: list[tuple[int, int, int]] = []
    for ring in range(len(points) - 1):
        first = ring * radial_segments
        second = (ring + 1) * radial_segments
        for segment in range(radial_segments):
            following = (segment + 1) % radial_segments
            faces.extend(
                (
                    (first + segment, second + segment, second + following),
                    (first + segment, second + following, first + following),
                )
            )

    start_center = len(vertices)
    end_center = start_center + 1
    vertices.extend((points[0], points[-1]))
    for segment in range(radial_segments):
        following = (segment + 1) % radial_segments
        faces.extend(
            (
                (start_center, following, segment),
                (
                    end_center,
                    (len(points) - 1) * radial_segments + segment,
                    (len(points) - 1) * radial_segments + following,
                ),
            )
        )

    mesh = trimesh.Trimesh(
        vertices=np.asarray(vertices),
        faces=np.asarray(faces, dtype=np.int64),
        process=False,
    )
    return mesh


def anatomical_path(
    frame: PlantarAnatomyFrame,
    controls: tuple[tuple[float, float], ...],
    depth: float,
) -> tuple[np.ndarray, np.ndarray]:
    normalized = chaikin(np.asarray(controls, dtype=np.float64), iterations=2)
    points = np.asarray(
        [frame.point(medial, longitudinal, depth) for medial, longitudinal in normalized]
    )
    longitudinal = normalized[:, 1]
    return points, longitudinal


def muscle_bundle(
    frame: PlantarAnatomyFrame,
    controls: tuple[tuple[float, float], ...],
    width_fraction: float,
    depth_fraction: float,
    presentation_depth: float = 0.34,
    end_scales: tuple[float, float] = (0.08, 0.08),
) -> trimesh.Trimesh:
    points, longitudinal = anatomical_path(frame, controls, depth=presentation_depth)
    progression = np.linspace(0.0, 1.0, len(points))
    belly = np.sin(np.pi * progression) ** 0.68
    endpoint_floor = end_scales[0] + (end_scales[1] - end_scales[0]) * progression
    taper = endpoint_floor + belly * (1.0 - endpoint_floor)
    # A small asymmetry avoids the inflated-capsule silhouette while keeping
    # the system light enough for a continuously interactive mobile scene.
    taper *= 1.0 + 0.045 * np.sin(2.4 * np.pi * progression + controls[0][0])
    widths = np.asarray(
        [frame.width(value) * width_fraction for value in longitudinal]
    ) * taper
    depths = np.asarray(
        [frame.depth(value) * depth_fraction for value in longitudinal]
    ) * taper
    return sweep_path(
        points,
        widths,
        depths,
        radial_segments=18,
        ridge_count=5,
        ridge_strength=0.045,
    )


def tubular_bundle(
    frame: PlantarAnatomyFrame,
    controls: tuple[tuple[float, float], ...],
    radius_fraction: float,
    depth: float,
    start_scale: float = 1.0,
    end_scale: float = 1.0,
) -> trimesh.Trimesh:
    points, longitudinal = anatomical_path(frame, controls, depth=depth)
    progression = np.linspace(0.0, 1.0, len(points))
    radii = np.asarray(
        [frame.width(value) * radius_fraction for value in longitudinal]
    ) * (start_scale + (end_scale - start_scale) * progression)
    return sweep_path(points, radii, radii * 0.86, radial_segments=14)


def plantar_anatomy_systems(
    shell: trimesh.Trimesh,
    side: str,
) -> dict[str, trimesh.Trimesh]:
    """Build a clean superficial plantar anatomy plate in the registered shell."""
    frame = PlantarAnatomyFrame(shell, side)

    muscle_definitions = (
        # First layer: abductor hallucis, flexor digitorum brevis, and
        # abductor digiti minimi. Their unequal taper and shallow flattened
        # profiles match the broad superficial plantar layer.
        (((0.87, 0.09), (0.91, 0.28), (0.90, 0.51), (0.86, 0.76)), 0.105, 0.078, 0.31, (0.15, 0.06)),
        (((0.50, 0.08), (0.49, 0.24), (0.50, 0.43), (0.51, 0.61)), 0.175, 0.09, 0.32, (0.13, 0.09)),
        (((0.14, 0.09), (0.09, 0.28), (0.10, 0.50), (0.15, 0.75)), 0.098, 0.072, 0.31, (0.14, 0.06)),
        # Second layer: quadratus plantae, the two heads of flexor hallucis
        # brevis, and the oblique/transverse heads of adductor hallucis.
        (((0.40, 0.14), (0.33, 0.26), (0.39, 0.40), (0.49, 0.49)), 0.115, 0.07, 0.39, (0.10, 0.08)),
        (((0.72, 0.52), (0.77, 0.66), (0.82, 0.81)), 0.064, 0.06, 0.37, (0.08, 0.05)),
        (((0.88, 0.51), (0.89, 0.65), (0.89, 0.81)), 0.052, 0.055, 0.37, (0.08, 0.05)),
        (((0.38, 0.50), (0.54, 0.61), (0.72, 0.73), (0.84, 0.80)), 0.052, 0.052, 0.41, (0.05, 0.04)),
        (((0.24, 0.73), (0.45, 0.755), (0.66, 0.77), (0.83, 0.79)), 0.030, 0.045, 0.40, (0.04, 0.04)),
        # Four lumbricals follow the long flexor tendons into toes two through
        # five; four compact interosseous bellies occupy the metatarsal spaces.
        (((0.40, 0.53), (0.34, 0.64), (0.29, 0.76)), 0.032, 0.042, 0.36, (0.05, 0.04)),
        (((0.47, 0.53), (0.45, 0.65), (0.43, 0.78)), 0.031, 0.042, 0.36, (0.05, 0.04)),
        (((0.54, 0.53), (0.56, 0.66), (0.57, 0.79)), 0.030, 0.041, 0.36, (0.05, 0.04)),
        (((0.61, 0.52), (0.67, 0.65), (0.71, 0.79)), 0.029, 0.040, 0.36, (0.05, 0.04)),
        (((0.25, 0.64), (0.29, 0.75), (0.31, 0.85)), 0.036, 0.052, 0.43, (0.05, 0.04)),
        (((0.38, 0.63), (0.41, 0.75), (0.42, 0.86)), 0.036, 0.052, 0.43, (0.05, 0.04)),
        (((0.51, 0.63), (0.54, 0.75), (0.55, 0.87)), 0.036, 0.052, 0.43, (0.05, 0.04)),
        (((0.64, 0.62), (0.68, 0.74), (0.70, 0.86)), 0.035, 0.05, 0.43, (0.05, 0.04)),
    )
    muscles = trimesh.util.concatenate(
        [muscle_bundle(frame, *definition) for definition in muscle_definitions]
    )

    tendon_definitions = (
        # Four flexor digitorum brevis tendons, each dividing into two slips
        # around its digit rather than terminating as a single straight wire.
        ((0.49, 0.54), (0.40, 0.65), (0.27, 0.78)),
        ((0.50, 0.55), (0.47, 0.67), (0.43, 0.79)),
        ((0.51, 0.55), (0.55, 0.67), (0.57, 0.80)),
        ((0.52, 0.54), (0.63, 0.66), (0.70, 0.79)),
        ((0.27, 0.77), (0.22, 0.84), (0.20, 0.90)),
        ((0.27, 0.77), (0.29, 0.84), (0.31, 0.90)),
        ((0.43, 0.78), (0.39, 0.85), (0.38, 0.91)),
        ((0.43, 0.78), (0.46, 0.85), (0.47, 0.91)),
        ((0.57, 0.79), (0.53, 0.85), (0.52, 0.91)),
        ((0.57, 0.79), (0.60, 0.85), (0.61, 0.91)),
        ((0.70, 0.78), (0.67, 0.84), (0.66, 0.90)),
        ((0.70, 0.78), (0.73, 0.84), (0.75, 0.90)),
        # Flexor hallucis longus remains a single strong tendon to the hallux.
        ((0.81, 0.48), (0.86, 0.67), (0.89, 0.91)),
    )
    tendons = trimesh.util.concatenate(
        [
            tubular_bundle(
                frame,
                controls,
                0.0095,
                0.245,
                end_scale=0.72,
            )
            for controls in tendon_definitions
        ]
    )

    nerve_definitions = (
        # Tibial nerve through the tarsal tunnel and the medial/lateral plantar
        # trunks. Radius falls with each branch order, making the hierarchy
        # legible at phone scale without exaggerating distal nerves.
        (((0.84, 0.015), (0.83, 0.08), (0.79, 0.16), (0.70, 0.23)), 0.026, 1.0, 0.88),
        (((0.70, 0.23), (0.71, 0.34), (0.68, 0.46), (0.64, 0.57)), 0.022, 1.0, 0.80),
        (((0.70, 0.23), (0.57, 0.31), (0.41, 0.40), (0.28, 0.52), (0.20, 0.66)), 0.021, 1.0, 0.78),
        # The deep lateral plantar branch arcs medially across the metatarsal
        # bases instead of crossing the digital branches as a straight chord.
        (((0.30, 0.49), (0.38, 0.54), (0.50, 0.58), (0.64, 0.59), (0.77, 0.62)), 0.014, 1.0, 0.58),
        # Medial plantar proper branch to the hallux and three common digital
        # nerves before they bifurcate to adjacent toe sides.
        (((0.64, 0.54), (0.74, 0.67), (0.84, 0.79), (0.89, 0.91)), 0.015, 1.0, 0.62),
        (((0.63, 0.54), (0.66, 0.66), (0.69, 0.77)), 0.016, 1.0, 0.76),
        (((0.58, 0.52), (0.55, 0.65), (0.53, 0.77)), 0.0155, 1.0, 0.76),
        (((0.49, 0.49), (0.43, 0.63), (0.39, 0.76)), 0.015, 1.0, 0.74),
        # Proper digital branches to the facing sides of toes one through four.
        (((0.69, 0.76), (0.73, 0.84), (0.76, 0.91)), 0.0105, 1.0, 0.48),
        (((0.69, 0.76), (0.65, 0.84), (0.62, 0.91)), 0.0105, 1.0, 0.48),
        (((0.53, 0.76), (0.57, 0.84), (0.58, 0.91)), 0.0105, 1.0, 0.48),
        (((0.53, 0.76), (0.49, 0.84), (0.47, 0.91)), 0.0105, 1.0, 0.48),
        (((0.39, 0.75), (0.43, 0.83), (0.43, 0.90)), 0.0102, 1.0, 0.46),
        (((0.39, 0.75), (0.35, 0.83), (0.33, 0.90)), 0.0102, 1.0, 0.46),
        # Superficial lateral plantar branches to the fourth/fifth interdigital
        # space and the lateral border of the little toe.
        (((0.21, 0.62), (0.26, 0.72), (0.27, 0.79)), 0.014, 1.0, 0.72),
        (((0.27, 0.78), (0.31, 0.85), (0.31, 0.90)), 0.0098, 1.0, 0.46),
        (((0.27, 0.78), (0.23, 0.85), (0.21, 0.90)), 0.0098, 1.0, 0.46),
        (((0.20, 0.65), (0.16, 0.76), (0.14, 0.88)), 0.0105, 1.0, 0.46),
        # Medial calcaneal branches spread locally across the heel pad.
        (((0.82, 0.10), (0.88, 0.07), (0.91, 0.035)), 0.010, 1.0, 0.42),
        (((0.80, 0.11), (0.73, 0.07), (0.66, 0.035)), 0.0095, 1.0, 0.42),
        (((0.81, 0.09), (0.84, 0.055), (0.82, 0.025)), 0.009, 1.0, 0.40),
    )
    nerve_core = trimesh.util.concatenate(
        [
            tubular_bundle(
                frame,
                controls,
                radius,
                0.28,
                start_scale=start_scale,
                end_scale=end_scale,
            )
            for controls, radius, start_scale, end_scale in nerve_definitions
        ]
    )
    nerve_sheath = trimesh.util.concatenate(
        [
            tubular_bundle(
                frame,
                controls,
                radius * 1.32,
                0.28,
                start_scale=start_scale,
                end_scale=end_scale,
            )
            for controls, radius, start_scale, end_scale in nerve_definitions
        ]
    )
    for mesh in (muscles, tendons, nerve_core, nerve_sheath):
        mesh.remove_unreferenced_vertices()
    return {
        "MuscularSystem": muscles,
        "TendonSystem": tendons,
        "NervousSystem": nerve_core,
        "NerveSheathSystem": nerve_sheath,
    }


def expanded_sheath(
    mesh: trimesh.Trimesh,
    thickness: float,
) -> trimesh.Trimesh:
    """Create a softly translucent epineurial sleeve around the nerve core."""
    result = mesh.copy()
    result.vertices = np.asarray(result.vertices) + (
        np.asarray(result.vertex_normals) * thickness
    )
    result.fix_normals()
    return result


def internal_sole_presentation(
    side_mesh: trimesh.Trimesh,
    target_sole_mesh: trimesh.Trimesh,
    variant: str,
) -> tuple[trimesh.Trimesh, PlantarWarp]:
    """Return a true plantar shell and one shared affine for every internal layer."""
    source_mesh = clip_mesh_below(side_mesh, INTERNAL_SOLE_UPPER_Y[variant])
    vertices = np.asarray(source_mesh.vertices)
    z_edges = np.linspace(vertices[:, 2].min(), vertices[:, 2].max(), 13)
    centers: list[tuple[float, float]] = []
    for lower_z, upper_z in zip(z_edges[:-1], z_edges[1:]):
        sample = vertices[
            (vertices[:, 2] >= lower_z) & (vertices[:, 2] < upper_z)
        ]
        if len(sample) < 10:
            continue
        center_x = (
            np.quantile(sample[:, 0], 0.03)
            + np.quantile(sample[:, 0], 0.97)
        ) * 0.5
        centers.append(((lower_z + upper_z) * 0.5, center_x))

    slope, _ = np.polyfit(
        [center[0] for center in centers],
        [center[1] for center in centers],
        1,
    )
    pivot = np.asarray(
        (
            np.mean([center[1] for center in centers]),
            0.0,
            (vertices[:, 2].min() + vertices[:, 2].max()) * 0.5,
        )
    )
    rotation = trimesh.transformations.rotation_matrix(
        -float(np.arctan(slope)),
        (0.0, 1.0, 0.0),
        point=pivot,
    )
    rotated = source_mesh.copy()
    rotated.apply_transform(rotation)

    source_min, source_max = rotated.bounds
    target_min, target_max = target_sole_mesh.bounds
    scale = (target_max - target_min) / (source_max - source_min)
    registration = np.eye(4)
    registration[:3, :3] = np.diag(scale)
    registration[:3, 3] = target_min - source_min * scale
    matrix = registration @ rotation
    warp = PlantarWarp(
        matrix=matrix,
        target_center=target_sole_mesh.bounds.mean(axis=0),
    )
    source_mesh.vertices = warp.transform_points(np.asarray(source_mesh.vertices))
    source_mesh.fix_normals()
    return source_mesh, warp


def target_frame(variant: str, side: str) -> TargetFrame:
    if variant == "Female":
        return TargetFrame(
            center_x=0.141 if side == "Left" else -0.160,
            width=0.102,
            sole_y=-0.794,
            top_y=-0.720,
            toe_z=0.159,
            heel_z=-0.108,
        )
    return TargetFrame(
        center_x=0.214 if side == "Left" else -0.214,
        width=0.132,
        sole_y=-0.915,
        top_y=-0.826,
        toe_z=0.162,
        heel_z=-0.112,
    )


def fit_to_frame(
    mesh: trimesh.Trimesh,
    frame: TargetFrame,
    source_foot_top_y: float = -6.92,
) -> trimesh.Trimesh:
    source_min, source_max = mesh.bounds
    source_center_x = (source_min[0] + source_max[0]) * 0.5
    vertices = mesh.vertices.copy()
    vertices[:, 0] = frame.center_x + (
        (vertices[:, 0] - source_center_x)
        * frame.width
        / (source_max[0] - source_min[0])
    )
    vertices[:, 1] = frame.sole_y + (
        (vertices[:, 1] - source_min[1])
        * (frame.top_y - frame.sole_y)
        / (source_foot_top_y - source_min[1])
    )
    vertices[:, 2] = frame.heel_z + (
        (vertices[:, 2] - source_min[2])
        * (frame.toe_z - frame.heel_z)
        / (source_max[2] - source_min[2])
    )
    fitted = trimesh.Trimesh(
        vertices=vertices,
        faces=mesh.faces,
        process=False,
    )
    fitted.fix_normals()
    return fitted


def vectors(values: np.ndarray) -> str:
    return ", ".join(
        f"({value[0]:.8g}, {value[1]:.8g}, {value[2]:.8g})" for value in values
    )


def write_usdc(mesh: trimesh.Trimesh, destination: Path, name: str) -> None:
    with tempfile.TemporaryDirectory(prefix="littlewindows-foot-surface-") as directory:
        source = Path(directory) / f"{name}.usda"
        compiled = Path(directory) / f"{name}.usdc"
        source.write_text(
            "#usda 1.0\n"
            "(\n"
            f'    defaultPrim = "{name}"\n'
            "    metersPerUnit = 1\n"
            '    upAxis = "Y"\n'
            ")\n\n"
            f'def Xform "{name}"\n'
            "{\n"
            '    def Mesh "Anatomy"\n'
            "    {\n"
            f"        float3[] extent = [{vectors(mesh.bounds)}]\n"
            f"        int[] faceVertexCounts = [{', '.join(['3'] * len(mesh.faces))}]\n"
            f"        int[] faceVertexIndices = [{', '.join(map(str, mesh.faces.reshape(-1)))}]\n"
            f"        normal3f[] normals = [{vectors(mesh.vertex_normals)}] (\n"
            '            interpolation = "vertex"\n'
            "        )\n"
            f"        point3f[] points = [{vectors(mesh.vertices)}]\n"
            "        uniform bool doubleSided = false\n"
            '        uniform token subdivisionScheme = "none"\n'
            "    }\n"
            "}\n",
            encoding="utf-8",
        )
        subprocess.run(
            ("/usr/bin/usdcat", str(source), "-o", str(compiled)),
            check=True,
            capture_output=True,
            text=True,
        )
        compiled.replace(destination)
        destination.chmod(0o644)


def generate(source: str, destination_directory: Path) -> None:
    makehuman_vertices, makehuman_faces = load_makehuman_body(source)
    for variant in ("Female", "Male"):
        registered_vertices, registered_faces = load_usd_mesh(
            destination_directory / f"BodySkin{variant}Medium.usdc"
        )
        for side in ("Left", "Right"):
            side_sign = 1.0 if side == "Left" else -1.0
            frame = target_frame(variant, side)
            side_upper_y = -0.475 if variant == "Female" else -0.532
            side_mesh = crop_foot(
                registered_vertices,
                registered_faces,
                side_sign,
                upper_y=side_upper_y,
                side_minimum=0.0,
            )
            sole_source = crop_foot(
                makehuman_vertices,
                makehuman_faces,
                side_sign,
                upper_y=-6.92,
            )
            sole_mesh = fit_to_frame(sole_source, frame)

            internal_sole_mesh, _ = internal_sole_presentation(
                side_mesh,
                sole_mesh,
                variant,
            )

            for prefix, mesh in (
                ("FootSurface", side_mesh),
                ("FootSoleSurface", sole_mesh),
                ("FootInternalSoleSurface", internal_sole_mesh),
            ):
                name = f"{prefix}{variant}{side}"
                destination = destination_directory / f"{name}.usdc"
                write_usdc(mesh, destination, name)
                print(
                    f"{destination}: {len(mesh.vertices)} vertices, "
                    f"{len(mesh.faces)} faces"
                )

            side_nerve_path = destination_directory / (
                f"FootNervousSystem{variant}{side}.usdc"
            )
            if side_nerve_path.exists():
                side_nerve_vertices, side_nerve_faces = load_usd_mesh(side_nerve_path)
                side_nerve_mesh = trimesh.Trimesh(
                    vertices=side_nerve_vertices,
                    faces=side_nerve_faces,
                    process=False,
                )
                side_sheath = expanded_sheath(
                    side_nerve_mesh,
                    thickness=0.00085 if variant == "Female" else 0.00105,
                )
                side_sheath_name = f"FootNerveSheathSystem{variant}{side}"
                write_usdc(
                    side_sheath,
                    destination_directory / f"{side_sheath_name}.usdc",
                    side_sheath_name,
                )

            for system, system_mesh in plantar_anatomy_systems(
                internal_sole_mesh,
                side,
            ).items():
                name = f"FootSole{system}{variant}{side}"
                destination = destination_directory / f"{name}.usdc"
                write_usdc(system_mesh, destination, name)
                print(
                    f"{destination}: {len(system_mesh.vertices)} vertices, "
                    f"{len(system_mesh.faces)} faces"
                )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default=MAKEHUMAN_BASE_URL)
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
