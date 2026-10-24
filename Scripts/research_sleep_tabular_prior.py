#!/usr/bin/env python3
"""Local TabPFN-v2 sleep replay, issuing each query separately at its wake."""
import argparse
import hashlib
import json
from pathlib import Path
import time
import numpy as np
from research_sleep_ensemble import combine, metrics
from research_sleep_grf import plans


def replay(data, fallback, factory, progress=None, *, lookback_days=60):
    if not np.isfinite(lookback_days) or lookback_days <= 0:
        raise ValueError("Lookback must be finite and positive")
    outputs = {name: fallback.copy() for name in ["mean", "median", "mode"]}
    schedule = plans(data, np.zeros(len(data["y"]), dtype=int), lookback_days=lookback_days)
    for number, plan in enumerate(schedule):
        model = factory()
        train = plan["train"]
        model.fit(data["X"][train], data["y"][train])
        for i in plan["queries"]:
            # Never supply a later query as part of this issued prediction.
            points = model.predict(data["X"][[i]], output_type="main")
            for name in outputs:
                point = float(np.asarray(points[name])[0])
                if not np.isfinite(point):
                    raise ValueError("Nonfinite prediction; retain the cohort and fail the experiment")
                outputs[name][i] = np.clip(point, 1, 480)
        if progress:
            progress(number + 1, len(schedule), plan["queries"][-1] + 1)
        del model
    return outputs, len(schedule)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["source", "features", "baseline", "bootstrap", "output"]:
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--lookback-days", type=int, default=60)
    args = parser.parse_args()
    if args.lookback_days <= 0:
        parser.error("Lookback must be positive")
    if args.output.resolve().is_relative_to(Path(__file__).resolve().parents[1]):
        parser.error("Keep private history and learned results outside the repository")
    import torch
    import tabpfn
    from tabpfn import TabPFNRegressor
    from tabpfn.constants import ModelVersion
    torch.set_num_threads(2)
    bootstrap = json.loads(args.bootstrap.read_text())
    assert bootstrap["passed"] and bootstrap["device"] == "cpu"
    for path, digest in bootstrap["weights"].items():
        assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest
    data = dict(np.load(args.features, allow_pickle=False))
    base = json.loads(args.baseline.read_text())
    source_hash = hashlib.sha256(args.source.read_bytes()).hexdigest()
    assert base["audit"]["sourceSHA256"] == source_hash
    indices = data["indices"].astype(int).tolist()
    rows = {r["index"]: r for r in base["events"]}
    assert set(indices) == set(rows)
    np.testing.assert_allclose([rows[i]["actual"] for i in indices], data["available"], rtol=0, atol=1e-6)
    np.testing.assert_allclose([rows[i]["wakeMinutes"] for i in indices], data["y"], rtol=0, atol=1e-6)
    fallback = (np.array([rows[i]["prediction"] for i in indices]) - data["wakes"]) / 60
    result = dict(audit=dict(sourceSHA256=source_hash, careExposure="completed",
        library="tabpfn", version=tabpfn.__version__, torchVersion=torch.__version__, modelVersion="v2",
        featureCount=len(data["names"]),
        featureCacheSHA256=hashlib.sha256(args.features.read_bytes()).hexdigest(),
        baselineResultSHA256=hashlib.sha256(args.baseline.read_bytes()).hexdigest(),
        scriptSHA256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        weights=bootstrap["weights"], device="cpu", torchThreads=2, nEstimators=8,
        autoScaleNEstimators=False, fitMode="fit_with_cache", randomState=42,
        lookbackDays=args.lookback_days, refitEvery=24, minimumLabels=40,
        rule="Only earlier resolved labels; every forecast query issued separately; no hosted inference",
        sourceURLs=["https://www.nature.com/articles/s41586-024-08328-6",
                    "https://github.com/PriorLabs/TabPFN"]), models={}, events={})
    def save(name, prediction, **details):
        result["models"][name] = dict(all=metrics(data["y"], prediction, np.ones(len(indices), dtype=bool)), **details)
        result["events"][name] = [dict(index=i, actual=float(y), prediction=float(p))
            for i, y, p in zip(indices, data["y"], prediction)]
        args.output.write_text(json.dumps(result, indent=2) + "\n")
        print(name, json.dumps(result["models"][name]), flush=True)
    def factory():
        return TabPFNRegressor.create_default_for_version(ModelVersion.V2, device="cpu", n_estimators=8,
            auto_scale_n_estimators=False, fit_mode="fit_with_cache", random_state=42)
    started = time.monotonic()
    def progress(done, total, issued):
        print(json.dumps(dict(completedFits=done, totalFits=total, issuedQueries=issued,
                              seconds=time.monotonic() - started)), flush=True)
    forecasts, fits = replay(data, fallback, factory, progress, lookback_days=args.lookback_days)
    for name, prediction in forecasts.items():
        save("tabularPrior_" + name, prediction, refits=fits, seconds=time.monotonic() - started)
    experts = np.column_stack([fallback, *forecasts.values()])
    for name, policy, calibrate, local in [("localCalibratedSoft", "soft", True, True),
        ("localCalibratedBest", "best", True, True), ("localRawSoft", "soft", False, True),
        ("globalCalibratedSoft", "soft", True, False), ("calibratedMedian", "median", True, True)]:
        save("tabularPriorPool_" + name, combine(data, experts, policy, calibrate, local))


if __name__ == "__main__":
    main()
