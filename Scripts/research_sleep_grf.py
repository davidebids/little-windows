#!/usr/bin/env python3
"""Chronological replay using the authors' external GRF C++ implementation.

No upstream source or executable is added to the app target. Native fitting,
honesty and local-linear splitting/prediction run through the upstream core.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import time

import numpy as np
from sklearn.impute import SimpleImputer

from research_sleep_regimes import regimes
from research_sleep_ensemble import combine, metrics


def plans(data, groups, lookback_days=60, refit_every=24):
    """Plan only by past availability; never inspect target values here."""
    output, active = [], {}
    available, wakes = data["available"], data["wakes"]
    for i, wake in enumerate(wakes):
        group = int(groups[i])
        train = np.flatnonzero((np.arange(len(wakes)) < i) & (available <= wake) &
            (wakes >= wake - lookback_days * 86400) & (groups == group))
        previous = active.get(group)
        if len(train) >= 40 and (previous is None or i - previous["index"] >= refit_every):
            previous = dict(index=i, train=train, queries=[])
            active[group] = previous
            output.append(previous)
        if previous is not None:
            previous["queries"].append(i)
    return output


def native_fit(binary, x, y, queries, method, trees=2000, seed=42, honesty=True):
    imputer = SimpleImputer(keep_empty_features=True).fit(x)
    x, queries = imputer.transform(x), imputer.transform(queries)
    with tempfile.TemporaryDirectory(prefix="lw-grf-fit-") as temp:
        folder = Path(temp)
        with (folder / "input.txt").open("w") as handle:
            handle.write(f"{len(y)} {x.shape[1]} {len(queries)} {method} {trees} {seed} {int(honesty)}\n")
            np.savetxt(handle, np.column_stack([x, y]), fmt="%.17g")
            np.savetxt(handle, queries, fmt="%.17g")
        subprocess.run([str(binary), str(folder / "input.txt"), str(folder / "output.json")], check=True)
        return json.loads((folder / "output.json").read_text())


def replay(data, fallback, groups, method, fitter):
    prediction, control = fallback.copy(), fallback.copy()
    diagnostics = dict(refits=0, unavailablePredictions=0, unavailableControlPredictions=0, penaltySelections={})
    for plan in plans(data, groups):
        train, query = plan["train"], np.array(plan["queries"], dtype=int)
        result = fitter(data["X"][train], data["y"][train], data["X"][query], method)
        point = np.array([np.nan if p is None else p for p in result["predictions"]], dtype=float)
        assert len(point) == len(query)
        valid = np.isfinite(point)
        prediction[query[valid]] = np.clip(point[valid], 1, 480)
        diagnostics["unavailablePredictions"] += int(np.sum(~valid))
        if result.get("basePredictions"):
            raw = np.array([np.nan if p is None else p for p in result["basePredictions"]], dtype=float)
            assert len(raw) == len(query)
            valid = np.isfinite(raw)
            control[query[valid]] = np.clip(raw[valid], 1, 480)
            diagnostics["unavailableControlPredictions"] += int(np.sum(~valid))
        key = str(result["lambda"])
        diagnostics["penaltySelections"][key] = diagnostics["penaltySelections"].get(key, 0) + 1
        diagnostics["refits"] += 1
    return prediction, control, diagnostics


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--nonhonest", action="store_true", help="Ablate the supported honesty option; future labels remain unavailable")
    for name in ["source", "features", "baseline", "members", "incumbent", "build", "output"]:
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root) or args.build.resolve().is_relative_to(root):
        parser.error("Keep external research dependencies and history results outside the repository")
    build = json.loads((args.build / "build-check.json").read_text())
    binary = args.build / "replay"
    assert build["passed"] and build["authorLocalLinearTestsPassed"]
    assert hashlib.sha256(binary.read_bytes()).hexdigest() == build["binarySHA256"]
    assert hashlib.sha256((root / "Scripts/SleepReplay/GRFReplay.cpp").read_bytes()).hexdigest() == build["bridgeSHA256"]
    base, members, incumbent = [json.loads(p.read_text()) for p in [args.baseline, args.members, args.incumbent]]
    source_hash = hashlib.sha256(args.source.read_bytes()).hexdigest()
    assert all(r["audit"]["sourceSHA256"] == source_hash for r in [base, members, incumbent])
    data = dict(np.load(args.features, allow_pickle=False))
    indices = data["indices"].astype(int).tolist()
    baseline = {r["index"]: r for r in base["events"]}
    assert set(indices) == set(baseline) == {r["index"] for r in incumbent["events"]}
    np.testing.assert_allclose([baseline[i]["actual"] for i in indices], data["available"], rtol=0, atol=1e-6)
    np.testing.assert_allclose([baseline[i]["wakeMinutes"] for i in indices], data["y"], rtol=0, atol=1e-6)
    fallback = (np.array([baseline[i]["prediction"] for i in indices]) - data["wakes"]) / 60
    original = []
    for events in members["events"].values():
        rows = {r["index"]: r for r in events}
        assert set(rows) == set(indices)
        np.testing.assert_allclose([rows[i]["actual"] for i in indices], data["y"], rtol=0, atol=1e-6)
        original.append(np.array([rows[i]["prediction"] for i in indices]))
    result = dict(audit=dict(sourceSHA256=source_hash, careExposure="completed", featureCount=len(data["names"]),
        featureCacheSHA256=hashlib.sha256(args.features.read_bytes()).hexdigest(), upstreamBuild=build,
        trees=2000, seed=42, threads=1, sampleFraction=.5, honesty=not args.nonhonest, honestyFraction=.5,
        honestyPruneLeaves=True, minNodeSize=5, alpha=.05, ciGroupSize=2, legacySeed=False,
        lookbackDays=60, refitEvery=24, linearVariables="all", splitLambda=.1,
        localPenaltyPath=[0, .001, .01, .05, .1, .3, .5, .7, 1, 10], penaltySelection="Past fit-snapshot OOB mean squared error",
        imputation="Training-only feature means; no future-query preprocessing fit",
        sourceURLs=["https://grf-labs.github.io/grf/reference/ll_regression_forest.html", "https://github.com/grf-labs/grf"],
        baselineResultSHA256=hashlib.sha256(args.baseline.read_bytes()).hexdigest(),
        memberResultSHA256=hashlib.sha256(args.members.read_bytes()).hexdigest(),
        incumbentResultSHA256=hashlib.sha256(args.incumbent.read_bytes()).hexdigest()), models={}, events={})
    mask = np.ones(len(indices), dtype=bool)
    def save(name, prediction, **details):
        result["models"][name] = dict(all=metrics(data["y"], prediction, mask), **details)
        result["events"][name] = [dict(index=i, actual=float(y), prediction=float(p)) for i, y, p in zip(indices, data["y"], prediction)]
        args.output.write_text(json.dumps(result, indent=2) + "\n")
        print(name, json.dumps(result["models"][name]), flush=True)
    def fitter(x, y, queries, method):
        return native_fit(binary, x, y, queries, method, honesty=not args.nonhonest)
    global_experts = []
    for method in ["median", "ll_standard", "ll_residual"]:
        started = time.monotonic()
        prediction, control, diagnostics = replay(data, fallback, np.zeros(len(indices), dtype=int), method, fitter)
        save("grf_global_" + method, prediction, seconds=time.monotonic() - started, **diagnostics)
        if method == "ll_standard": save("grf_global_mean_control", control, **diagnostics)
        global_experts.append(prediction)
    context_experts = []
    for policy in ["previousKind", "wakePhase", "cycleStage"]:
        started = time.monotonic()
        prediction, _, diagnostics = replay(data, fallback, regimes(data, policy), "median", fitter)
        save("grf_median_" + policy, prediction, seconds=time.monotonic() - started, **diagnostics)
        context_experts.append(prediction)
    variants = [("localCalibratedSoft", "soft", True, True), ("localCalibratedBest", "best", True, True),
        ("localRawSoft", "soft", False, True), ("globalCalibratedSoft", "soft", True, False),
        ("calibratedMedian", "median", True, True)]
    for family, experts in [("grfGlobal", global_experts), ("grfContext", context_experts), ("grfAugmented", original + global_experts)]:
        for name, policy, calibrate, local in variants:
            prediction = combine(data, np.column_stack([fallback] + experts), policy=policy, calibrate=calibrate, local=local)
            save(family + "_" + name, prediction)


if __name__ == "__main__":
    main()
