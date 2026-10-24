#!/usr/bin/env python3
"""Test fixed, past-only numeric interpretations of structured care fields."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import time
from zoneinfo import ZoneInfo
import numpy as np
from research_sleep_predictions import read_structured_records, run_candidate
from research_sleep_ensemble import combine, metrics


def nursing_segment(value):
    match = re.fullmatch(r"(\d{2}):(\d{2})([LR])", value.strip().upper())
    if not match or int(match[2]) >= 60:
        return None
    minutes = int(match[1]) * 60 + int(match[2])
    return (minutes, match[3]) if minutes > 0 else None


def care_values(records, wakes):
    """No vocabulary fit or notes; the export's fixed duration/side grammar only."""
    nursing, diapers = [], []
    for record in records:
        start, end = record["startEpoch"], record["endEpoch"]
        if end < start:
            continue
        if record["Type"] == "Feed":
            segments = [nursing_segment(record.get(field, "")) for field in ["Start Condition", "End Condition"]]
            segments = [s for s in segments if s is not None]
            if segments:
                left = sum(m for m, side in segments if side == "L")
                right = sum(m for m, side in segments if side == "R")
                nursing.append((start, end, left + right, left / (left + right), len(segments)))
        elif record["Type"] == "Diaper":
            text = record.get("End Condition", "").lower()
            wet = bool(re.search(r"\b(?:both|pee|wet)\b", text))
            dirty = bool(re.search(r"\b(?:both|poo|dirty|soiled)\b", text))
            loose = bool(re.search(r"\b(?:loose|watery)\b", text))
            diapers.append((start, end, float(wet), float(dirty), float(loose)))
    nursing = np.asarray(nursing, dtype=float).reshape(-1, 5)
    diapers = np.asarray(diapers, dtype=float).reshape(-1, 5)
    names = ["nursingLastMinutes", "nursingLastLeftFraction", "nursingLastSegments",
             "nursingMinutes3h", "nursingMinutes12h", "nursingMinutes24h", "nursingTwoSegmentFraction12h",
             "diaperWetCount12h", "diaperDirtyCount12h", "lastWetMinutes", "lastDirtyMinutes",
             "lastDiaperLooseFlag", "diaperLooseCount24h"]
    output = []
    for now in wakes:
        known = nursing[(nursing[:, 0] <= now) & (nursing[:, 1] <= now)]
        if len(known):
            last = known[np.argmax(known[:, 1])]
            values = [last[2], last[3], last[4]]
        else:
            values = [np.nan] * 3
        values += [float(np.sum(known[known[:, 1] >= now - h * 3600, 2])) for h in [3, 12, 24]]
        recent = known[known[:, 1] >= now - 12 * 3600]
        values.append(float(np.mean(recent[:, 4] == 2)) if len(recent) else np.nan)
        known = diapers[(diapers[:, 0] <= now) & (diapers[:, 1] <= now)]
        recent = known[known[:, 1] >= now - 12 * 3600]
        values += [float(np.sum(recent[:, 2])), float(np.sum(recent[:, 3]))]
        for column in [2, 3]:
            matching = known[known[:, column] == 1]
            values.append(min(2880., (now - np.max(matching[:, 1])) / 60) if len(matching) else np.nan)
        values.append(float(known[np.argmax(known[:, 1]), 4]) if len(known) else np.nan)
        values.append(float(np.sum(known[known[:, 1] >= now - 24 * 3600, 4])))
        output.append(values)
    return np.asarray(output, dtype=float).reshape(-1, len(names)), names


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["source", "features", "baseline", "output"]:
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--time-zone", required=True)
    parser.add_argument("--feature-cache", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    for path in [args.output, args.feature_cache]:
        if path and path.resolve().is_relative_to(root):
            parser.error("Keep private results and derived features outside the repository")
    data = dict(np.load(args.features, allow_pickle=False))
    base = json.loads(args.baseline.read_text())
    digest = hashlib.sha256(args.source.read_bytes()).hexdigest()
    assert base["audit"]["sourceSHA256"] == digest
    records = read_structured_records(args.source, ZoneInfo(args.time_zone))
    extra, names = care_values(records, data["wakes"])
    enriched = dict(data, X=np.column_stack([data["X"], extra]), names=np.asarray([*data["names"], *names]))
    if args.feature_cache:
        np.savez_compressed(args.feature_cache, **enriched)
    indices = data["indices"].astype(int).tolist()
    rows = {r["index"]: r for r in base["events"]}
    assert set(rows) == set(indices)
    np.testing.assert_allclose([rows[i]["actual"] for i in indices], data["available"], rtol=0, atol=1e-6)
    np.testing.assert_allclose([rows[i]["wakeMinutes"] for i in indices], data["y"], rtol=0, atol=1e-6)
    fallback = (np.array([rows[i]["prediction"] for i in indices]) - data["wakes"]) / 60
    result = dict(audit=dict(sourceSHA256=digest, careExposure="completed", timeZone=args.time_zone,
        originalFeatureCount=len(data["names"]), enrichedFeatureCount=len(enriched["names"]), addedFeatureNames=names,
        featureCacheSHA256=hashlib.sha256(args.features.read_bytes()).hexdigest(),
        baselineResultSHA256=hashlib.sha256(args.baseline.read_bytes()).hexdigest(),
        scriptSHA256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        rule="Fixed structured-field grammar; completed records only; no notes or fitted vocabulary; unchanged controls",
        lookbackDays=60, refitEvery=24), models={}, events={})
    def save(name, prediction, **details):
        result["models"][name] = dict(all=metrics(data["y"], prediction, np.ones(len(indices), dtype=bool)), **details)
        result["events"][name] = [dict(index=i, actual=float(y), prediction=float(p))
            for i, y, p in zip(indices, data["y"], prediction)]
        args.output.write_text(json.dumps(result, indent=2) + "\n")
        print(name, json.dumps(result["models"][name]), flush=True)
    members = [fallback]
    for kind, inputs in [("control", data), ("values", enriched)]:
        for model in ["hist_absolute_error_7_10", "extra_5"]:
            started = time.monotonic()
            prediction, train_counts = run_candidate(model, inputs, fallback, 60, 24)
            save(kind + "_" + model, prediction, seconds=time.monotonic() - started,
                 fits=int(np.sum(train_counts >= 40)))
            if kind == "values":
                members.append(prediction)
    for name, policy, calibrate, local in [("localCalibratedSoft", "soft", True, True),
        ("localCalibratedBest", "best", True, True), ("localRawSoft", "soft", False, True),
        ("globalCalibratedSoft", "soft", True, False), ("calibratedMedian", "median", True, True)]:
        save("careValues_" + name, combine(enriched, np.column_stack(members), policy, calibrate, local))


if __name__ == "__main__":
    main()
