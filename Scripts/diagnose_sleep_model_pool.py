#!/usr/bin/env python3
"""Hindsight-only limits of selecting or convexly blending a fixed model pool.

These are diagnostic bounds for supplied forecasts, never deployable forecasts
or bounds on untested algorithms. Per-event data stays outside the repository.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from sleep_research_metadata import care_exposure


def diagnose(actual, predictions):
    if predictions.ndim != 2 or predictions.shape[0] != len(actual):
        raise ValueError("Expected one prediction row per outcome")
    if not predictions.shape[1] or not np.all(np.isfinite(predictions)) or not np.all(np.isfinite(actual)):
        raise ValueError("Expected finite outcomes and a nonempty finite model pool")
    selection_error = np.min(np.abs(predictions - actual[:, None]), axis=1)
    hull_error = np.maximum(np.maximum(np.min(predictions, axis=1) - actual,
                                       actual - np.max(predictions, axis=1)), 0)
    def metrics(errors):
        return dict(count=len(errors), mae=float(np.mean(errors)),
                    within30=float(np.mean(errors <= 30) * 100))
    return dict(perfectSelection=metrics(selection_error),
                perfectConvexCombination=metrics(hull_error), candidatesPerCase=predictions.shape[1])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--members", type=Path, nargs="+", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.resolve().is_relative_to(Path(__file__).resolve().parents[1]):
        parser.error("Keep research results outside the repository")
    baseline = json.loads(args.baseline.read_text())
    rows = sorted(baseline["events"], key=lambda r: r["index"])
    indices = [r["index"] for r in rows]
    actual = np.array([r["wakeMinutes"] for r in rows])
    wakes = np.array([r["actual"] for r in rows]) - actual * 60
    members = [(np.array([r["prediction"] for r in rows]) - wakes) / 60]
    for path in args.members:
        candidate = json.loads(path.read_text())
        assert candidate["audit"]["sourceSHA256"] == baseline["audit"]["sourceSHA256"]
        assert care_exposure(candidate) == "completed", "Keep started-care assumptions separate"
        for events in candidate["events"].values():
            by_index = {r["index"]: r for r in events}
            assert set(by_index) == set(indices)
            np.testing.assert_allclose([by_index[i]["actual"] for i in indices], actual, rtol=0, atol=1e-6)
            prediction = np.array([by_index[i]["prediction"] for i in indices])
            if not any(np.array_equal(prediction, member) for member in members):
                members.append(prediction)
    result = diagnose(actual, np.column_stack(members))
    result["sourceSHA256"] = baseline["audit"]["sourceSHA256"]
    result["baselineResultSHA256"] = hashlib.sha256(args.baseline.read_bytes()).hexdigest()
    result["memberResultsSHA256"] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in args.members}
    result["scope"] = "Hindsight diagnostic only; not a forecast or a bound on untested models"
    args.output.write_text(json.dumps(result, indent=2))
    print(json.dumps(result))


if __name__ == "__main__":
    main()
