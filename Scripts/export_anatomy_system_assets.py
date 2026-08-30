"""Export mobile anatomy system sources while preserving hand detail.

Run this script with Blender 3.6 after opening the official Z-Anatomy
``Startup.blend`` file.  Objects that touch either hand, plus structures whose
names identify hand anatomy, keep their evaluated source topology.  The rest of
each system receives the same broad reduction used by the upstream web viewer.

Example:

    blender -b Startup.blend --factory-startup -noaudio \
        -P Scripts/export_anatomy_system_assets.py -- \
        --output /tmp/anatomy-systems muscle nerves skeleton joints
"""

from __future__ import annotations

import argparse
import json
import os
import re
import time

import bpy
from mathutils import Vector


SYSTEMS = {
    "surface": ("9: Regions of human body", "surface.glb", 180_000),
    "skeleton": ("1: Skeletal system", "iskelet.glb", 320_000),
    "joints": ("3: Joints", "eklem.glb", 150_000),
    "muscle": ("4: Muscular system", "kas.glb", 420_000),
    "nerves": ("7: Nervous system & Sense organs", "sinir.glb", 400_000),
}

GEOMETRY_TYPES = {"MESH", "CURVE", "SURFACE"}
TEMP_COLLECTION = "LITTLEWINDOWS_HAND_DETAIL_EXPORT"
HAND_NAME = re.compile(
    r"hand|finger|thumb|digital|palmar|dorsal branch|pollic|thenar|hypothenar",
    re.IGNORECASE,
)
LOWER_EXTREMITY_NAME = re.compile(
    r"foot|toe|plantar|fibular|metatars|tarsal|calcane|halluc",
    re.IGNORECASE,
)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--hands-only", action="store_true")
    parser.add_argument(
        "systems",
        nargs="*",
        choices=tuple(SYSTEMS),
        default=tuple(SYSTEMS),
    )
    argv = []
    if "--" in __import__("sys").argv:
        argv = __import__("sys").argv[__import__("sys").argv.index("--") + 1 :]
    return parser.parse_args(argv)


def evaluated_triangle_count(obj: bpy.types.Object, depsgraph) -> int:
    try:
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
    except RuntimeError:
        return 0
    if mesh is None:
        return 0
    count = sum(max(0, len(face.vertices) - 2) for face in mesh.polygons)
    evaluated.to_mesh_clear()
    return count


def world_bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    minimum = Vector((min(v.x for v in corners), min(v.y for v in corners), min(v.z for v in corners)))
    maximum = Vector((max(v.x for v in corners), max(v.y for v in corners), max(v.z for v in corners)))
    return minimum, maximum


def touches_hand(obj: bpy.types.Object) -> bool:
    if HAND_NAME.search(obj.name) and not LOWER_EXTREMITY_NAME.search(obj.name):
        return True
    minimum, maximum = world_bounds(obj)
    # Startup.blend is Z-up. The glTF exporter converts this to the Y-up
    # coordinates consumed by the downstream USD generator.
    overlaps_height = maximum.z >= 0.72 and minimum.z <= 1.08
    overlaps_depth = maximum.y >= -0.20 and minimum.y <= 0.20
    reaches_left = maximum.x >= 0.245
    reaches_right = minimum.x <= -0.245
    return overlaps_height and overlaps_depth and (reaches_left or reaches_right)


def clear_temp_collection() -> None:
    collection = bpy.data.collections.get(TEMP_COLLECTION)
    if collection is None:
        return
    for obj in list(collection.objects):
        collection.objects.unlink(obj)
    bpy.context.scene.collection.children.unlink(collection)
    bpy.data.collections.remove(collection)


def export_system(
    system: str,
    output_directory: str,
    depsgraph,
    hands_only: bool,
) -> dict:
    collection_name, file_name, triangle_target = SYSTEMS[system]
    source_collection = bpy.data.collections.get(collection_name)
    if source_collection is None:
        raise RuntimeError(f"Missing Z-Anatomy collection: {collection_name}")

    items = []
    seen = set()
    for obj in source_collection.all_objects:
        if (
            obj.type not in GEOMETRY_TYPES
            or obj.name in seen
            or obj.name.endswith(".g")
        ):
            continue
        seen.add(obj.name)
        triangles = evaluated_triangle_count(obj, depsgraph)
        if triangles:
            items.append((obj, triangles, touches_hand(obj)))

    if hands_only:
        items = [item for item in items if item[2]]

    source_triangles = sum(item[1] for item in items)
    hand_triangles = sum(item[1] for item in items if item[2])
    non_hand_triangles = source_triangles - hand_triangles
    non_hand_target = max(1, triangle_target - min(hand_triangles, triangle_target // 2))
    non_hand_ratio = 1.0 if hands_only else min(
        1.0,
        non_hand_target / max(1, non_hand_triangles),
    )

    clear_temp_collection()
    temporary_collection = bpy.data.collections.new(TEMP_COLLECTION)
    bpy.context.scene.collection.children.link(temporary_collection)
    temporary_objects = []
    linked_objects = []

    for source, triangles, preserve in items:
        target = source
        if source.type != "MESH":
            evaluated = source.evaluated_get(depsgraph)
            mesh = bpy.data.meshes.new_from_object(evaluated)
            original_name = source.name
            source.name = original_name + "~source"
            target = bpy.data.objects.new(original_name, mesh)
            target.matrix_world = source.matrix_world
            temporary_objects.append((target, source, original_name))

        for modifier in [m for m in target.modifiers if m.name == "LittleWindowsDecimate"]:
            target.modifiers.remove(modifier)
        if not preserve and non_hand_ratio < 0.999 and triangles >= 600:
            modifier = target.modifiers.new(name="LittleWindowsDecimate", type="DECIMATE")
            modifier.decimate_type = "COLLAPSE"
            modifier.ratio = non_hand_ratio

        try:
            temporary_collection.objects.link(target)
            linked_objects.append(target)
        except RuntimeError:
            pass

    layer_collection = bpy.context.view_layer.layer_collection.children.get(TEMP_COLLECTION)
    if layer_collection is None:
        raise RuntimeError("Temporary export collection was not linked into the view layer")
    bpy.context.view_layer.active_layer_collection = layer_collection

    output_name = file_name.replace(".glb", "-hands.glb") if hands_only else file_name
    output_path = os.path.join(output_directory, output_name)
    bpy.ops.export_scene.gltf(
        filepath=output_path,
        export_format="GLB",
        use_active_collection=True,
        use_active_collection_with_nested=False,
        use_selection=False,
        use_visible=False,
        export_apply=True,
        export_yup=True,
        export_materials="NONE",
        export_normals=True,
        export_texcoords=False,
        export_tangents=False,
        export_cameras=False,
        export_lights=False,
        export_animations=False,
        export_skins=False,
        export_morph=False,
    )

    for obj in linked_objects:
        for modifier in [m for m in obj.modifiers if m.name == "LittleWindowsDecimate"]:
            obj.modifiers.remove(modifier)
    clear_temp_collection()
    for temporary, source, original_name in temporary_objects:
        mesh = temporary.data
        bpy.data.objects.remove(temporary, do_unlink=True)
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)
        source.name = original_name

    return {
        "system": system,
        "file": output_name,
        "hands_only": hands_only,
        "objects": len(items),
        "source_triangles": source_triangles,
        "hand_objects": sum(1 for item in items if item[2]),
        "hand_source_triangles": hand_triangles,
        "non_hand_ratio": round(non_hand_ratio, 6),
        "size_mb": round(os.path.getsize(output_path) / 1_000_000, 2),
        "preserved_hand_names": [item[0].name for item in items if item[2]],
    }


def main() -> None:
    arguments = parse_arguments()
    os.makedirs(arguments.output, exist_ok=True)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    report = []
    for system in arguments.systems:
        started = time.time()
        result = export_system(
            system,
            arguments.output,
            depsgraph,
            arguments.hands_only,
        )
        result["elapsed_seconds"] = round(time.time() - started, 2)
        report.append(result)
        print(json.dumps(result, ensure_ascii=False, indent=2))
    with open(os.path.join(arguments.output, "export-report.json"), "w") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)


main()
