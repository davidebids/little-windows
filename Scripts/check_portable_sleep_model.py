#!/usr/bin/env python3
"""Compile native feature extraction/training and compare the full external replay.

Raw input and intermediate arrays live only in a temporary folder. The saved
output is an aggregate verification report, not a trained personal model.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

import numpy as np

from research_sleep_predictions import feature_rows, load_history


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--birth-date", required=True)
    parser.add_argument("--time-zone", required=True)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--trees", type=int, default=80)
    parser.add_argument("--minimum-leaf", type=int, default=5)
    parser.add_argument("--refit-every", type=int, default=48)
    parser.add_argument("--native-only", action="store_true", help="Evaluate another refit cadence after a successful full component check")
    parser.add_argument("--component-check", type=Path)
    parser.add_argument("--forecast-output", type=Path, help="Optional private per-event result file outside the repository")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root):
        parser.error("Keep history-derived reports outside the repository")
    if args.forecast_output and args.forecast_output.resolve().is_relative_to(root):
        parser.error("Keep per-event results outside the repository")
    if min(args.trees, args.minimum_leaf, args.refit_every) <= 0:
        parser.error("Tree count, minimum leaf size, and refit interval must be positive")
    if args.native_only and not args.component_check:
        parser.error("Native-only evaluation requires the successful current-source component check")
    baseline, reference = [json.loads(path.read_text()) for path in [args.baseline, args.reference]]
    source_hash = hashlib.sha256(args.input.read_bytes()).hexdigest()
    assert baseline["audit"]["sourceSHA256"] == reference["audit"]["sourceSHA256"] == source_hash
    sleeps, care, birth, zone = load_history(args.input, args.birth_date, args.time_zone)
    expected = feature_rows(sleeps, care, birth, zone)
    baseline_rows = {row["index"]: row for row in baseline["events"]}
    assert set(expected["indices"]) == set(baseline_rows)
    np.testing.assert_allclose([baseline_rows[int(i)]["actual"] for i in expected["indices"]], expected["available"], rtol=0, atol=1e-6)
    payload = dict(birth=birth, zone=str(zone), trees=args.trees, minimumLeaf=args.minimum_leaf, refitEvery=args.refit_every,
                   sleeps=[dict(start=float(s), end=float(e), night=bool(n)) for s, e, n in sleeps],
                   care=[dict(start=s, end=e) for s, e, kind in care if kind == "Feed"],
                   fallback=[dict(index=int(i), minutes=(baseline_rows[int(i)]["prediction"] - expected["wakes"][j]) / 60)
                             for j, i in enumerate(expected["indices"])])
    sources = [root / "LittleWindows/Services" / name for name in
               ["PortableSleepFeatures.swift", "PortableSleepForest.swift"]] + [root / "Scripts/SleepReplay/PortableReplay.swift"]
    source_hashes = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}
    name = "portable_" + str(args.trees) + "_" + str(args.minimum_leaf)
    if args.native_only:
        check = json.loads(args.component_check.read_text())
        assert check["passed"] and check["model"] == name and check["sourceSHA256"] == source_hash
        assert check["sourceFilesSHA256"] == source_hashes
        assert check.get("predictionParityChecked", True), "Component certificate must include reference prediction parity"
        assert check["maximumPredictionDifferenceMinutes"] <= 1e-6
    else:
        assert args.refit_every == reference["audit"]["refitEvery"], "Reference cadence must match for prediction parity"
    with tempfile.TemporaryDirectory(prefix="lw-portable-check-") as folder:
        folder = Path(folder)
        (folder / "input.json").write_text(json.dumps(payload))
        subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-O", "-module-cache-path", str(folder / "cache"),
                        *map(str, sources), "-o", str(folder / "replay")], check=True)
        subprocess.run([str(folder / "replay"), str(folder / "input.json"), str(folder / "output.json")], check=True)
        native = json.loads((folder / "output.json").read_text())
    assert native["indices"] == expected["indices"].tolist()
    positions = [expected["names"].index(name) for name in native["names"]]
    x = np.array([[np.nan if value is None else value for value in row] for row in native["features"]])
    expected_x = expected["X"][:, positions]
    np.testing.assert_allclose(x, expected_x, rtol=0, atol=1e-6, equal_nan=True)
    np.testing.assert_allclose(native["targets"], expected["y"], rtol=0, atol=1e-6)
    by_index = {row["index"]: row for row in reference["events"][name]}
    assert set(by_index) == set(native["indices"])
    reference_predictions = np.array([by_index[i]["prediction"] for i in native["indices"]])
    np.testing.assert_allclose([by_index[i]["actual"] for i in native["indices"]], expected["y"], rtol=0, atol=1e-6)
    if not args.native_only:
        np.testing.assert_allclose(native["predictions"], reference_predictions, rtol=0, atol=1e-6)
    error = np.abs(np.array(native["predictions"]) - expected["y"])
    result = dict(passed=True, model=name, sourceSHA256=source_hash,
                  accuracyGoalAchieved=bool(np.mean(error) <= 2 and np.mean(error <= 30) >= .98),
                  sourceFilesSHA256=source_hashes, refitEvery=args.refit_every,
                  featureRows=len(x), featureCells=int(x.size), forecastCount=len(error),
                  maximumFeatureDifference=float(np.nanmax(np.abs(x - expected_x))),
                  maximumPredictionDifferenceMinutes=None if args.native_only else float(np.max(np.abs(np.array(native["predictions"]) - reference_predictions))),
                  predictionParityChecked=not args.native_only,
                  prefixChecks=native["prefixChecks"], maximumPrefixFeatureDifference=native["maximumPrefixFeatureDifference"],
                  mae=float(np.mean(error)), within30=float(np.mean(error <= 30) * 100),
                  refits=len(native["trainingMilliseconds"]),
                  medianTrainingMilliseconds=float(np.median(native["trainingMilliseconds"])),
                  maximumTrainingMilliseconds=max(native["trainingMilliseconds"]),
                  scope="Native macOS component verification; iOS integration and device timing remain unverified")
    args.output.write_text(json.dumps(result, indent=2))
    if args.forecast_output:
        indices = expected["indices"]
        day = np.array([baseline_rows[int(i)]["context"] == "daytime" for i in indices])
        masks = dict(all=np.ones(len(error), dtype=bool), daytime=day,
                     development=indices < int(len(sleeps) * .6),
                     validation=(indices >= int(len(sleeps) * .6)) & (indices < int(len(sleeps) * .8)),
                     finalPeriod=indices >= int(len(sleeps) * .8))
        def metrics(mask):
            e = error[mask]
            return dict(count=len(e), mae=float(np.mean(e)), median=float(np.median(e)), p90=float(np.quantile(e, .9)),
                        within15=float(np.mean(e <= 15) * 100), within30=float(np.mean(e <= 30) * 100)) if len(e) else dict(count=0)
        model_name = "nativeEveryWake" + str(args.trees) if args.refit_every == 1 else "nativePortable" + str(args.trees)
        forecast_result = dict(audit=dict(sourceSHA256=source_hash, sourceFilesSHA256=source_hashes,
                                         featureCount=len(native["names"]), careExposure="completed", refitEvery=args.refit_every,
                                         lookbackDays=60, nativeEvaluation=True, predictionParityChecked=not args.native_only),
                               models={model_name: {k: metrics(mask) for k, mask in masks.items()}},
                               events={model_name: [dict(index=i, actual=float(a), prediction=float(p))
                                                    for i, a, p in zip(native["indices"], expected["y"], native["predictions"])]})
        args.forecast_output.write_text(json.dumps(forecast_result, indent=2))
    print(json.dumps(result))


if __name__ == "__main__":
    main()
