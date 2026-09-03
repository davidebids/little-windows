#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import {
    chmodSync,
    copyFileSync,
    mkdtempSync,
    readFileSync,
    rmSync,
    writeFileSync
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [inputArgument, outputArgument, variantArgument, profileArgument = "skeleton"] =
    process.argv.slice(2);
const meshoptimizerRoot = process.env.MESHOPTIMIZER_ROOT;
const supportedProfiles = new Set([
    "skeleton",
    "muscles",
    "nerves",
    "nerves-core",
    "hand-nerves",
    "detail"
]);

if (
    !inputArgument ||
    !outputArgument ||
    !variantArgument ||
    !meshoptimizerRoot ||
    !supportedProfiles.has(profileArgument)
) {
    console.error(
        "Usage: MESHOPTIMIZER_ROOT=/path/to/meshoptimizer node " +
        "Scripts/generate_skeleton_assets.mjs input.glb output.usdc " +
        "female|male [skeleton|muscles|nerves|nerves-core|hand-nerves|detail]"
    );
    process.exit(2);
}

const transform = {
    female: {
        scale: [1.4025410479674654, 0.9753050896750797, 1.0994547118840001],
        translation: [-0.004938842076231464, -0.7972659181835451, -0.07208135471513982]
    },
    male: {
        scale: [1.543802131255959, 1.0705058736700754, 1.0416830285459215],
        translation: [-0.0003712963140640735, -0.9165427949470785, -0.009672623622318854]
    }
}[variantArgument];

if (!transform) throw new Error(`Unsupported variant: ${variantArgument}`);

const moduleURL = pathToFileURL(join(resolve(meshoptimizerRoot), "meshopt_simplifier.js"));
const { MeshoptSimplifier } = await import(moduleURL.href);
await MeshoptSimplifier.ready;

const workingDirectory = mkdtempSync(join(tmpdir(), "littlewindows-skeleton-"));

try {
    const sourceOBJ = join(workingDirectory, "skeleton.obj");
    execFileSync("assimp", ["export", resolve(inputArgument), sourceOBJ, "-f", "obj"], {
        stdio: "ignore"
    });
    const parsed = parseOBJ(readFileSync(sourceOBJ, "utf8"));
    const transformed = transformPositions(parsed.positions, transform);
    const resultPositions = [];
    const resultIndices = [];
    let sourceTriangles = 0;
    let preservedExtremityTriangles = 0;

    const includedGroups = parsed.groups.filter((group) => includeGroup(group.name));
    for (const group of includedGroups) {
        sourceTriangles += group.indices.length / 3;
        const simplified = simplifyGroup(
            group,
            transformed,
            MeshoptSimplifier,
            profileArgument
        );
        const vertexOffset = resultPositions.length / 3;
        resultPositions.push(...simplified.positions);
        resultIndices.push(...simplified.indices.map((index) => index + vertexOffset));
        if (preserveAtSourceFidelity(group.name, profileArgument, group.indices.length / 3)) {
            preservedExtremityTriangles += simplified.indices.length / 3;
        }
    }

    const positions = Float32Array.from(resultPositions);
    const indices = Uint32Array.from(resultIndices);
    const normals = smoothNormals(positions, indices);
    const resultUSDA = join(workingDirectory, "skeleton.usda");
    const resultUSDC = join(workingDirectory, "skeleton.usdc");
    writeFileSync(
        resultUSDA,
        usdDocument(
            sanitizeIdentifier(basename(outputArgument, ".usdc")),
            positions,
            normals,
            indices
        )
    );
    execFileSync("/usr/bin/usdcat", [resultUSDA, "-o", resultUSDC], { stdio: "inherit" });
    copyFileSync(resultUSDC, resolve(outputArgument));
    chmodSync(resolve(outputArgument), 0o644);
    console.log(JSON.stringify({
        variant: variantArgument,
        profile: profileArgument,
        sourceGroups: parsed.groups.length,
        includedGroups: includedGroups.length,
        sourceTriangles,
        outputTriangles: indices.length / 3,
        outputVertices: positions.length / 3,
        preservedExtremityTriangles
    }, null, 2));
} finally {
    rmSync(workingDirectory, { recursive: true, force: true });
}

function parseOBJ(source) {
    const positions = [];
    const groups = [];
    let currentGroup = null;
    for (const line of source.split("\n")) {
        if (line.startsWith("v ")) {
            // Assimp may append RGB vertex colors after XYZ. Treating those
            // values as more positions creates phantom (0,0,0)/(1,1,1)
            // vertices and long triangles across small anatomy such as hands.
            positions.push(
                ...line.slice(2).trim().split(/\s+/).slice(0, 3).map(Number)
            );
        } else if (line.startsWith("g ")) {
            currentGroup = { name: line.slice(2).trim(), indices: [] };
            groups.push(currentGroup);
        } else if (line.startsWith("f ") && currentGroup) {
            const face = line.slice(2).trim().split(/\s+/).map((value) => {
                const index = Number.parseInt(value.split("/")[0], 10);
                return index > 0 ? index - 1 : positions.length / 3 + index;
            });
            for (let index = 1; index < face.length - 1; index += 1) {
                currentGroup.indices.push(face[0], face[index], face[index + 1]);
            }
        }
    }
    return {
        positions: Float32Array.from(positions),
        groups: groups.filter((group) => group.indices.length >= 3)
    };
}

function simplifyGroup(group, sourcePositions, simplifier, profile) {
    const vertexIndices = [...new Set(group.indices)];
    const sourceToLocal = new Map(
        vertexIndices.map((sourceIndex, localIndex) => [sourceIndex, localIndex])
    );
    const localPositions = new Float32Array(vertexIndices.length * 3);
    for (const [localIndex, sourceIndex] of vertexIndices.entries()) {
        localPositions[localIndex * 3] = sourcePositions[sourceIndex * 3];
        localPositions[localIndex * 3 + 1] = sourcePositions[sourceIndex * 3 + 1];
        localPositions[localIndex * 3 + 2] = sourcePositions[sourceIndex * 3 + 2];
    }
    const localIndices = Uint32Array.from(
        group.indices.map((sourceIndex) => sourceToLocal.get(sourceIndex))
    );
    const triangleCount = localIndices.length / 3;
    const preserve = preserveAtSourceFidelity(group.name, profile, triangleCount);
    const targetTriangleCount = preserve
        ? triangleCount
        : Math.max(96, Math.floor(triangleCount * 0.36));
    const simplifiedIndices = targetTriangleCount >= triangleCount
        ? localIndices
        : simplifier.simplify(
            localIndices,
            localPositions,
            3,
            targetTriangleCount * 3,
            0.006,
            ["RegularizeLight"]
        )[0];
    return compactMesh(localPositions, new Uint32Array(simplifiedIndices));
}

function preserveAtSourceFidelity(name, profile, triangleCount) {
    if (profile === "detail") return true;
    if (profile === "hand-nerves") return true;
    if (profile === "nerves") {
        return isHandNerveGroup(name) || triangleCount <= 240;
    }
    if (profile === "nerves-core") return triangleCount <= 240;
    if (profile === "muscles") {
        return isHandOrFootMuscleGroup(name) || triangleCount <= 240;
    }
    return isExtremityGroup(name) || triangleCount <= 240;
}

function includeGroup(name) {
    if (profileArgument === "hand-nerves") return isHandNerveGroup(name);
    if (profileArgument === "nerves-core") return !isHandNerveGroup(name);
    if (profileArgument !== "muscles") return true;
    if (/tensor fasciae latae/i.test(name)) return true;
    return !/fascia|aponeurosis|retinaculum|intermuscular septum|fibrous sheath|tendon sheath|synovial sheath|ligament/i.test(name);
}

function isHandNerveGroup(name) {
    return /antebrachial cutaneous nerve|branch of radial nerve|interosseous nerve of forearm|digital branches of (radial|ulnar|median) nerve|branch of ulnar nerve|median nerve|communicating branch of median nerve with ulnar nerve/i.test(name);
}

function compactMesh(positions, indices) {
    const sourceToCompacted = new Map();
    const resultPositions = [];
    const compactedIndices = new Uint32Array(indices.length);
    for (let offset = 0; offset < indices.length; offset += 1) {
        const sourceIndex = indices[offset];
        let compactedIndex = sourceToCompacted.get(sourceIndex);
        if (compactedIndex === undefined) {
            compactedIndex = sourceToCompacted.size;
            sourceToCompacted.set(sourceIndex, compactedIndex);
            resultPositions.push(
                positions[sourceIndex * 3],
                positions[sourceIndex * 3 + 1],
                positions[sourceIndex * 3 + 2]
            );
        }
        compactedIndices[offset] = compactedIndex;
    }
    return {
        positions: Float32Array.from(resultPositions),
        indices: compactedIndices
    };
}

function isExtremityGroup(name) {
    return /phalanx|metacarpal|metatarsal|sesamoid|calcaneus|cuboid|cuneiform|navicular|talus|capitate|hamate|lunate|pisiform|scaphoid|trapezium|trapezoid|triquetrum/i.test(name);
}

function isHandOrFootMuscleGroup(name) {
    return /of hand|of foot|pollicis|hallucis|carpi|digitorum|lumbrical|interossei|palmaris|plantaris|thenar|hypothenar/i.test(name);
}

function transformPositions(positions, value) {
    const result = new Float32Array(positions.length);
    for (let offset = 0; offset < positions.length; offset += 3) {
        for (let axis = 0; axis < 3; axis += 1) {
            result[offset + axis] =
                positions[offset + axis] * value.scale[axis] + value.translation[axis];
        }
    }
    return result;
}

function smoothNormals(positions, indices) {
    const normals = new Float32Array(positions.length);
    for (let offset = 0; offset < indices.length; offset += 3) {
        const ia = indices[offset] * 3;
        const ib = indices[offset + 1] * 3;
        const ic = indices[offset + 2] * 3;
        const ab = [
            positions[ib] - positions[ia],
            positions[ib + 1] - positions[ia + 1],
            positions[ib + 2] - positions[ia + 2]
        ];
        const ac = [
            positions[ic] - positions[ia],
            positions[ic + 1] - positions[ia + 1],
            positions[ic + 2] - positions[ia + 2]
        ];
        const normal = [
            ab[1] * ac[2] - ab[2] * ac[1],
            ab[2] * ac[0] - ab[0] * ac[2],
            ab[0] * ac[1] - ab[1] * ac[0]
        ];
        for (const index of [ia, ib, ic]) {
            normals[index] += normal[0];
            normals[index + 1] += normal[1];
            normals[index + 2] += normal[2];
        }
    }
    for (let offset = 0; offset < normals.length; offset += 3) {
        const length = Math.hypot(
            normals[offset],
            normals[offset + 1],
            normals[offset + 2]
        ) || 1;
        normals[offset] /= length;
        normals[offset + 1] /= length;
        normals[offset + 2] /= length;
    }
    return normals;
}

function usdDocument(name, positions, normals, indices) {
    const extent = meshExtent(positions);
    const tuples = (values) => {
        const result = [];
        for (let offset = 0; offset < values.length; offset += 3) {
            result.push(
                `(${format(values[offset])}, ${format(values[offset + 1])}, ` +
                `${format(values[offset + 2])})`
            );
        }
        return result.join(", ");
    };
    return `#usda 1.0
(
    defaultPrim = "${name}"
    metersPerUnit = 1
    upAxis = "Y"
)

def Xform "${name}"
{
    def Mesh "SkeletonMesh"
    {
        float3[] extent = [(${extent.minimum.map(format).join(", ")}), (${extent.maximum.map(format).join(", ")})]
        int[] faceVertexCounts = [${new Array(indices.length / 3).fill("3").join(", ")}]
        int[] faceVertexIndices = [${Array.from(indices).join(", ")}]
        normal3f[] normals = [${tuples(normals)}] (
            interpolation = "vertex"
        )
        point3f[] points = [${tuples(positions)}]
        uniform token subdivisionScheme = "none"
    }
}
`;
}

function meshExtent(positions) {
    const minimum = [Infinity, Infinity, Infinity];
    const maximum = [-Infinity, -Infinity, -Infinity];
    for (let offset = 0; offset < positions.length; offset += 3) {
        for (let axis = 0; axis < 3; axis += 1) {
            minimum[axis] = Math.min(minimum[axis], positions[offset + axis]);
            maximum[axis] = Math.max(maximum[axis], positions[offset + axis]);
        }
    }
    return { minimum, maximum };
}

function sanitizeIdentifier(value) {
    const sanitized = value.replace(/[^A-Za-z0-9_]/g, "_");
    return /^[A-Za-z_]/.test(sanitized) ? sanitized : `_${sanitized}`;
}

function format(value) {
    if (!Number.isFinite(value)) return "0";
    const result = Number(value).toPrecision(8);
    return result.includes("e") ? result : result.replace(/\.?0+$/, "");
}
