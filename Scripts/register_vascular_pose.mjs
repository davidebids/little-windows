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

const [inputArgument, skinArgument, referenceArgument, outputArgument] = process.argv.slice(2);

if (!inputArgument || !skinArgument || !referenceArgument || !outputArgument) {
    console.error(
        "Usage: node Scripts/register_vascular_pose.mjs " +
        "anatomy-system.usdc skin.usdc registered-nervous-system.usdc output.usdc"
    );
    process.exit(2);
}

const workingDirectory = mkdtempSync(join(tmpdir(), "littlewindows-anatomy-pose-"));

try {
    const input = loadUSD(inputArgument, "anatomy-system");
    const skin = loadUSD(skinArgument, "skin");
    const reference = loadUSD(referenceArgument, "reference");
    const registration = registerPose(
        input.points,
        skin.points,
        reference.points,
        basename(inputArgument)
    );
    const normals = smoothNormals(input.points, input.indices);
    const resultUSDA = join(workingDirectory, "registered.usda");
    const resultUSDC = join(workingDirectory, "registered.usdc");

    writeFileSync(
        resultUSDA,
        usdDocument(
            sanitizeIdentifier(basename(outputArgument, ".usdc")),
            input.points,
            normals,
            input.indices
        )
    );
    execFileSync("/usr/bin/usdcat", [resultUSDA, "-o", resultUSDC], { stdio: "inherit" });
    copyFileSync(resultUSDC, resolve(outputArgument));
    chmodSync(resolve(outputArgument), 0o644);
    console.log(JSON.stringify(registration, null, 2));
} finally {
    rmSync(workingDirectory, { recursive: true, force: true });
}

function loadUSD(argument, name) {
    const sourceUSDA = join(workingDirectory, `${name}.usda`);
    execFileSync("/usr/bin/usdcat", [resolve(argument), "-o", sourceUSDA], {
        stdio: "ignore"
    });
    const source = readFileSync(sourceUSDA, "utf8");
    return {
        points: parseTupleAttribute(source, "point3f[] points"),
        indices: Uint32Array.from(
            parseScalarAttribute(source, "int[] faceVertexIndices", Number)
        )
    };
}

function parseTupleAttribute(source, attributeName) {
    const match = source.match(
        new RegExp(`${escapeRegExp(attributeName)}\\s*=\\s*\\[([\\s\\S]*?)\\]`)
    );
    if (!match) throw new Error(`Missing ${attributeName}`);
    return Float32Array.from(
        match[1].match(/-?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?/gi)?.map(Number) ?? []
    );
}

function parseScalarAttribute(source, attributeName, converter) {
    const match = source.match(
        new RegExp(`${escapeRegExp(attributeName)}\\s*=\\s*\\[([\\s\\S]*?)\\]`)
    );
    if (!match) throw new Error(`Missing ${attributeName}`);
    return match[1]
        .split(",")
        .map((value) => converter(value.trim()))
        .filter(Number.isFinite);
}

function registerPose(points, skinPoints, referencePoints, inputName) {
    const source = landmarks(points);
    const skin = landmarks(skinPoints);
    const reference = landmarks(referencePoints);
    const isVascular = /Vascular/i.test(inputName);
    const handCorrections = {};
    const footCorrections = {};
    const armEnvelopeRegistrations = Object.fromEntries(
        ["left", "right"].map((side) => [
            side,
            makeArmEnvelopeRegistration(points, skinPoints, side)
        ])
    );

    for (const side of ["left", "right"]) {
        const hand = `${side}Hand`;
        handCorrections[side] = {
            x: axisRegistration(source[hand], reference[hand], "x"),
            y: axisRegistration(source[hand], reference[hand], "y"),
            z: axisRegistration(source[hand], reference[hand], "z")
        };
        const foot = `${side}Foot`;
        footCorrections[side] = {
            x: axisRegistration(source[foot], reference[foot], "x"),
            y: axisRegistration(source[foot], reference[foot], "y"),
            z: axisRegistration(source[foot], reference[foot], "z")
        };
    }

    // Fit the skull and head structures to the actual body surface. Using a
    // different internal system as the head envelope made the skull visibly
    // undersized even though it technically remained inside the model.
    const headScale = axisScaleToFit(source.head, skin.head, -0.003);
    const headSourceCenter = {
        x: boundsCenter(source.head, "x"),
        z: boundsCenter(source.head, "z")
    };
    const headTargetCenter = {
        x: boundsCenter(skin.head, "x"),
        z: boundsCenter(skin.head, "z")
    };

    for (let offset = 0; offset < points.length; offset += 3) {
        const x = points[offset];
        const y = points[offset + 1];
        const z = points[offset + 2];
        const absoluteX = Math.abs(x);

        if (y > 0.66) {
            const blend = smoothstep(0.66, 0.71, y);
            const registeredX = headTargetCenter.x +
                (x - headSourceCenter.x) * headScale.x;
            const registeredZ = headTargetCenter.z +
                (z - headSourceCenter.z) * headScale.z;
            points[offset] = mix(x, registeredX, blend);
            points[offset + 2] = mix(z, registeredZ, blend);
            continue;
        }

        const side = x < 0 ? "left" : "right";
        const armRegistration = armEnvelopeRegistrations[side];
        const armShift = armEnvelopeShift(armRegistration, absoluteX, y);
        if (armShift) {
            points[offset] += (x < 0 ? armShift.inward : -armShift.inward) *
                armShift.blend;
        }

        // The atlas systems already share the same shoulder, elbow, hip, knee,
        // and ankle pose. Only the hand meshes differ in their exported finger
        // spread. Confining the correction to the distal hand prevents the old
        // hand-derived affine transform from pulling the upper arm and clavicle
        // away from the body.
        const handBlendStart = isVascular ? 0.27 : 0.30;
        const handBlendEnd = isVascular ? 0.355 : 0.385;
        if (absoluteX > handBlendStart && y > -0.18 && y < 0.28) {
            const blend = smoothstep(handBlendStart, handBlendEnd, absoluteX);
            points[offset] = mix(
                x,
                registerAxis(x, handCorrections[side].x),
                blend
            );
            points[offset + 1] = mix(
                y,
                registerAxis(y, handCorrections[side].y),
                blend
            );
            points[offset + 2] = mix(
                z,
                registerAxis(z, handCorrections[side].z),
                blend
            );
        }

        if (absoluteX > 0.035 && absoluteX < 0.34 && y < -0.58) {
            const footSide = x < 0 ? "left" : "right";
            const blend = smoothstep(-0.58, -0.72, y) *
                smoothstep(0.025, 0.065, absoluteX);
            points[offset] = mix(
                points[offset],
                registerAxis(points[offset], footCorrections[footSide].x),
                blend
            );
            points[offset + 1] = mix(
                points[offset + 1],
                registerAxis(points[offset + 1], footCorrections[footSide].y),
                blend
            );
            points[offset + 2] = mix(
                points[offset + 2],
                registerAxis(points[offset + 2], footCorrections[footSide].z),
                blend
            );
        }
    }

    return {
        handCorrections,
        footCorrections,
        armEnvelopeRegistrations: Object.fromEntries(
            Object.entries(armEnvelopeRegistrations).map(([side, value]) => [
                side,
                {
                    samples: value.samples.length,
                    maximumShift: Number(value.maximumShift.toFixed(5))
                }
            ])
        ),
        headScale,
        containment: containmentAudit(points, skinPoints)
    };
}

function makeArmEnvelopeRegistration(sourcePoints, skinPoints, side) {
    const samples = [];
    let maximumShift = 0;
    for (let y = 0.10; y <= 0.64; y += 0.015) {
        const source = outerArmExtent(sourcePoints, side, y);
        const target = outerArmExtent(skinPoints, side, y);
        if (!source || !target) continue;
        const inward = Math.max(0, source.maximumX - target.maximumX + 0.003);
        maximumShift = Math.max(maximumShift, inward);
        samples.push({
            y,
            inward,
            sourceMinimumX: source.minimumX,
            sourceMaximumX: source.maximumX
        });
    }
    return { samples, maximumShift };
}

function outerArmExtent(points, side, yCenter) {
    const values = [];
    const sign = side === "left" ? -1 : 1;
    const minimumX = armInnerBoundary(yCenter) - 0.025;
    for (let offset = 0; offset < points.length; offset += 3) {
        const x = points[offset];
        const y = points[offset + 1];
        const z = points[offset + 2];
        const absoluteX = Math.abs(x);
        if (
            Math.sign(x) !== sign ||
            Math.abs(y - yCenter) > 0.011 ||
            absoluteX < minimumX ||
            absoluteX > 0.58
        ) continue;
        values.push(absoluteX);
    }
    if (values.length < 5) return null;
    values.sort((left, right) => left - right);
    const minimum = quantile(values, 0.05);
    const maximum = quantile(values, 0.985);
    return {
        minimumX: minimum,
        maximumX: maximum
    };
}

function armEnvelopeShift(registration, absoluteX, y) {
    const samples = registration.samples;
    if (samples.length < 2 || y < samples[0].y || y > samples.at(-1).y) return null;
    let upperIndex = samples.findIndex((sample) => sample.y >= y);
    if (upperIndex < 0) upperIndex = samples.length - 1;
    const lower = samples[Math.max(0, upperIndex - 1)];
    const upper = samples[upperIndex];
    const amount = upper.y === lower.y ? 0 : (y - lower.y) / (upper.y - lower.y);
    const minimumX = mix(lower.sourceMinimumX, upper.sourceMinimumX, amount);
    const innerBlend = smoothstep(minimumX - 0.025, minimumX + 0.012, absoluteX);
    const shoulderBlend = smoothstep(0.64, 0.605, y);
    const blend = innerBlend * shoulderBlend;
    if (blend <= 0) return null;
    return {
        inward: mix(lower.inward, upper.inward, amount),
        blend
    };
}

function armInnerBoundary(y) {
    const anchors = [
        [0.10, 0.285],
        [0.18, 0.255],
        [0.30, 0.19],
        [0.44, 0.16],
        [0.64, 0.14]
    ];
    for (let index = 1; index < anchors.length; index += 1) {
        const [nextY, nextX] = anchors[index];
        const [previousY, previousX] = anchors[index - 1];
        if (y <= nextY) {
            return mix(
                previousX,
                nextX,
                (y - previousY) / (nextY - previousY)
            );
        }
    }
    return anchors.at(-1)[1];
}

function quantile(sortedValues, amount) {
    return sortedValues[
        Math.min(sortedValues.length - 1, Math.floor((sortedValues.length - 1) * amount))
    ];
}


function landmarks(points) {
    const selectors = {
        leftHand: (x, y) => x < -0.34 && y < 0.16,
        rightHand: (x, y) => x > 0.34 && y < 0.16,
        leftFoot: (x, y) => x < -0.04 && y < -0.68,
        rightFoot: (x, y) => x > 0.04 && y < -0.68,
        head: (x, y) => Math.abs(x) < 0.14 && y > 0.68
    };
    return Object.fromEntries(
        Object.entries(selectors).map(([name, selector]) => [
            name,
            landmark(points, selector)
        ])
    );
}

function landmark(points, selector) {
    const result = {
        count: 0,
        center: { x: 0, y: 0, z: 0 },
        minimum: { x: Infinity, y: Infinity, z: Infinity },
        maximum: { x: -Infinity, y: -Infinity, z: -Infinity }
    };
    for (let offset = 0; offset < points.length; offset += 3) {
        const x = points[offset];
        const y = points[offset + 1];
        const z = points[offset + 2];
        if (!selector(x, y)) continue;
        result.count += 1;
        result.center.x += x;
        result.center.y += y;
        result.center.z += z;
        result.minimum.x = Math.min(result.minimum.x, x);
        result.minimum.y = Math.min(result.minimum.y, y);
        result.minimum.z = Math.min(result.minimum.z, z);
        result.maximum.x = Math.max(result.maximum.x, x);
        result.maximum.y = Math.max(result.maximum.y, y);
        result.maximum.z = Math.max(result.maximum.z, z);
    }
    if (result.count === 0) throw new Error("Required anatomy landmark has no vertices");
    result.center.x /= result.count;
    result.center.y /= result.count;
    result.center.z /= result.count;
    return result;
}

function axisScaleToFit(source, target, margin) {
    return Object.fromEntries(["x", "z"].map((axis) => {
        const sourceExtent = source.maximum[axis] - source.minimum[axis];
        const targetExtent = target.maximum[axis] - target.minimum[axis] + margin * 2;
        return [axis, Math.min(1, targetExtent / sourceExtent)];
    }));
}

function axisRegistration(source, target, axis) {
    const sourceExtent = source.maximum[axis] - source.minimum[axis];
    const targetExtent = target.maximum[axis] - target.minimum[axis];
    return {
        sourceCenter: boundsCenter(source, axis),
        targetCenter: boundsCenter(target, axis),
        scale: targetExtent / sourceExtent
    };
}

function registerAxis(value, registration) {
    return registration.targetCenter +
        (value - registration.sourceCenter) * registration.scale;
}

function boundsCenter(value, axis) {
    return (value.minimum[axis] + value.maximum[axis]) / 2;
}

function containmentAudit(points, skinPoints) {
    const envelope = makeSkinEnvelope(skinPoints);
    let outsideVertices = 0;
    let maximumDistance = 0;
    for (let offset = 0; offset < points.length; offset += 3) {
        const x = points[offset];
        const y = points[offset + 1];
        const z = points[offset + 2];
        const range = nearbyEnvelope(envelope, bodyRegion(x, y), y);
        if (!range) continue;
        const distance = Math.hypot(
            x < range.xMinimum ? range.xMinimum - x :
                x > range.xMaximum ? x - range.xMaximum : 0,
            z < range.zMinimum ? range.zMinimum - z :
                z > range.zMaximum ? z - range.zMaximum : 0
        );
        if (distance > 0.0025) {
            outsideVertices += 1;
            maximumDistance = Math.max(maximumDistance, distance);
        }
    }
    return {
        outsideVertices,
        outsidePercent: Number((outsideVertices / (points.length / 3) * 100).toFixed(2)),
        maximumDistance: Number(maximumDistance.toFixed(5))
    };
}

function makeSkinEnvelope(points) {
    const cellSize = 0.012;
    const cells = new Map();
    for (let offset = 0; offset < points.length; offset += 3) {
        const x = points[offset];
        const y = points[offset + 1];
        const z = points[offset + 2];
        const key = `${bodyRegion(x, y)}:${Math.floor(y / cellSize)}`;
        const range = cells.get(key) ?? {
            xMinimum: Infinity,
            xMaximum: -Infinity,
            zMinimum: Infinity,
            zMaximum: -Infinity
        };
        range.xMinimum = Math.min(range.xMinimum, x);
        range.xMaximum = Math.max(range.xMaximum, x);
        range.zMinimum = Math.min(range.zMinimum, z);
        range.zMaximum = Math.max(range.zMaximum, z);
        cells.set(key, range);
    }
    return { cellSize, cells };
}

function nearbyEnvelope(envelope, region, y) {
    const cell = Math.floor(y / envelope.cellSize);
    let result = null;
    for (let delta = -4; delta <= 4; delta += 1) {
        const value = envelope.cells.get(`${region}:${cell + delta}`);
        if (!value) continue;
        result ??= { ...value };
        result.xMinimum = Math.min(result.xMinimum, value.xMinimum);
        result.xMaximum = Math.max(result.xMaximum, value.xMaximum);
        result.zMinimum = Math.min(result.zMinimum, value.zMinimum);
        result.zMaximum = Math.max(result.zMaximum, value.zMaximum);
    }
    return result;
}

function bodyRegion(x, y) {
    const absoluteX = Math.abs(x);
    if (y >= -0.2 && y < 0.62 && absoluteX > 0.205) {
        return x < 0 ? "left-arm" : "right-arm";
    }
    if (y < 0.08 && absoluteX > 0.035) {
        return x < 0 ? "left-leg" : "right-leg";
    }
    return "central";
}

function smoothstep(edge0, edge1, value) {
    const ratio = (value - edge0) / (edge1 - edge0);
    const t = Math.max(0, Math.min(1, ratio));
    return t * t * (3 - 2 * t);
}

function mix(start, end, amount) {
    return start + (end - start) * amount;
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
    def Mesh "VascularMesh"
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

function escapeRegExp(value) {
    return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
