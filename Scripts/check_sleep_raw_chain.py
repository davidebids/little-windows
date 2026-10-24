#!/usr/bin/env python3
"""Verify the native combination directly from external primitive history.

Only aggregate checks survive. Raw rows, features, and forecasts stay in a
temporary directory; no history is imported into the app or bundled in source.
"""
import argparse
import csv
import datetime as dt
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

import numpy as np

from research_sleep_predictions import feature_rows, load_history


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["source", "baseline", "members", "reference", "output"]:
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--birth-date", required=True)
    parser.add_argument("--time-zone", required=True)
    parser.add_argument("--app-fallbacks", action="store_true", help="Generate sparse-history points from the actual uncombined app engine")
    parser.add_argument("--session", action="store_true", help="Also verify the production value session using unresolved queries and incremental outcomes")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root):
        parser.error("Keep history-derived reports outside the repository")
    source_hash = hashlib.sha256(args.source.read_bytes()).hexdigest()
    base, members, reference = [json.loads(p.read_text()) for p in [args.baseline, args.members, args.reference]]
    assert all(r["audit"]["sourceSHA256"] == source_hash for r in [base, members, reference])
    sleeps, care, birth, zone = load_history(args.source, args.birth_date, args.time_zone)
    expected = feature_rows(sleeps, care, birth, zone)
    indices = expected["indices"].astype(int).tolist()
    baseline = {r["index"]: r for r in base["events"]}
    assert set(indices) == set(baseline)
    np.testing.assert_allclose([baseline[i]["actual"] for i in indices], expected["available"], rtol=0, atol=1e-6)
    np.testing.assert_allclose([baseline[i]["wakeMinutes"] for i in indices], expected["y"], rtol=0, atol=1e-6)
    dense = np.array([np.sum((expected["wakes"][:i] >= wake - 60 * 86400) &
        (expected["available"][:i] <= wake)) >= 40 for i, wake in enumerate(expected["wakes"])])
    payload = dict(birth=birth, zone=str(zone), boundedHistory=False,
        useSession=args.session,
        sleeps=[dict(start=float(s), end=float(e), night=bool(n)) for s, e, n in sleeps],
        care=[dict(start=float(s), end=float(e)) for s, e, kind in care if kind == "Feed"],
        fallback=[dict(index=indices[i], minutes=(baseline[indices[i]]["prediction"] - float(expected["wakes"][i])) / 60)
            for i in np.flatnonzero(~dense)])
    if args.app_fallbacks:
        payload["fallback"] = []
        def epoch(value):
            return dt.datetime.strptime(value, "%Y-%m-%d %H:%M").replace(tzinfo=zone).timestamp()
        with args.source.open(encoding="utf-8-sig") as handle:
            payload["care"] = [dict(start=epoch(r["Start"]), end=epoch(r["End"] or r["Start"]),
                nursing=r["Start Location"] == "Breast") for r in csv.DictReader(handle) if r["Type"] == "Feed"]
    variants = ["localCalibratedSoft", "localCalibratedBest", "localRawSoft", "globalCalibratedSoft", "calibratedMedian"]
    assert list(members["events"]) == ["specialist_" + k for k in ["previousKind", "wakePhase", "cycleStage"]]
    experts = [(np.array([baseline[i]["prediction"] for i in indices]) - expected["wakes"]) / 60]
    for events in members["events"].values():
        by_index = {r["index"]: r for r in events}
        assert set(by_index) == set(indices)
        np.testing.assert_allclose([by_index[i]["actual"] for i in indices], expected["y"], rtol=0, atol=1e-6)
        experts.append(np.array([by_index[i]["prediction"] for i in indices]))
    experts = np.column_stack(experts)
    sources = [root / "LittleWindows/Services" / n for n in ["PortableSleepFeatures.swift", "PortableSleepForest.swift",
        "ReferenceSleepForest.swift", "PortableSleepCalibration.swift", "PortableSleepSpecialists.swift", "PortableSleepBaseline.swift", "PersonalizedSleepSession.swift"]]
    sources += [root / "Scripts/SleepReplay" / n for n in ["ExpertCalibrationReplay.swift", "RawSleepCombinationReplay.swift"]]
    if args.app_fallbacks:
        sources += [root / "Scripts/SleepReplay" / n for n in ["AppSleepFallbackReplay.swift", "Support.swift"]]
        sources += [root / "LittleWindows/Services" / n for n in
            ["PersonalizedSleepLearning.swift", "PortableSleepPlanning.swift", "SleepLearningCoordinator.swift", "SleepPredictionEngine.swift", "PredictionTuningService.swift"]]
    source_hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    checks, bounded = {}, []
    with tempfile.TemporaryDirectory(prefix="lw-raw-chain-") as folder:
        folder = Path(folder)
        compile_sources = sources
        flags = ["-D", "RAW_SLEEP_COMBINATION_REPLAY"]
        if args.app_fallbacks:
            engine = (root / "LittleWindows/Services/SleepPredictionEngine.swift").read_text()
            compiled_engine = engine[:engine.index("enum ActiveSleepPlanService {")] + engine[engine.index("enum SleepPredictionEngine {"):]
            tuning = (root / "LittleWindows/Services/PredictionTuningService.swift").read_text()
            bias = tuning[tuning.index("    static func conservativeBiasCorrection("):tuning.index("    private static func latestOpenRecord(")]
            (folder / "Engine.swift").write_text(compiled_engine)
            (folder / "Tuning.swift").write_text("import Foundation\nenum PredictionTuningService {\n" + bias + "}\n")
            compile_sources = [p for p in sources if p.name not in ["SleepPredictionEngine.swift", "PredictionTuningService.swift"]]
            compile_sources += [folder / "Engine.swift", folder / "Tuning.swift"]
            flags += ["-D", "APP_SLEEP_FALLBACKS"]
        subprocess.run(["xcrun", "swiftc", "-O", "-parse-as-library", *flags,
            "-module-cache-path", str(folder / "cache"), *map(str, compile_sources), "-o", str(folder / "replay")], check=True)

        def run(values):
            (folder / "input.json").write_text(json.dumps(values))
            subprocess.run([str(folder / "replay"), str(folder / "input.json"), str(folder / "output.json")], check=True)
            return json.loads((folder / "output.json").read_text())

        full = run(payload)
        assert full["externalSparseFallbacks"] == (not args.app_fallbacks)
        assert full["sparseFallbackCount"] == int(np.sum(~dense))
        assert full["indices"] == indices
        positions = [expected["names"].index(n) for n in full["names"]]
        x = np.array([[np.nan if v is None else v for v in r] for r in full["features"]])
        np.testing.assert_allclose(x, expected["X"][:, positions], rtol=0, atol=1e-6, equal_nan=True)
        np.testing.assert_allclose(full["wakes"], expected["wakes"], rtol=0, atol=1e-6)
        np.testing.assert_allclose(full["targets"], expected["y"], rtol=0, atol=1e-6)
        np.testing.assert_allclose(full["chain"]["experts"], experts, rtol=0, atol=1e-6)
        predictions = np.array(full["chain"]["predictions"])
        if args.session:
            np.testing.assert_allclose(full["session"]["predictions"], predictions[:, 1], rtol=0, atol=1e-6)
            assert full["session"]["baselineTrainingCount"] == full["chain"]["baselineTrainingCount"]
            assert full["session"]["specialistTrainingCounts"] == full["chain"]["specialistTrainingCounts"]
        for k, name in enumerate(variants):
            expected_rows = {r["index"]: r for r in reference["events"][name]}
            assert set(expected_rows) == set(indices)
            np.testing.assert_allclose([expected_rows[i]["actual"] for i in indices], expected["y"], rtol=0, atol=1e-6)
            difference = np.abs(predictions[:, k] - np.array([expected_rows[i]["prediction"] for i in indices]))
            assert np.max(difference) <= 1e-6
            errors = np.abs(predictions[:, k] - expected["y"])
            checks[name] = dict(forecasts=len(indices), maximumDifference=float(np.max(difference)),
                mae=float(np.mean(errors)), within30=float(np.mean(errors <= 30) * 100))
            print(name, checks[name], flush=True)
        for count in [40, 400, 800, 1400, len(indices)]:
            if count > len(indices):
                continue
            # The next timer start and its later sleep are physically removed.
            # Native features and the queried forecast must still match.
            current = run(dict(payload, throughSleepIndex=indices[count - 1], boundedHistory=True))
            assert current["indices"] == indices[:count]
            assert current["targets"][-1] is None
            np.testing.assert_allclose(np.asarray(current["features"][-1], dtype=float),
                np.asarray(full["features"][count - 1], dtype=float), rtol=0, atol=1e-6, equal_nan=True)
            np.testing.assert_allclose(current["chain"]["predictions"][-1], predictions[count - 1], rtol=0, atol=1e-6)
            if args.session:
                np.testing.assert_allclose(current["session"]["predictions"][-1], predictions[count - 1, 1], rtol=0, atol=1e-6)
            recent = expected["wakes"][:count] >= expected["wakes"][count - 1] - 60 * 86400
            np.testing.assert_allclose(np.array(current["chain"]["experts"])[recent], experts[:count][recent], rtol=0, atol=1e-6)
            chain = current["chain"]
            bounded.append(dict(prefix=count, requestedRawRows=int(np.sum(recent)),
                baselineFits=chain["baselineTrainingCount"], specialistFits=sum(chain["specialistTrainingCounts"]),
                preparationSeconds=current["preparationSeconds"], sparseFallbackCount=current["sparseFallbackCount"],
                currentTargetAbsent=True))
            print("bounded raw", bounded[-1], flush=True)
    assert source_hashes == {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    result = dict(passed=True, sourceSHA256=source_hash,
        baselineResultSHA256=hashlib.sha256(args.baseline.read_bytes()).hexdigest(),
        memberResultSHA256=hashlib.sha256(args.members.read_bytes()).hexdigest(),
        referenceResultSHA256=hashlib.sha256(args.reference.read_bytes()).hexdigest(),
        sourceFilesSHA256=source_hashes, caseCount=len(indices), featureCount=x.shape[1],
        maximumFeatureDifference=float(np.nanmax(np.abs(x - expected["X"][:, positions]))),
        sparseFallbackCount=full["sparseFallbackCount"], externalSparseFallbackInputs=not args.app_fallbacks,
        externalFeatureInputs=False,
        externalLearnedBaselineInputs=False, variants=checks, boundedHistoryChecks=bounded,
        productionValueSessionChecked=args.session,
        timingIncludesSessionVerification=args.session,
        fullPreparationSeconds=full["preparationSeconds"],
        scope=("Native raw-history frontend, actual uncombined app fallbacks and learned baseline/specialist/calibration chain. macOS timing and storage-free app adapters; iOS production integration and device latency remain unverified."
            if args.app_fallbacks else "Native raw-history frontend and learned baseline/specialist/calibration chain; external sparse app fallbacks remain. macOS timing, not iOS production integration or device latency."))
    args.output.write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
