#!/usr/bin/env python3
"""Paired day-block bootstrap for a fixed retrospective sleep forecast comparison.

Intervals describe variation in this one observed history. They do not account
for model-selection optimism or establish independent predictive performance.
"""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
from zoneinfo import ZoneInfo

import numpy as np


def summarize(actual, predictions, reference, days, repetitions=5000):
    if not (len(actual) == len(predictions) == len(reference) == len(days)):
        raise ValueError("Comparison arrays must describe identical cohorts")
    if not all(np.all(np.isfinite(values)) for values in [actual, predictions, reference]):
        raise ValueError("Expected finite outcomes and predictions")
    labels, groups = np.unique(days, return_inverse=True)
    if not len(labels):
        raise ValueError("Expected at least one scored day")
    error, previous = np.abs(actual - predictions), np.abs(actual - reference)
    values = np.column_stack([np.ones(len(actual)), error, error <= 30,
                              previous - error, (error <= 30).astype(float) - (previous <= 30)])
    daily = np.zeros((len(labels), values.shape[1]))
    np.add.at(daily, groups, values)
    counts = np.random.default_rng(42).multinomial(len(labels), np.full(len(labels), 1 / len(labels)), repetitions)
    samples = counts @ daily
    estimates = samples[:, 1:] / samples[:, :1]
    estimates[:, [1, 3]] *= 100
    point = np.sum(daily, axis=0)
    point = point[1:] / point[0]
    point[[1, 3]] *= 100
    names = ["maeMinutes", "within30Percent", "maeImprovementMinutes", "within30ImprovementPercentagePoints"]
    return dict(dayCount=len(labels), caseCount=len(actual), repetitions=repetitions,
                metrics={name: dict(estimate=float(point[k]), interval95=np.quantile(estimates[:, k], [.025, .975]).tolist())
                         for k, name in enumerate(names)})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--reference", type=Path)
    parser.add_argument("--reference-model")
    parser.add_argument("--time-zone", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.resolve().is_relative_to(Path(__file__).resolve().parents[1]):
        parser.error("Keep research results outside the repository")
    if bool(args.reference) != bool(args.reference_model):
        parser.error("Supply reference file and model together")
    baseline = json.loads(args.baseline.read_text())
    rows = sorted(baseline["events"], key=lambda row: row["index"])
    indices = [row["index"] for row in rows]
    actual = np.array([row["wakeMinutes"] for row in rows])
    wakes = np.array([row["actual"] for row in rows]) - actual * 60
    reference = (np.array([row["prediction"] for row in rows]) - wakes) / 60
    def read(path, name):
        result = json.loads(path.read_text())
        assert result["audit"]["sourceSHA256"] == baseline["audit"]["sourceSHA256"]
        events = {row["index"]: row for row in result["events"][name]}
        assert set(events) == set(indices)
        np.testing.assert_allclose([events[i]["actual"] for i in indices], actual, rtol=0, atol=1e-6)
        return np.array([events[i]["prediction"] for i in indices])
    prediction = read(args.candidate, args.model)
    if args.reference:
        reference = read(args.reference, args.reference_model)
    days = [dt.datetime.fromtimestamp(wake, ZoneInfo(args.time_zone)).date().isoformat() for wake in wakes]
    result = summarize(actual, prediction, reference, days)
    result.update(sourceSHA256=baseline["audit"]["sourceSHA256"], candidate=args.model,
                  reference=args.reference_model or baseline.get("algorithm", "appBaseline"),
                  candidateResultSHA256=hashlib.sha256(args.candidate.read_bytes()).hexdigest(),
                  referenceResultSHA256=hashlib.sha256((args.reference or args.baseline).read_bytes()).hexdigest(),
                  scope="Paired wake-date bootstrap; one retrospective history; excludes model-selection uncertainty")
    args.output.write_text(json.dumps(result, indent=2))
    print(json.dumps(result))


if __name__ == "__main__":
    main()
