#!/usr/bin/env python3
"""Verify native calibration against previously issued external expert forecasts."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

import numpy as np


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["features", "baseline", "members", "reference", "source", "output"]:
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--fit-specialists", action="store_true", help="Fit native experts before native calibration, and compare delayed outcome resolution")
    parser.add_argument("--reference-forest", action="store_true", help="Use the library-compatible native forest for the specialist fits")
    parser.add_argument("--fit-baseline", action="store_true", help="Rebuild the v6 learned baseline; external points are used only for sparse-history fallbacks")
    args = parser.parse_args()
    if args.reference_forest and not args.fit_specialists:
        parser.error("Reference forest requires fitting the specialists")
    if args.fit_baseline and not args.fit_specialists:
        parser.error("Baseline reconstruction requires fitting the specialists")
    root = Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root):
        parser.error("Keep history-derived reports outside the repository")
    base, members, reference = [json.loads(p.read_text()) for p in [args.baseline, args.members, args.reference]]
    source_hash = hashlib.sha256(args.source.read_bytes()).hexdigest()
    assert all(r["audit"]["sourceSHA256"] == source_hash for r in [base, members, reference])
    data = dict(np.load(args.features, allow_pickle=False))
    indices = list(data["indices"].astype(int))
    baseline = {r["index"]: r for r in base["events"]}
    assert set(indices) == set(baseline)
    np.testing.assert_allclose([baseline[i]["actual"] for i in indices], data["available"], rtol=0, atol=1e-6)
    np.testing.assert_allclose([baseline[i]["wakeMinutes"] for i in indices], data["y"], rtol=0, atol=1e-6)
    np.testing.assert_allclose(data["wakes"] + data["y"] * 60, data["available"], rtol=0, atol=1e-6)
    raw = [(np.array([baseline[i]["prediction"] for i in indices]) - data["wakes"]) / 60]
    for events in members["events"].values():
        by_index = {r["index"]: r for r in events}
        assert set(by_index) == set(indices)
        np.testing.assert_allclose([by_index[i]["actual"] for i in indices], data["y"], rtol=0, atol=1e-6)
        raw.append(np.array([by_index[i]["prediction"] for i in indices]))
    raw = np.column_stack(raw)
    names = list(data["names"])
    x = data["X"]
    clocks = np.mod(np.arctan2(x[:, names.index("clockSin1")], x[:, names.index("clockCos1")]), 2 * np.pi) * 1440 / (2 * np.pi)
    rows = [dict(context=dict(wake=float(w), clockMinute=float(clock), sleepMinutes=float(duration)),
                 availableAt=float(a), actual=float(y), raw=list(map(float, predictions)))
        for w, clock, duration, a, y, predictions in zip(data["wakes"], clocks, x[:, names.index("lastDuration")], data["available"], data["y"], raw)]
    sources = [root / "LittleWindows/Services/PortableSleepCalibration.swift", root / "Scripts/SleepReplay/CalibrationReplay.swift"]
    if args.fit_specialists:
        prefix = "specialist_" if args.reference_forest else "nativeSpecialist_"
        assert list(members["events"]) == [prefix + key for key in ["previousKind", "wakePhase", "cycleStage"]]
        for i, row in enumerate(rows):
            row.update(values=[float(v) if np.isfinite(v) else None for v in x[i]],
                lastNight=bool(x[i, names.index("lastNight")] > .5), napsToday=float(x[i, names.index("napsToday")]), baseline=float(raw[i, 0]))
        sources = [root / "LittleWindows/Services" / name for name in
            ["PortableSleepForest.swift", "ReferenceSleepForest.swift", "PortableSleepCalibration.swift", "PortableSleepSpecialists.swift", "PortableSleepBaseline.swift"]]
        sources += [root / "Scripts/SleepReplay/ExpertCalibrationReplay.swift"]
    variants = [("localCalibratedSoft", "soft", True, True), ("localCalibratedBest", "best", True, True),
                ("localRawSoft", "soft", False, True), ("globalCalibratedSoft", "soft", True, False),
                ("calibratedMedian", "median", True, True)]
    checks = {}
    with tempfile.TemporaryDirectory(prefix="lw-native-calibration-") as folder:
        folder = Path(folder)
        subprocess.run(["xcrun", "swiftc", "-O", "-parse-as-library", "-module-cache-path", str(folder / "cache"),
            *map(str, sources), "-o", str(folder / "replay")], check=True)
        def encoded(payload):
            (folder / "input.json").write_text(json.dumps(payload))
            subprocess.run([str(folder / "replay"), str(folder / "input.json"), str(folder / "output.json")], check=True)
            return json.loads((folder / "output.json").read_text())
        def native(payload):
            return np.array(encoded(payload)["predictions"])
        if args.fit_specialists:
            payload = dict(rows=rows, revealOnlyWhenAvailable=False, referenceForest=args.reference_forest,
                fitBaseline=args.fit_baseline)
            full = encoded(payload)
            forecasts = np.array(full["predictions"])
            expert_error = float(np.max(np.abs(np.array(full["experts"]) - raw)))
            assert expert_error <= 1e-6
            expected_fit_counts = [members["models"][name]["refits"] for name in members["events"]]
            assert full["specialistFitCounts"] == expected_fit_counts
            assert full["specialistTrainingCounts"] == expected_fit_counts
            dense = np.array([np.sum((data["wakes"][:i] >= wake - 60 * 86400) &
                (data["available"][:i] <= wake)) >= 40 for i, wake in enumerate(data["wakes"])])
            if args.fit_baseline:
                assert full["baselineTrainingCount"] == int(np.sum(dense))
                # Learned points must not secretly depend on the supplied v6
                # vector. Withhold it wherever a fit can produce the point.
                sparse_only = json.loads(json.dumps(payload))
                for i in np.flatnonzero(dense):
                    sparse_only["rows"][i]["baseline"] = None
                np.testing.assert_array_equal(native(sparse_only), forecasts)
            for k, (name, _, _, _) in enumerate(variants):
                expected = {r["index"]: r for r in reference["events"][name]}
                assert set(expected) == set(indices)
                errors = np.abs(forecasts[:, k] - np.array([expected[i]["prediction"] for i in indices]))
                absolute = np.abs(forecasts[:, k] - data["y"])
                checks[name] = dict(forecasts=len(rows), mismatches=int(np.sum(errors > 1e-6)), maximumDifference=float(np.max(errors)),
                    mae=float(np.mean(absolute)), within30=float(np.mean(absolute <= 30) * 100))
                print(name, checks[name], flush=True)
            streamed = encoded(dict(payload, revealOnlyWhenAvailable=True))
            np.testing.assert_allclose(streamed["experts"], full["experts"], rtol=0, atol=1e-6)
            np.testing.assert_allclose(streamed["predictions"], forecasts, rtol=0, atol=1e-6)
            assert streamed["specialistFitCounts"] == full["specialistFitCounts"]
            unlabelled = json.loads(json.dumps(payload))
            unlabelled["rows"][-1]["actual"] = None
            unlabelled["rows"][-1]["availableAt"] = None
            np.testing.assert_array_equal(native(unlabelled), forecasts)
            for count in [40, len(rows) // 2, len(rows) - 1]:
                np.testing.assert_allclose(native(dict(payload, rows=rows[:count])), forecasts[:count], rtol=0, atol=1e-6)
            changed = json.loads(json.dumps(payload))
            changed["rows"][0]["availableAt"] = rows[-1]["context"]["wake"] + 86400
            before = encoded(changed)
            changed["rows"][0]["actual"] = 1e8
            after = encoded(changed)
            np.testing.assert_array_equal(after["experts"], before["experts"])
            np.testing.assert_array_equal(after["predictions"], before["predictions"])
            bounded_checks = []
            for count in [40, 400, 800, 1400, len(rows)]:
                if count > len(rows):
                    continue
                cutoff = rows[count - 1]["context"]["wake"] - 60 * 86400
                bounded = encoded(dict(payload, rows=rows[:count], retainRawFromWake=cutoff))
                tail = np.array([r["context"]["wake"] >= cutoff for r in rows[:count]])
                np.testing.assert_allclose(np.array(bounded["experts"])[tail], np.array(full["experts"])[:count][tail], rtol=0, atol=1e-6)
                np.testing.assert_allclose(bounded["predictions"][-1], forecasts[count - 1], rtol=0, atol=1e-6)
                bounded_checks.append(dict(prefix=count, requestedRawRows=int(np.sum(tail)),
                    actualFits=sum(bounded["specialistTrainingCounts"]), logicalFits=sum(bounded["specialistFitCounts"]),
                    baselineFits=bounded["baselineTrainingCount"]))
                print("bounded", bounded_checks[-1], flush=True)
            result = dict(passed=all(v["mismatches"] == 0 for v in checks.values()), sourceSHA256=source_hash,
                baselineResultSHA256=hashlib.sha256(args.baseline.read_bytes()).hexdigest(),
                memberResultSHA256=hashlib.sha256(args.members.read_bytes()).hexdigest(),
                referenceResultSHA256=hashlib.sha256(args.reference.read_bytes()).hexdigest(),
                sourceFilesSHA256={p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
                caseCount=len(rows), expertCount=raw.shape[1], variants=checks, maximumExpertDifference=expert_error,
                specialistFitCounts=full["specialistFitCounts"], delayedOutcomeParity=True,
                referenceForest=args.reference_forest,
                nativeBaseline=args.fit_baseline,
                baselineTrainingCount=full["baselineTrainingCount"],
                sparseFallbackCount=int(np.sum(~dense)) if args.fit_baseline else None,
                learnedBaselineInputWithheld=args.fit_baseline,
                prefixChecks=3, unavailableOutcomeInvariant=True,
                boundedHistoryChecks=bounded_checks,
                unlabelledCurrentQueryParity=True,
                scope=("Native learned baseline, specialists and calibration with external causal features and sparse-history app fallbacks; production integration pending"
                    if args.fit_baseline else "Native specialists and calibration with external v6 baseline forecasts and features; production integration pending"))
            args.output.write_text(json.dumps(result, indent=2))
            assert result["passed"]
            return
        for name, policy, calibrate, local in variants:
            payload = dict(rows=rows, policy=policy, calibrate=calibrate, local=local)
            forecasts = native(payload)
            expected = {r["index"]: r for r in reference["events"][name]}
            assert set(expected) == set(indices)
            errors = np.abs(forecasts - np.array([expected[i]["prediction"] for i in indices]))
            mismatches = np.flatnonzero(errors > 1e-6)
            checks[name] = dict(forecasts=len(forecasts), mismatches=len(mismatches), maximumDifference=float(np.max(errors)))
            print(name, checks[name], "examples", [(indices[i], float(errors[i])) for i in mismatches[:5]], flush=True)
            if len(mismatches):
                continue
            for count in [40, len(rows) // 2, len(rows) - 1]:
                np.testing.assert_allclose(native(dict(payload, rows=rows[:count])), forecasts[:count], rtol=0, atol=1e-6)
            changed = json.loads(json.dumps(payload))
            changed["rows"][0]["availableAt"] = rows[-1]["context"]["wake"] + 86400
            before = native(changed)
            changed["rows"][0]["actual"] = 1e8
            np.testing.assert_array_equal(native(changed), before)
        result = dict(passed=all(v["mismatches"] == 0 for v in checks.values()), sourceSHA256=source_hash,
            sourceFilesSHA256={p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
            caseCount=len(rows), expertCount=raw.shape[1], variants=checks,
            prefixChecksPerPassingVariant=3, unavailableOutcomeChecksPerPassingVariant=1,
            scope="Native macOS calibration with externally supplied expert forecasts; app integration not yet validated")
        args.output.write_text(json.dumps(result, indent=2))
    assert result["passed"], "Native calibration must match every reference forecast"


if __name__ == "__main__":
    main()
