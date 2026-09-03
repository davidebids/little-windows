#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [
    inputArgument,
    arterialOutputArgument,
    venousOutputArgument,
    variantArgument,
    skinArgument
] =
    process.argv.slice(2);
const meshoptimizerRoot = process.env.MESHOPTIMIZER_ROOT;

if (
    !inputArgument ||
    !arterialOutputArgument ||
    !venousOutputArgument ||
    !variantArgument ||
    !skinArgument ||
    !meshoptimizerRoot
) {
    console.error(
        "Usage: MESHOPTIMIZER_ROOT=/path/to/meshoptimizer node " +
        "Scripts/generate_vascular_assets.mjs circulation.glb arterial.usdc venous.usdc " +
        "female|male registered-skin.usdc"
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

const workingDirectory = mkdtempSync(join(tmpdir(), "littlewindows-vascular-"));
const sourceOBJ = join(workingDirectory, "circulation.obj");
const skinUSDA = join(workingDirectory, "registered-skin.usda");

try {
    execFileSync("assimp", ["export", resolve(inputArgument), sourceOBJ, "-f", "obj"], {
        stdio: "ignore"
    });
    const parsed = parseOBJ(readFileSync(sourceOBJ, "utf8"));
    execFileSync("/usr/bin/usdcat", [resolve(skinArgument), "-o", skinUSDA], {
        stdio: "ignore"
    });
    const skinPositions = parseUSDPoints(readFileSync(skinUSDA, "utf8"));
    const skinEnvelope = makeSkinEnvelope(skinPositions);
    const registeredPositions = transformPositions(parsed.positions, transform);
    const venousRegistration = fitVenousGroupsInsideSkin(
        registeredPositions,
        parsed.groupsByKind.venous,
        skinEnvelope
    );
    const positionRemap = MeshoptSimplifier.generatePositionRemap(registeredPositions, 3);
    const weldedPositions = compactWeldedPositions(registeredPositions, positionRemap);

    for (const [kind, outputArgument, simplificationRatio] of [
        ["arterial", arterialOutputArgument, 0.42],
        ["venous", venousOutputArgument, 0.48]
    ]) {
        const simplified = simplifyVascularGroups(
            parsed.groupsByKind[kind],
            positionRemap,
            weldedPositions,
            MeshoptSimplifier,
            simplificationRatio
        );
        const registration = kind === "venous"
            ? venousRegistration
            : { adjustedGroups: 0, adjustedVertices: 0, maximumShift: 0 };
        const normals = smoothNormals(simplified.positions, simplified.indices);
        const usda = join(workingDirectory, `${kind}-${variantArgument}.usda`);
        const name = `${variantArgument}_${kind}_vascular_system`;
        writeFileSync(
            usda,
            usdDocument(name, simplified.positions, normals, simplified.indices)
        );
        execFileSync("/usr/bin/usdcat", [usda, "-o", resolve(outputArgument)], { stdio: "inherit" });
        console.log(JSON.stringify({
            variant: variantArgument,
            kind,
            groups: simplified.groups,
            components: simplified.components,
            sourceTriangles: simplified.sourceTriangles,
            outputTriangles: simplified.indices.length / 3,
            outputVertices: simplified.positions.length / 3,
            preservedSmallBranchTriangles: simplified.preservedSmallBranchTriangles,
            maximumSimplificationError: simplified.maximumError,
            registration
        }));
    }
} finally {
    rmSync(workingDirectory, { recursive: true, force: true });
}

function parseOBJ(source) {
    const positions = [];
    const groupsByKind = { arterial: [], venous: [] };
    let currentKind = null;
    let currentGroup = null;
    for (const line of source.split("\n")) {
        if (line.startsWith("v ")) {
            // Assimp can write XYZRGB vertex records. Only XYZ are geometry;
            // ingesting the color triplet produces false vessel vertices.
            positions.push(
                ...line.slice(2).trim().split(/\s+/).slice(0, 3).map(Number)
            );
        } else if (line.startsWith("g ")) {
            currentKind = groupKind(line.slice(2).trim());
            currentGroup = currentKind ? { indices: [] } : null;
            if (currentGroup) groupsByKind[currentKind].push(currentGroup);
        } else if (line.startsWith("f ") && currentKind) {
            const face = line.slice(2).trim().split(/\s+/).map((value) => {
                const index = Number.parseInt(value.split("/")[0], 10);
                return index > 0 ? index - 1 : positions.length / 3 + index;
            });
            for (let index = 1; index < face.length - 1; index += 1) {
                currentGroup.indices.push(face[0], face[index], face[index + 1]);
            }
        }
    }
    return { positions: new Float32Array(positions), groupsByKind };
}

function parseUSDPoints(source) {
    const match = source.match(/point3f\[\] points\s*=\s*\[([\s\S]*?)\]/);
    if (!match) throw new Error("Registered skin USD has no point array");
    return Float32Array.from(
        match[1].match(/-?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?/gi)?.map(Number) ?? []
    );
}

function makeSkinEnvelope(positions) {
    const cellSize = 0.012;
    const y = new Map();
    const regionalY = new Map();
    for (let offset = 0; offset < positions.length; offset += 3) {
        const x = positions[offset];
        const vertical = positions[offset + 1];
        const z = positions[offset + 2];
        const verticalCell = Math.floor(vertical / cellSize);
        extendBodyEnvelope(y, verticalCell, x, z);
        extendBodyEnvelope(
            regionalY,
            `${bodyRegion(x, vertical)}:${verticalCell}`,
            x,
            z
        );
    }
    return { cellSize, y, regionalY };
}

function fitVenousGroupsInsideSkin(positions, groups, envelope) {
    const surfaceInset = 0.0015;
    let adjustedGroups = 0;
    let adjustedVertices = 0;
    let maximumShift = 0;
    const alreadyAdjusted = new Set();

    for (const group of groups) {
        const vertexIndices = [...new Set(group.indices)];
        const xCorrection = groupAxisCorrection(
            positions,
            vertexIndices,
            envelope,
            0,
            "xMinimum",
            "xMaximum",
            surfaceInset
        );
        const zCorrection = groupAxisCorrection(
            positions,
            vertexIndices,
            envelope,
            2,
            "zMinimum",
            "zMaximum",
            surfaceInset
        );
        const shift = Math.hypot(xCorrection, zCorrection);
        if (shift <= 0.00001 || shift > 0.04) continue;

        adjustedGroups += 1;
        maximumShift = Math.max(maximumShift, shift);
        for (const vertexIndex of vertexIndices) {
            if (alreadyAdjusted.has(vertexIndex)) continue;
            alreadyAdjusted.add(vertexIndex);
            positions[vertexIndex * 3] += xCorrection;
            positions[vertexIndex * 3 + 2] += zCorrection;
            adjustedVertices += 1;
        }
    }
    return { adjustedGroups, adjustedVertices, maximumShift };
}

function groupAxisCorrection(
    positions,
    vertexIndices,
    envelope,
    axis,
    minimumKey,
    maximumKey,
    inset
) {
    let positiveCorrection = 0;
    let negativeCorrection = 0;
    let positiveCount = 0;
    let negativeCount = 0;
    for (const vertexIndex of vertexIndices) {
        const offset = vertexIndex * 3;
        const x = positions[offset];
        const vertical = positions[offset + 1];
        const range = nearbyRegionalEnvelope(
            envelope,
            bodyRegion(x, vertical),
            vertical
        );
        if (!range) continue;
        const value = positions[offset + axis];
        if (value < range[minimumKey] + inset) {
            positiveCorrection = Math.max(
                positiveCorrection,
                range[minimumKey] + inset - value
            );
            positiveCount += 1;
        } else if (value > range[maximumKey] - inset) {
            negativeCorrection = Math.min(
                negativeCorrection,
                range[maximumKey] - inset - value
            );
            negativeCount += 1;
        }
    }
    if (positiveCount === 0) return negativeCorrection;
    if (negativeCount === 0) return positiveCorrection;
    return positiveCount >= negativeCount ? positiveCorrection : negativeCorrection;
}

function bodyRegion(x, vertical) {
    const absoluteX = Math.abs(x);
    if (vertical >= -0.2 && vertical < 0.68 && absoluteX > 0.205) {
        return x < 0 ? "left-arm" : "right-arm";
    }
    if (vertical < 0.08 && absoluteX > 0.035) {
        return x < 0 ? "left-leg" : "right-leg";
    }
    return "central";
}

function nearbyRegionalEnvelope(envelope, region, vertical) {
    const cell = Math.floor(vertical / envelope.cellSize);
    let result = null;
    for (let offset = -1; offset <= 1; offset += 1) {
        const range = envelope.regionalY.get(`${region}:${cell + offset}`);
        if (!range) continue;
        result = mergeBodyEnvelope(result, range);
    }
    return result ?? nearbyBodyEnvelope(envelope.y, vertical, envelope.cellSize);
}

function mergeBodyEnvelope(result, range) {
    if (!result) {
        return {
            xMinimum: range.xMinimum,
            xMaximum: range.xMaximum,
            zMinimum: range.zMinimum,
            zMaximum: range.zMaximum
        };
    }
    result.xMinimum = Math.min(result.xMinimum, range.xMinimum);
    result.xMaximum = Math.max(result.xMaximum, range.xMaximum);
    result.zMinimum = Math.min(result.zMinimum, range.zMinimum);
    result.zMaximum = Math.max(result.zMaximum, range.zMaximum);
    return result;
}

function extendBodyEnvelope(map, key, x, z) {
    const range = map.get(key);
    if (range) {
        range.xMinimum = Math.min(range.xMinimum, x);
        range.xMaximum = Math.max(range.xMaximum, x);
        range.zMinimum = Math.min(range.zMinimum, z);
        range.zMaximum = Math.max(range.zMaximum, z);
    } else {
        map.set(key, {
            xMinimum: x,
            xMaximum: x,
            zMinimum: z,
            zMaximum: z
        });
    }
}

function nearbyBodyEnvelope(map, vertical, cellSize) {
    const cell = Math.floor(vertical / cellSize);
    let result = null;
    for (let offset = -1; offset <= 1; offset += 1) {
        const range = map.get(cell + offset);
        if (!range) continue;
        result ??= {
            xMinimum: Infinity,
            xMaximum: -Infinity,
            zMinimum: Infinity,
            zMaximum: -Infinity
        };
        result.xMinimum = Math.min(result.xMinimum, range.xMinimum);
        result.xMaximum = Math.max(result.xMaximum, range.xMaximum);
        result.zMinimum = Math.min(result.zMinimum, range.zMinimum);
        result.zMaximum = Math.max(result.zMaximum, range.zMaximum);
    }
    return result;
}

function groupKind(name) {
    if (variantArgument === "female" && /penis|testicular|spermatic|scrotal|seminal|prostatic|deferential/i.test(name)) {
        return null;
    }
    if (/atrium|ventricle|papillary|leaflet|atrioventricular valve|semilunar/i.test(name)) {
        return null;
    }
    if (/vein|venous|vena|venae|sinus|portal/i.test(name)) return "venous";
    return "arterial";
}

function compactWeldedPositions(positions, positionRemap) {
    const values = [];
    const lookup = new Map();
    for (let sourceIndex = 0; sourceIndex < positionRemap.length; sourceIndex += 1) {
        const representative = positionRemap[sourceIndex];
        if (lookup.has(representative)) continue;
        lookup.set(representative, lookup.size);
        values.push(
            positions[representative * 3],
            positions[representative * 3 + 1],
            positions[representative * 3 + 2]
        );
    }
    return { values: new Float32Array(values), lookup };
}

function remapTriangles(indices, positionRemap, lookup) {
    const result = [];
    for (let offset = 0; offset < indices.length; offset += 3) {
        const a = lookup.get(positionRemap[indices[offset]]);
        const b = lookup.get(positionRemap[indices[offset + 1]]);
        const c = lookup.get(positionRemap[indices[offset + 2]]);
        if (a !== b && b !== c && c !== a) result.push(a, b, c);
    }
    return result;
}

function simplifyVascularGroups(
    groups,
    positionRemap,
    weldedPositions,
    simplifier,
    simplificationRatio
) {
    const positions = [];
    const indices = [];
    let sourceTriangles = 0;
    let preservedSmallBranchTriangles = 0;
    let maximumError = 0;
    let includedGroups = 0;
    let includedComponents = 0;

    for (const group of groups) {
        const remapped = remapTriangles(
            group.indices,
            positionRemap,
            weldedPositions.lookup
        );
        if (remapped.length < 3) continue;
        includedGroups += 1;
        for (const component of connectedTriangleComponents(remapped)) {
            includedComponents += 1;
            const sourceTriangleCount = component.length / 3;
            sourceTriangles += sourceTriangleCount;
            const vertexIndices = [...new Set(component)];
            const sourceToLocal = new Map(
                vertexIndices.map((sourceIndex, localIndex) => [sourceIndex, localIndex])
            );
            const localPositions = new Float32Array(vertexIndices.length * 3);
            for (const [localIndex, sourceIndex] of vertexIndices.entries()) {
                localPositions[localIndex * 3] = weldedPositions.values[sourceIndex * 3];
                localPositions[localIndex * 3 + 1] =
                    weldedPositions.values[sourceIndex * 3 + 1];
                localPositions[localIndex * 3 + 2] =
                    weldedPositions.values[sourceIndex * 3 + 2];
            }
            const localIndices = Uint32Array.from(
                component.map((sourceIndex) => sourceToLocal.get(sourceIndex))
            );
            const preserve = sourceTriangleCount <= 240;
            const targetTriangleCount = preserve
                ? sourceTriangleCount
                : Math.max(96, Math.floor(sourceTriangleCount * simplificationRatio));
            let simplifiedIndices = localIndices;
            if (targetTriangleCount < sourceTriangleCount) {
                const [result, error] = simplifier.simplify(
                    localIndices,
                    localPositions,
                    3,
                    targetTriangleCount * 3,
                    0.006,
                    ["RegularizeLight"]
                );
                simplifiedIndices = new Uint32Array(result);
                maximumError = Math.max(maximumError, error);
            } else {
                preservedSmallBranchTriangles += sourceTriangleCount;
            }
            const compactedIndices = new Uint32Array(simplifiedIndices);
            const [vertexRemap, compactedVertexCount] =
                simplifier.compactMesh(compactedIndices);
            const compactedPositions = compactPositions(
                localPositions,
                vertexRemap,
                compactedVertexCount
            );
            const vertexOffset = positions.length / 3;
            positions.push(...compactedPositions);
            for (const index of compactedIndices) {
                indices.push(index + vertexOffset);
            }
        }
    }
    return {
        positions: Float32Array.from(positions),
        indices: Uint32Array.from(indices),
        groups: includedGroups,
        components: includedComponents,
        sourceTriangles,
        preservedSmallBranchTriangles,
        maximumError
    };
}

function connectedTriangleComponents(indices) {
    const vertexIndices = [...new Set(indices)];
    const parents = new Map(vertexIndices.map((index) => [index, index]));
    const find = (value) => {
        let root = value;
        while (parents.get(root) !== root) root = parents.get(root);
        while (parents.get(value) !== value) {
            const next = parents.get(value);
            parents.set(value, root);
            value = next;
        }
        return root;
    };
    const union = (left, right) => {
        const a = find(left);
        const b = find(right);
        if (a !== b) parents.set(b, a);
    };
    for (let offset = 0; offset < indices.length; offset += 3) {
        union(indices[offset], indices[offset + 1]);
        union(indices[offset], indices[offset + 2]);
    }
    const components = new Map();
    for (let offset = 0; offset < indices.length; offset += 3) {
        const root = find(indices[offset]);
        const component = components.get(root) ?? [];
        component.push(indices[offset], indices[offset + 1], indices[offset + 2]);
        components.set(root, component);
    }
    return components.values();
}

function compactPositions(positions, vertexRemap, compactedVertexCount) {
    const result = new Float32Array(compactedVertexCount * 3);
    for (let oldIndex = 0; oldIndex < vertexRemap.length; oldIndex += 1) {
        const newIndex = vertexRemap[oldIndex];
        if (newIndex === 0xffffffff) continue;
        result[newIndex * 3] = positions[oldIndex * 3];
        result[newIndex * 3 + 1] = positions[oldIndex * 3 + 1];
        result[newIndex * 3 + 2] = positions[oldIndex * 3 + 2];
    }
    return result;
}

function transformPositions(positions, value) {
    const result = new Float32Array(positions.length);
    for (let offset = 0; offset < positions.length; offset += 3) {
        for (let axis = 0; axis < 3; axis += 1) {
            result[offset + axis] = positions[offset + axis] * value.scale[axis] + value.translation[axis];
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
        const ab = [positions[ib] - positions[ia], positions[ib + 1] - positions[ia + 1], positions[ib + 2] - positions[ia + 2]];
        const ac = [positions[ic] - positions[ia], positions[ic + 1] - positions[ia + 1], positions[ic + 2] - positions[ia + 2]];
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
        const length = Math.hypot(normals[offset], normals[offset + 1], normals[offset + 2]) || 1;
        normals[offset] /= length;
        normals[offset + 1] /= length;
        normals[offset + 2] /= length;
    }
    return normals;
}

function usdDocument(name, positions, normals, indices) {
    const minimum = [Infinity, Infinity, Infinity];
    const maximum = [-Infinity, -Infinity, -Infinity];
    for (let offset = 0; offset < positions.length; offset += 3) {
        for (let axis = 0; axis < 3; axis += 1) {
            minimum[axis] = Math.min(minimum[axis], positions[offset + axis]);
            maximum[axis] = Math.max(maximum[axis], positions[offset + axis]);
        }
    }
    const tuples = (values) => {
        const result = [];
        for (let offset = 0; offset < values.length; offset += 3) {
            result.push(`(${format(values[offset])}, ${format(values[offset + 1])}, ${format(values[offset + 2])})`);
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
    def Mesh "VascularMesh"
    {
        float3[] extent = [(${minimum.map(format).join(", ")}), (${maximum.map(format).join(", ")})]
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

function format(value) {
    if (!Number.isFinite(value)) return "0";
    const result = Number(value).toPrecision(8);
    return result.includes("e") ? result : result.replace(/\.?0+$/, "");
}
