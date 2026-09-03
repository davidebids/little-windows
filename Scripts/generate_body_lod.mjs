#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [inputArgument, outputArgument, targetTriangleArgument, targetErrorArgument = "0.002"] =
    process.argv.slice(2);
const meshoptimizerRoot = process.env.MESHOPTIMIZER_ROOT;

if (!inputArgument || !outputArgument || !targetTriangleArgument || !meshoptimizerRoot) {
    console.error(
        "Usage: MESHOPTIMIZER_ROOT=/path/to/meshoptimizer " +
        "node Scripts/generate_body_lod.mjs input.usdc output.usdc targetTriangles [targetError]"
    );
    process.exit(2);
}

const input = resolve(inputArgument);
const output = resolve(outputArgument);
if (/MuscularSystem|NervousSystem/i.test(basename(input))) {
    throw new Error(
        "Muscular and nervous system assets must retain their complete source topology; " +
        "the whole-body simplifier removes small anatomical structures."
    );
}
const targetTriangleCount = Number.parseInt(targetTriangleArgument, 10);
const targetError = Number.parseFloat(targetErrorArgument);
const moduleURL = pathToFileURL(join(resolve(meshoptimizerRoot), "meshopt_simplifier.js"));
const { MeshoptSimplifier } = await import(moduleURL.href);
await MeshoptSimplifier.ready;

const workingDirectory = mkdtempSync(join(tmpdir(), "littlewindows-body-lod-"));
const sourceUSDA = join(workingDirectory, "source.usda");
const resultUSDA = join(workingDirectory, "result.usda");

try {
    execFileSync("/usr/bin/usdcat", [input, "-o", sourceUSDA], { stdio: "inherit" });
    const source = readFileSync(sourceUSDA, "utf8");
    const points = parseTupleAttribute(source, "point3f[] points");
    const sourceIndices = parseScalarAttribute(source, "int[] faceVertexIndices", Number);
    const faceVertexCounts = parseScalarAttribute(source, "int[] faceVertexCounts", Number);

    if (points.length % 3 !== 0) {
        throw new Error(`Point buffer has ${points.length} scalar values; expected xyz tuples`);
    }
    if (faceVertexCounts.some((count) => count !== 3)) {
        throw new Error("Only triangulated USD meshes are supported");
    }

    const positionRemap = MeshoptSimplifier.generatePositionRemap(points, 3);
    const weldedPositions = [];
    const weldedLookup = new Map();
    for (let sourceIndex = 0; sourceIndex < positionRemap.length; sourceIndex += 1) {
        const representative = positionRemap[sourceIndex];
        if (!weldedLookup.has(representative)) {
            weldedLookup.set(representative, weldedLookup.size);
            const offset = representative * 3;
            weldedPositions.push(points[offset], points[offset + 1], points[offset + 2]);
        }
    }

    const weldedIndices = [];
    for (let triangle = 0; triangle < sourceIndices.length; triangle += 3) {
        const a = weldedLookup.get(positionRemap[sourceIndices[triangle]]);
        const b = weldedLookup.get(positionRemap[sourceIndices[triangle + 1]]);
        const c = weldedLookup.get(positionRemap[sourceIndices[triangle + 2]]);
        if (a !== b && b !== c && c !== a) weldedIndices.push(a, b, c);
    }

    const requestedIndexCount = Math.min(
        weldedIndices.length,
        Math.max(3, targetTriangleCount * 3)
    );
    const [simplifiedIndices, simplificationError] = MeshoptSimplifier.simplify(
        new Uint32Array(weldedIndices),
        new Float32Array(weldedPositions),
        3,
        requestedIndexCount,
        targetError,
        ["RegularizeLight"]
    );
    const compactedIndices = new Uint32Array(simplifiedIndices);
    const [vertexRemap, compactedVertexCount] = MeshoptSimplifier.compactMesh(compactedIndices);
    const compactedPositions = new Float32Array(compactedVertexCount * 3);
    for (let oldIndex = 0; oldIndex < vertexRemap.length; oldIndex += 1) {
        const newIndex = vertexRemap[oldIndex];
        if (newIndex === 0xffffffff) continue;
        compactedPositions[newIndex * 3] = weldedPositions[oldIndex * 3];
        compactedPositions[newIndex * 3 + 1] = weldedPositions[oldIndex * 3 + 1];
        compactedPositions[newIndex * 3 + 2] = weldedPositions[oldIndex * 3 + 2];
    }

    const normals = smoothNormals(compactedPositions, compactedIndices);
    const extent = meshExtent(compactedPositions);
    const primitiveName = sanitizeIdentifier(basename(output, ".usdc"));
    writeFileSync(
        resultUSDA,
        usdDocument(primitiveName, compactedPositions, normals, compactedIndices, extent)
    );
    execFileSync("/usr/bin/usdcat", [resultUSDA, "-o", output], { stdio: "inherit" });

    console.log(JSON.stringify({
        inputVertices: points.length / 3,
        weldedVertices: weldedPositions.length / 3,
        outputVertices: compactedPositions.length / 3,
        inputTriangles: sourceIndices.length / 3,
        outputTriangles: compactedIndices.length / 3,
        simplificationError
    }, null, 2));
} finally {
    rmSync(workingDirectory, { recursive: true, force: true });
}

function parseTupleAttribute(source, attributeName) {
    const match = source.match(new RegExp(`${escapeRegExp(attributeName)}\\s*=\\s*\\[([\\s\\S]*?)\\]`));
    if (!match) throw new Error(`Missing ${attributeName}`);
    return Float32Array.from(match[1].match(/-?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?/gi)?.map(Number) ?? []);
}

function parseScalarAttribute(source, attributeName, converter) {
    const match = source.match(new RegExp(`${escapeRegExp(attributeName)}\\s*=\\s*\\[([\\s\\S]*?)\\]`));
    if (!match) throw new Error(`Missing ${attributeName}`);
    return match[1].split(",").map((value) => converter(value.trim())).filter(Number.isFinite);
}

function escapeRegExp(value) {
    return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function smoothNormals(positions, indices) {
    const normals = new Float32Array(positions.length);
    for (let offset = 0; offset < indices.length; offset += 3) {
        const ia = indices[offset] * 3;
        const ib = indices[offset + 1] * 3;
        const ic = indices[offset + 2] * 3;
        const abx = positions[ib] - positions[ia];
        const aby = positions[ib + 1] - positions[ia + 1];
        const abz = positions[ib + 2] - positions[ia + 2];
        const acx = positions[ic] - positions[ia];
        const acy = positions[ic + 1] - positions[ia + 1];
        const acz = positions[ic + 2] - positions[ia + 2];
        const nx = aby * acz - abz * acy;
        const ny = abz * acx - abx * acz;
        const nz = abx * acy - aby * acx;
        for (const index of [ia, ib, ic]) {
            normals[index] += nx;
            normals[index + 1] += ny;
            normals[index + 2] += nz;
        }
    }
    for (let offset = 0; offset < normals.length; offset += 3) {
        const length = Math.hypot(normals[offset], normals[offset + 1], normals[offset + 2]) || 1;
        normals[offset] /= length;
        normals[offset + 1] /= length;
        normals[offset + 2] /= length;
    }
    return normals;
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

function usdDocument(name, positions, normals, indices, extent) {
    const tuples = (values) => {
        const result = [];
        for (let offset = 0; offset < values.length; offset += 3) {
            result.push(`(${format(values[offset])}, ${format(values[offset + 1])}, ${format(values[offset + 2])})`);
        }
        return result.join(", ");
    };
    const counts = new Array(indices.length / 3).fill("3").join(", ");
    return `#usda 1.0
(
    defaultPrim = "${name}"
    metersPerUnit = 1
    upAxis = "Y"
)

def Xform "${name}"
{
    def Mesh "BodyMesh"
    {
        float3[] extent = [(${extent.minimum.map(format).join(", ")}), (${extent.maximum.map(format).join(", ")})]
        int[] faceVertexCounts = [${counts}]
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

function format(value) {
    if (!Number.isFinite(value)) return "0";
    const result = Number(value).toPrecision(8);
    return result.includes("e") ? result : result.replace(/\.?0+$/, "");
}
