#!/usr/bin/env python3
"""Generate aligned hand skin, muscle, bone, joint, and nerve assets.

The source model is the MIT-licensed NIMBLE anatomical hand atlas:
https://github.com/reyuwei/NIMBLE_model

The large NIMBLE parameter pickle is intentionally not committed. Pass its
path explicitly when regenerating the compact runtime USD assets.
"""

from __future__ import annotations

import argparse
import collections
import io
import json
import math
import pickle
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import torch


def _load_torch_storage(data: bytes):
    return torch.load(io.BytesIO(data), map_location="cpu", weights_only=True)


class _RestrictedUnpickler(pickle.Unpickler):
    """Load the published tensor dictionary without allowing arbitrary code."""

    _ALLOWED = {
        ("torch._utils", "_rebuild_tensor_v2"): torch._utils._rebuild_tensor_v2,
        ("torch.storage", "_load_from_bytes"): _load_torch_storage,
        ("collections", "OrderedDict"): collections.OrderedDict,
        ("numpy.core.multiarray", "_reconstruct"): np._core.multiarray._reconstruct,
        ("numpy._core.multiarray", "_reconstruct"): np._core.multiarray._reconstruct,
        ("numpy", "ndarray"): np.ndarray,
        ("numpy", "dtype"): np.dtype,
    }

    def find_class(self, module: str, name: str):
        try:
            return self._ALLOWED[(module, name)]
        except KeyError as error:
            raise pickle.UnpicklingError(
                f"Refusing unsupported pickle global {module}.{name}"
            ) from error


def load_parameter_dictionary(path: Path) -> dict:
    with path.open("rb") as handle:
        return _RestrictedUnpickler(handle).load()


def as_numpy(value) -> np.ndarray:
    if isinstance(value, torch.Tensor):
        return value.detach().cpu().numpy()
    return np.asarray(value)


def shaped_vertices(parameters: dict, normalized_shape: np.ndarray) -> np.ndarray:
    vertices = as_numpy(parameters["vert"]).squeeze().astype(np.float64)
    basis = as_numpy(parameters["shape_basis"]).squeeze().astype(np.float64)
    mean = as_numpy(parameters["shape_pm_mean"]).squeeze().astype(np.float64)
    standard_deviation = (
        as_numpy(parameters["shape_pm_std"]).squeeze().astype(np.float64)
    )
    component_count = min(len(normalized_shape), basis.shape[0])
    real_shape = (
        normalized_shape[:component_count] * standard_deviation[:component_count]
        + mean[:component_count]
    )
    displacement = np.sum(
        basis[:component_count] * real_shape[:component_count, None],
        axis=0,
        dtype=np.float64,
    )
    return vertices + displacement.reshape(vertices.shape)


def joint_positions(parameters: dict, vertices: np.ndarray) -> np.ndarray:
    bone_end = int(parameters["bone_v_sep"])
    regressor = as_numpy(parameters["jreg_bone"]).squeeze().astype(np.float64)
    return np.sum(
        regressor[:, :, None] * vertices[None, :bone_end, :],
        axis=1,
        dtype=np.float64,
    )


def inspection_report(parameters: dict) -> dict:
    vertices = shaped_vertices(parameters, np.zeros(20, dtype=np.float64))
    bone_end = int(parameters["bone_v_sep"])
    skin_start = vertices.shape[0] + int(parameters["skin_v_sep"])
    sections = {
        "bone": vertices[:bone_end],
        "muscle": vertices[bone_end:skin_start],
        "skin": vertices[skin_start:],
    }
    report = {
        "vertices": int(vertices.shape[0]),
        "bone_vertex_end": bone_end,
        "skin_vertex_start": skin_start,
        "sections": {},
    }
    for name, section in sections.items():
        faces = as_numpy(parameters[f"{name}_f"]).squeeze()
        report["sections"][name] = {
            "vertices": int(section.shape[0]),
            "faces": int(faces.shape[0]),
            "face_index_minimum": int(faces.min()),
            "face_index_maximum": int(faces.max()),
            "minimum": section.min(axis=0).round(5).tolist(),
            "maximum": section.max(axis=0).round(5).tolist(),
            "span": np.ptp(section, axis=0).round(5).tolist(),
        }
    bone_vertices = sections["bone"]
    joints = joint_positions(parameters, vertices)
    report["joints"] = joints.round(5).tolist()
    return report


@dataclass(frozen=True)
class Mesh:
    positions: np.ndarray
    faces: np.ndarray


@dataclass(frozen=True)
class HandTransform:
    center: np.ndarray
    rotation: np.ndarray
    scale: float
    variant_scale: np.ndarray

    def apply(self, values: np.ndarray) -> np.ndarray:
        centered = values - self.center
        rotated = np.sum(
            centered[:, None, :] * self.rotation[None, :, :],
            axis=2,
        )
        # NIMBLE is X/right, Y/depth, Z/finger length. RealityKit is
        # X/right, Y/up, Z/toward the camera.
        result = np.column_stack((rotated[:, 0], rotated[:, 2], -rotated[:, 1]))
        return result * self.scale * self.variant_scale


def make_hand_transform(
    skin_vertices: np.ndarray,
    joints: np.ndarray,
    variant: str,
) -> HandTransform:
    # Remove the atlas's global wrist-to-fingertip tilt while retaining the
    # natural local flexion at each interphalangeal joint.
    slope, _ = np.polyfit(joints[:, 2], joints[:, 1], 1)
    angle = math.atan(float(slope))
    cosine = math.cos(angle)
    sine = math.sin(angle)
    rotation = np.array(
        [
            [1.0, 0.0, 0.0],
            [0.0, cosine, -sine],
            [0.0, sine, cosine],
        ],
        dtype=np.float64,
    )
    rotated_skin = np.sum(
        skin_vertices[:, None, :] * rotation[None, :, :],
        axis=2,
    )
    rotated_center = np.array(
        [
            (rotated_skin[:, 0].min() + rotated_skin[:, 0].max()) * 0.5,
            (rotated_skin[:, 1].min() + rotated_skin[:, 1].max()) * 0.5,
            (rotated_skin[:, 2].min() + rotated_skin[:, 2].max()) * 0.5,
        ]
    )
    center = np.sum(rotation * rotated_center[:, None], axis=0)
    length = float(np.ptp(rotated_skin[:, 2]))
    variant_scale = {
        "female": np.array([0.965, 0.99, 0.96], dtype=np.float64),
        "male": np.array([1.055, 1.015, 1.04], dtype=np.float64),
    }[variant]
    return HandTransform(
        center=center,
        rotation=rotation,
        scale=0.62 / length,
        variant_scale=variant_scale,
    )


def compact_mesh(positions: np.ndarray, faces: np.ndarray) -> Mesh:
    used = np.unique(faces.reshape(-1))
    remap = np.full(positions.shape[0], -1, dtype=np.int64)
    remap[used] = np.arange(len(used), dtype=np.int64)
    return Mesh(positions=positions[used], faces=remap[faces])


def transformed_mesh(
    positions: np.ndarray,
    faces: np.ndarray,
    transform: HandTransform,
) -> Mesh:
    result = compact_mesh(transform.apply(positions), faces.astype(np.int64))
    # The source-to-RealityKit axis conversion includes a reflection.
    return Mesh(result.positions, result.faces[:, [0, 2, 1]])


def normalized(values: np.ndarray) -> np.ndarray:
    lengths = np.linalg.norm(values, axis=-1, keepdims=True)
    return values / np.maximum(lengths, 1e-12)


def smooth_normals(mesh: Mesh) -> np.ndarray:
    positions = mesh.positions
    faces = mesh.faces
    ab = positions[faces[:, 1]] - positions[faces[:, 0]]
    ac = positions[faces[:, 2]] - positions[faces[:, 0]]
    face_normals = np.cross(ab, ac)
    normals = np.zeros_like(positions)
    for corner in range(3):
        np.add.at(normals, faces[:, corner], face_normals)
    return normalized(normals)


def catmull_rom(control: np.ndarray, samples_per_segment: int = 5) -> np.ndarray:
    if len(control) < 2:
        return control.copy()
    padded = np.vstack((control[0], control, control[-1]))
    values = []
    for index in range(1, len(padded) - 2):
        p0, p1, p2, p3 = padded[index - 1 : index + 3]
        for sample in range(samples_per_segment):
            t = sample / samples_per_segment
            t2 = t * t
            t3 = t2 * t
            values.append(
                0.5
                * (
                    2 * p1
                    + (-p0 + p2) * t
                    + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                    + (-p0 + 3 * p1 - 3 * p2 + p3) * t3
                )
            )
    values.append(control[-1])
    return np.asarray(values, dtype=np.float64)


def surface_depth(
    path: np.ndarray,
    skin_positions: np.ndarray,
    side: str,
    inset: float,
) -> np.ndarray:
    result = path.copy()
    skin_plane = skin_positions[:, :2]
    for index, point in enumerate(result):
        squared_distance = np.sum((skin_plane - point[:2]) ** 2, axis=1)
        nearest = np.argpartition(squared_distance, 23)[:24]
        depths = skin_positions[nearest, 2]
        if side == "front":
            result[index, 2] = np.percentile(depths, 88) - inset
        else:
            result[index, 2] = np.percentile(depths, 12) + inset
    # Suppress nearest-neighbor chatter without pulling terminal branches out
    # of the hand envelope.
    for _ in range(2):
        if len(result) > 2:
            result[1:-1, 2] = (
                result[:-2, 2] + 2 * result[1:-1, 2] + result[2:, 2]
            ) * 0.25
    return result


def offset_control_path(control: np.ndarray, offset: float) -> np.ndarray:
    result = control.copy()
    tangents = np.gradient(result[:, :2], axis=0)
    tangents = normalized(tangents)
    perpendicular = np.column_stack((-tangents[:, 1], tangents[:, 0]))
    result[:, :2] += perpendicular * offset
    return result


def tube_mesh(
    path: np.ndarray,
    start_radius: float,
    end_radius: float,
    radial_segments: int = 10,
    flatten: float = 1.0,
) -> Mesh:
    if len(path) < 2:
        return Mesh(np.empty((0, 3)), np.empty((0, 3), dtype=np.int64))
    tangents = normalized(np.gradient(path, axis=0))
    positions = []
    for index, (point, tangent) in enumerate(zip(path, tangents)):
        reference = np.array([0.0, 0.0, 1.0])
        if abs(float(np.dot(reference, tangent))) > 0.86:
            reference = np.array([1.0, 0.0, 0.0])
        first = normalized(np.cross(tangent, reference)[None, :])[0]
        second = normalized(np.cross(tangent, first)[None, :])[0]
        progress = index / max(1, len(path) - 1)
        radius = start_radius + (end_radius - start_radius) * progress
        for ring_index in range(radial_segments):
            angle = math.tau * ring_index / radial_segments
            positions.append(
                point
                + first * math.cos(angle) * radius
                + second * math.sin(angle) * radius * flatten
            )
    faces = []
    for row in range(len(path) - 1):
        for column in range(radial_segments):
            following = (column + 1) % radial_segments
            a = row * radial_segments + column
            b = row * radial_segments + following
            c = (row + 1) * radial_segments + following
            d = (row + 1) * radial_segments + column
            faces.extend(((a, b, c), (a, c, d)))
    start_center = len(positions)
    end_center = start_center + 1
    positions.extend((path[0], path[-1]))
    for column in range(radial_segments):
        following = (column + 1) % radial_segments
        faces.append((start_center, following, column))
        last = (len(path) - 1) * radial_segments
        faces.append((end_center, last + column, last + following))
    return Mesh(np.asarray(positions), np.asarray(faces, dtype=np.int64))


def merge_meshes(meshes: list[Mesh]) -> Mesh:
    positions = []
    faces = []
    offset = 0
    for mesh in meshes:
        if len(mesh.positions) == 0:
            continue
        positions.append(mesh.positions)
        faces.append(mesh.faces + offset)
        offset += len(mesh.positions)
    return Mesh(np.vstack(positions), np.vstack(faces))


def sphere_mesh(center: np.ndarray, radius: np.ndarray) -> Mesh:
    latitude_count = 8
    longitude_count = 12
    positions = []
    for latitude in range(latitude_count + 1):
        polar = math.pi * latitude / latitude_count
        for longitude in range(longitude_count):
            azimuth = math.tau * longitude / longitude_count
            unit = np.array(
                [
                    math.sin(polar) * math.cos(azimuth),
                    math.cos(polar),
                    math.sin(polar) * math.sin(azimuth),
                ]
            )
            positions.append(center + unit * radius)
    faces = []
    for latitude in range(latitude_count):
        for longitude in range(longitude_count):
            following = (longitude + 1) % longitude_count
            a = latitude * longitude_count + longitude
            b = latitude * longitude_count + following
            c = (latitude + 1) * longitude_count + following
            d = (latitude + 1) * longitude_count + longitude
            if latitude > 0:
                faces.append((a, b, c))
            if latitude < latitude_count - 1:
                faces.append((a, c, d))
    return Mesh(np.asarray(positions), np.asarray(faces, dtype=np.int64))


def make_joint_mesh(joints: np.ndarray) -> Mesh:
    meshes = []
    for index, joint in enumerate(joints):
        if index == 0:
            radius = np.array([0.022, 0.016, 0.015])
        elif index in {1, 5, 10, 15, 20}:
            radius = np.array([0.014, 0.012, 0.011])
        elif index in {4, 9, 14, 19, 24}:
            radius = np.array([0.008, 0.008, 0.007])
        else:
            radius = np.array([0.0105, 0.009, 0.008])
        meshes.append(sphere_mesh(joint, radius))
    return merge_meshes(meshes)


FINGER_CHAINS = (
    (1, 2, 3, 4),
    (5, 6, 7, 8, 9),
    (10, 11, 12, 13, 14),
    (15, 16, 17, 18, 19),
    (20, 21, 22, 23, 24),
)


def make_tendon_mesh(joints: np.ndarray, skin: np.ndarray) -> Mesh:
    meshes = []
    wrist = joints[0]
    for finger_index, chain in enumerate(FINGER_CHAINS):
        digit = joints[np.asarray(chain)]
        origin = wrist.copy()
        origin[0] += (digit[0, 0] - wrist[0]) * 0.28
        front_control = np.vstack((origin, digit))
        back_control = front_control.copy()
        front = surface_depth(catmull_rom(front_control, 6), skin, "front", 0.012)
        back = surface_depth(catmull_rom(back_control, 6), skin, "back", 0.010)
        width = 0.0048 if finger_index == 0 else 0.0042
        meshes.append(tube_mesh(front, width, width * 0.52, 10, flatten=0.38))
        meshes.append(tube_mesh(back, width * 0.92, width * 0.42, 10, flatten=0.30))
    return merge_meshes(meshes)


@dataclass(frozen=True)
class NerveRoute:
    path: np.ndarray
    start_radius: float
    end_radius: float
    radial_segments: int = 10


def organic_path(path: np.ndarray, phase: float, amplitude: float) -> np.ndarray:
    result = path.copy()
    progress = np.linspace(0.0, 1.0, len(result))
    tangent = normalized(np.gradient(result[:, :2], axis=0))
    perpendicular = np.column_stack((-tangent[:, 1], tangent[:, 0]))
    envelope = np.sin(progress * math.pi)
    variation = np.sin(progress * math.tau * 1.35 + phase) * envelope * amplitude
    result[:, :2] += perpendicular * variation[:, None]
    return result


def make_nerve_routes(joints: np.ndarray, skin: np.ndarray) -> list[NerveRoute]:
    routes: list[NerveRoute] = []
    wrist = joints[0]
    median_knuckles = np.mean(joints[[6, 11, 16]], axis=0)
    ulnar_knuckles = np.mean(joints[[16, 21]], axis=0)
    median_hub = wrist * 0.46 + median_knuckles * 0.54
    ulnar_hub = wrist * 0.52 + ulnar_knuckles * 0.48

    def routed(
        control: np.ndarray,
        side: str,
        start_radius: float,
        end_radius: float,
        phase: float,
        amplitude: float,
        inset: float,
        samples: int = 6,
        radial_segments: int = 12,
    ) -> None:
        path = organic_path(
            catmull_rom(control, samples),
            phase=phase,
            amplitude=amplitude,
        )
        path = surface_depth(path, skin, side, inset)
        routes.append(
            NerveRoute(path, start_radius, end_radius, radial_segments)
        )

    def digit_side(
        origin: np.ndarray,
        chain: tuple[int, ...],
        side: float,
        phase: float,
        surface: str = "front",
        separation: float = 0.0051,
    ) -> None:
        # Proper digital nerves split near a web space, then hug the side of a
        # digit instead of drawing a straight centerline through the finger.
        digit = joints[np.asarray(chain[1:])]
        shifted = offset_control_path(digit, side * separation)
        routed(
            np.vstack((origin, shifted)),
            surface,
            0.00315,
            0.00155,
            phase,
            0.00125,
            0.011 if surface == "front" else 0.009,
        )

    # One substantial median trunk and one ulnar trunk enter through the
    # carpal tunnel/Guyon's canal. The previous parallel cylinders looked like
    # decorative wires and obscured the actual branch hierarchy.
    median_control = np.vstack(
        (
            wrist + np.array([0.005, -0.010, 0.0]),
            wrist + np.array([0.005, 0.018, 0.0]),
            median_hub,
        )
    )
    routed(median_control, "front", 0.0062, 0.0047, 0.2, 0.0015, 0.016, 7, 14)
    ulnar_control = np.vstack(
        (
            wrist + np.array([-0.032, -0.008, 0.0]),
            wrist + np.array([-0.030, 0.018, 0.0]),
            ulnar_hub,
        )
    )
    routed(ulnar_control, "front", 0.0054, 0.0040, 1.7, 0.0015, 0.016, 7, 14)

    # Median recurrent motor branch into the thenar eminence.
    thenar_end = wrist * 0.24 + joints[2] * 0.76
    routed(
        np.vstack((median_hub, median_hub + np.array([0.026, 0.025, 0.0]), thenar_end)),
        "front",
        0.0030,
        0.0014,
        0.8,
        0.0018,
        0.012,
    )

    # Thumb common branch and its two proper digital divisions.
    thumb_split = joints[1] * 0.56 + joints[2] * 0.44
    routed(
        np.vstack((median_hub, median_hub + np.array([0.028, 0.018, 0.0]), thumb_split)),
        "front",
        0.0042,
        0.0028,
        1.2,
        0.0014,
        0.013,
    )
    digit_side(thumb_split, FINGER_CHAINS[0], -1.0, 0.3, separation=0.0060)
    digit_side(thumb_split, FINGER_CHAINS[0], 1.0, 1.3, separation=0.0060)

    # The radial edge of the index finger receives a direct median branch.
    digit_side(median_hub, FINGER_CHAINS[1], 1.0, 2.0)

    # Common palmar digital nerves divide in the web spaces. Reusing the split
    # point gives the network visible Y junctions instead of a comb of lines.
    web_pairs = (
        (median_hub, FINGER_CHAINS[1], -1.0, FINGER_CHAINS[2], 1.0),
        (median_hub, FINGER_CHAINS[2], -1.0, FINGER_CHAINS[3], 1.0),
        (ulnar_hub, FINGER_CHAINS[3], -1.0, FINGER_CHAINS[4], 1.0),
    )
    for web_index, (hub, first_chain, first_side, second_chain, second_side) in enumerate(web_pairs):
        first_mcp = joints[first_chain[1]]
        second_mcp = joints[second_chain[1]]
        web = (first_mcp + second_mcp) * 0.5
        web[1] -= 0.026
        routed(
            np.vstack((hub, (hub + web) * 0.5 + np.array([0.0, -0.008, 0.0]), web)),
            "front",
            0.0044,
            0.0031,
            2.7 + web_index,
            0.00135,
            0.013,
        )
        digit_side(web, first_chain, first_side, 3.2 + web_index)
        digit_side(web, second_chain, second_side, 4.1 + web_index)

    # The ulnar edge of the little finger receives its own proper branch.
    digit_side(ulnar_hub, FINGER_CHAINS[4], -1.0, 5.4)

    # Dorsal radial and ulnar trunks divide into slimmer dorsal digital
    # branches, which are deliberately sparser than the palmar network.
    dorsal_radial_hub = wrist * 0.46 + np.mean(joints[[2, 6, 11]], axis=0) * 0.54
    radial_control = np.vstack(
        (
            wrist + np.array([0.034, -0.006, 0.0]),
            wrist + np.array([0.038, 0.024, 0.0]),
            dorsal_radial_hub,
        )
    )
    routed(radial_control, "back", 0.0050, 0.0036, 2.1, 0.0015, 0.013, 7, 13)
    for finger_index, chain in enumerate(FINGER_CHAINS[:3]):
        digit_side(
            dorsal_radial_hub,
            chain,
            -0.35 if finger_index == 0 else 0.0,
            6.0 + finger_index,
            surface="back",
            separation=0.0030,
        )

    dorsal_ulnar_hub = wrist * 0.5 + np.mean(joints[[16, 21]], axis=0) * 0.5
    routed(
        np.vstack(
            (
                wrist + np.array([-0.038, -0.005, 0.0]),
                wrist + np.array([-0.042, 0.023, 0.0]),
                dorsal_ulnar_hub,
            )
        ),
        "back",
        0.0045,
        0.0032,
        4.8,
        0.0015,
        0.013,
        7,
        13,
    )
    for finger_index, chain in enumerate(FINGER_CHAINS[3:]):
        digit_side(
            dorsal_ulnar_hub,
            chain,
            0.0,
            8.7 + finger_index,
            surface="back",
            separation=0.0026,
        )
    return routes


def nerve_route_mesh(routes: list[NerveRoute], radius_scale: float) -> Mesh:
    return merge_meshes(
        [
            tube_mesh(
                route.path,
                route.start_radius * radius_scale,
                route.end_radius * radius_scale,
                route.radial_segments,
            )
            for route in routes
        ]
    )


def format_number(value: float) -> str:
    if not math.isfinite(float(value)):
        return "0"
    return f"{float(value):.8g}"


def tuple_values(values: np.ndarray) -> str:
    return ", ".join(
        f"({format_number(value[0])}, {format_number(value[1])}, "
        f"{format_number(value[2])})"
        for value in values
    )


def usd_document(name: str, mesh: Mesh) -> str:
    normals = smooth_normals(mesh)
    minimum = mesh.positions.min(axis=0)
    maximum = mesh.positions.max(axis=0)
    face_count = len(mesh.faces)
    indices = ", ".join(str(int(value)) for value in mesh.faces.reshape(-1))
    return f'''#usda 1.0
(
    defaultPrim = "{name}"
    metersPerUnit = 1
    upAxis = "Y"
)

def Xform "{name}"
{{
    def Mesh "HandMesh"
    {{
        float3[] extent = [{tuple_values(minimum[None, :])}, {tuple_values(maximum[None, :])}]
        int[] faceVertexCounts = [{", ".join(["3"] * face_count)}]
        int[] faceVertexIndices = [{indices}]
        normal3f[] normals = [{tuple_values(normals)}] (
            interpolation = "vertex"
        )
        point3f[] points = [{tuple_values(mesh.positions)}]
        uniform bool doubleSided = 1
        uniform token subdivisionScheme = "none"
    }}
}}
'''


def write_usdc(output: Path, name: str, mesh: Mesh) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="littlewindows-hand-") as directory:
        usda = Path(directory) / f"{name}.usda"
        usda.write_text(usd_document(name, mesh))
        subprocess.run(
            ["/usr/bin/usdcat", str(usda), "-o", str(output)],
            check=True,
        )
    output.chmod(0o644)


def generate_assets(parameters: dict, output: Path) -> dict:
    vertices = shaped_vertices(parameters, np.zeros(20, dtype=np.float64))
    bone_end = int(parameters["bone_v_sep"])
    skin_start = vertices.shape[0] + int(parameters["skin_v_sep"])
    source_joints = joint_positions(parameters, vertices)
    source_sections = {
        "SkeletonSystem": (
            vertices[:bone_end],
            as_numpy(parameters["bone_f"]).squeeze(),
        ),
        "MuscularSystem": (
            vertices[bone_end:skin_start],
            as_numpy(parameters["muscle_f"]).squeeze(),
        ),
        "Surface": (
            vertices[skin_start:],
            as_numpy(parameters["skin_f"]).squeeze(),
        ),
    }
    report = {}
    for variant in ("female", "male"):
        transform = make_hand_transform(
            source_sections["Surface"][0],
            source_joints,
            variant,
        )
        meshes = {
            name: transformed_mesh(section, faces, transform)
            for name, (section, faces) in source_sections.items()
        }
        transformed_joints = transform.apply(source_joints)
        meshes["JointSystem"] = make_joint_mesh(transformed_joints)
        meshes["TendonSystem"] = make_tendon_mesh(
            transformed_joints,
            meshes["Surface"].positions,
        )
        nerve_routes = make_nerve_routes(
            transformed_joints,
            meshes["Surface"].positions,
        )
        meshes["NerveSheathSystem"] = nerve_route_mesh(nerve_routes, 1.0)
        meshes["NervousSystem"] = nerve_route_mesh(nerve_routes, 0.46)
        suffix = variant.capitalize()
        report[variant] = {}
        for system, mesh in meshes.items():
            file_name = f"Hand{system}{suffix}.usdc"
            write_usdc(output / file_name, f"Hand{system}{suffix}", mesh)
            report[variant][system] = {
                "vertices": int(len(mesh.positions)),
                "triangles": int(len(mesh.faces)),
                "minimum": mesh.positions.min(axis=0).round(6).tolist(),
                "maximum": mesh.positions.max(axis=0).round(6).tolist(),
            }
    return report


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("model", type=Path)
    parser.add_argument("--inspect", action="store_true")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("LittleWindows/Resources/BodyAnatomy"),
    )
    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()
    parameters = load_parameter_dictionary(arguments.model)
    if arguments.inspect:
        print(json.dumps(inspection_report(parameters), indent=2))
        return
    print(json.dumps(generate_assets(parameters, arguments.output), indent=2))


if __name__ == "__main__":
    main()
