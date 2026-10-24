#!/usr/bin/env python3
"""Test known calendar context in compact wake-history specialists.

This isolates calendar inputs from the larger complete-feature experiments.
It does not change the production predictor or the v6 baseline expert.
"""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import time
from zoneinfo import ZoneInfo

import numpy as np

from research_sleep_predictions import feature_rows, load_history, metrics
from research_sleep_regimes import run
from research_sleep_ensemble import combine


def weekly_features(data, zone, encoding):
    """Calendar transforms are fixed; no target or future row fits an encoder."""
    local = [dt.datetime.fromtimestamp(float(wake), ZoneInfo(zone)) for wake in data["wakes"]]
    weekday = np.array([day.weekday() for day in local])
    if encoding == "weekday":
        values = np.eye(7)[weekday]
        names = ["weekday" + str(day) for day in range(7)]
    elif encoding == "weeklyClock":
        minutes = np.array([day.hour * 60 + day.minute + day.second / 60 for day in local])
        phase = 2 * np.pi * (weekday * 1440 + minutes) / (7 * 1440)
        values = np.column_stack([np.sin(phase), np.cos(phase), np.sin(2 * phase), np.cos(2 * phase)])
        names = ["weekClockSin1", "weekClockCos1", "weekClockSin2", "weekClockCos2"]
    else:
        raise ValueError("Unknown weekly encoding")
    return dict(data, X=np.column_stack([data["X"], values]), names=np.array(list(data["names"]) + names))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["source", "features", "baseline", "incumbent", "output"]:
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--birth-date", required=True)
    parser.add_argument("--time-zone", required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root):
        parser.error("Keep history-derived results outside the repository")
    source_hash = hashlib.sha256(args.source.read_bytes()).hexdigest()
    baseline, incumbent = [json.loads(path.read_text()) for path in [args.baseline, args.incumbent]]
    assert baseline["audit"]["sourceSHA256"] == incumbent["audit"]["sourceSHA256"] == source_hash
    data = dict(np.load(args.features, allow_pickle=False))
    sleeps, care, birth, zone = load_history(args.source, args.birth_date, args.time_zone)
    expected = feature_rows(sleeps, care, birth, zone)
    for key in ["indices", "wakes", "available", "y"]:
        np.testing.assert_allclose(data[key], expected[key], rtol=0, atol=1e-6)
    positions = [expected["names"].index(name) for name in data["names"]]
    np.testing.assert_allclose(data["X"], expected["X"][:, positions], rtol=0, atol=1e-6, equal_nan=True)
    rows = {r["index"]: r for r in baseline["events"]}
    current = {r["index"]: r for r in incumbent["events"]}
    indices = data["indices"].astype(int).tolist()
    assert set(indices) == set(rows) == set(current)
    for reference in [rows, current]:
        np.testing.assert_allclose([reference[i]["actual"] for i in indices], data["available"], rtol=0, atol=1e-6)
        np.testing.assert_allclose([reference[i]["wakeMinutes"] for i in indices], data["y"], rtol=0, atol=1e-6)
    fallback = np.array([(rows[i]["prediction"] - wake) / 60 for i, wake in zip(indices, data["wakes"])])
    all_rows = np.ones(len(indices), dtype=bool)
    result = dict(audit=dict(sourceSHA256=source_hash, careExposure="completed", baselineAlgorithm=baseline["algorithm"],
        incumbentAlgorithm=incumbent["algorithm"], baselineResultSHA256=hashlib.sha256(args.baseline.read_bytes()).hexdigest(),
        incumbentResultSHA256=hashlib.sha256(args.incumbent.read_bytes()).hexdigest(),
        featureCacheSHA256=hashlib.sha256(args.features.read_bytes()).hexdigest(),
        timeZone=args.time_zone, lookbackDays=60, refitEvery=24,
        rule="Fixed wake-time calendar encodings; past available labels only; unchanged baseline and combination policies"),
        models={}, events={}, incumbentMetrics=incumbent["metrics"]["all"])

    def save(name, prediction, **details):
        result["models"][name] = dict(all=metrics(data["y"], prediction, all_rows), **details)
        result["events"][name] = [dict(index=i, actual=float(y), prediction=float(p)) for i, y, p in zip(indices, data["y"], prediction)]
        args.output.write_text(json.dumps(result, indent=2) + "\n")
        print(name, json.dumps(result["models"][name]), flush=True)

    variants = [("localCalibratedSoft", "soft", True, True), ("localCalibratedBest", "best", True, True),
        ("localRawSoft", "soft", False, True), ("globalCalibratedSoft", "soft", True, False),
        ("calibratedMedian", "median", True, True)]
    for encoding in ["weekday", "weeklyClock"]:
        augmented = weekly_features(data, args.time_zone, encoding)
        experts = [fallback]
        for policy in ["previousKind", "wakePhase", "cycleStage"]:
            started = time.monotonic()
            prediction, counts = run(augmented, fallback, policy)
            experts.append(prediction)
            save(encoding + "_" + policy, prediction, featureCount=len(augmented["names"]),
                refits=int(np.sum(counts > 0)), seconds=time.monotonic() - started)
        for name, policy, calibrate, local in variants:
            prediction = combine(augmented, np.column_stack(experts), policy=policy, calibrate=calibrate, local=local)
            save(encoding + "_" + name, prediction, featureCount=len(augmented["names"]))


if __name__ == "__main__":
    main()
