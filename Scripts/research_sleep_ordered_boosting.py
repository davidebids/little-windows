#!/usr/bin/env python3
"""Causal ordered-boosting research; no trained model is bundled in the app."""
import argparse
import hashlib
import json
from pathlib import Path
import time
import numpy as np
from research_sleep_ensemble import combine, metrics


def replay(data, fallback, factory, residual=False, refit_every=24):
    """Fit on resolved earlier labels and retain the original fallback forecasts."""
    y, wakes, available = [data[k] for k in ["y", "wakes", "available"]]
    target = y - fallback if residual else y
    output = fallback.copy()
    model, last_fit, fits = None, -refit_every, 0
    for i, now in enumerate(wakes):
        train = np.flatnonzero((np.arange(len(y)) < i) & (available <= now)
                              & (wakes >= now - 60 * 86400))
        if len(train) < 40:
            continue
        if model is None or i - last_fit >= refit_every:
            model = factory()
            model.fit(data["X"][train], target[train],
                      sample_weight=np.exp2(-(now - wakes[train]) / (14 * 86400)))
            last_fit, fits = i, fits + 1
        point = float(model.predict(data["X"][i:i + 1])[0])
        if not np.isfinite(point):
            raise ValueError("Nonfinite forecast; do not silently remove a scored case")
        output[i] = np.clip(point + (fallback[i] if residual else 0), 1, 480)
    return output, fits


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["source", "features", "baseline", "output"]:
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    if args.output.resolve().is_relative_to(Path(__file__).resolve().parents[1]):
        parser.error("Keep history-derived results outside the repository")
    import catboost
    data = dict(np.load(args.features, allow_pickle=False))
    base = json.loads(args.baseline.read_text())
    source_hash = hashlib.sha256(args.source.read_bytes()).hexdigest()
    assert source_hash == base["audit"]["sourceSHA256"]
    indices = data["indices"].astype(int).tolist()
    rows = {r["index"]: r for r in base["events"]}
    assert set(indices) == set(rows)
    np.testing.assert_allclose([rows[i]["actual"] for i in indices], data["available"], rtol=0, atol=1e-6)
    np.testing.assert_allclose([rows[i]["wakeMinutes"] for i in indices], data["y"], rtol=0, atol=1e-6)
    fallback = (np.array([rows[i]["prediction"] for i in indices]) - data["wakes"]) / 60
    result = dict(audit=dict(sourceSHA256=source_hash, careExposure="completed", library="catboost",
        version=catboost.__version__, featureCacheSHA256=hashlib.sha256(args.features.read_bytes()).hexdigest(),
        baselineResultSHA256=hashlib.sha256(args.baseline.read_bytes()).hexdigest(),
        scriptSHA256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        lookbackDays=60, halfLifeDays=14, minimumLabels=40, refitEvery=24,
        rule="Only resolved earlier outcomes; native missing values; chronological training; fixed iterations without future evaluation sets",
        sourceURLs=["https://catboost.ai/docs/en/references/training-parameters/common",
                    "https://catboost.ai/docs/en/concepts/loss-functions-regression"]), models={}, events={})
    def save(name, prediction, **details):
        result["models"][name] = dict(all=metrics(data["y"], prediction, np.ones(len(indices), dtype=bool)), **details)
        result["events"][name] = [dict(index=i, actual=float(y), prediction=float(p))
            for i, y, p in zip(indices, data["y"], prediction)]
        args.output.write_text(json.dumps(result, indent=2) + "\n")
        print(name, json.dumps(result["models"][name]), flush=True)
    experts = [fallback]
    configs = [(scheme, loss, residual, depth)
        for scheme, loss, residual in [("Ordered", "MAE", False), ("Plain", "MAE", False),
                                       ("Ordered", "RMSE", False), ("Ordered", "MAE", True)]
        for depth in [4, 6]]
    for scheme, loss, residual, depth in configs:
        params = dict(iterations=400, learning_rate=.05, depth=depth, l2_leaf_reg=10,
            loss_function=loss, boosting_type=scheme, has_time=True, random_seed=42,
            thread_count=1, allow_writing_files=False, verbose=False)
        started = time.monotonic()
        prediction, fits = replay(data, fallback, lambda: catboost.CatBoostRegressor(**params), residual)
        save(f"{scheme}_{loss}_{'residual' if residual else 'direct'}_d{depth}", prediction,
             parameters=params, refits=fits, seconds=time.monotonic() - started)
        experts.append(prediction)
    for name, policy, calibrate, local in [("localCalibratedSoft", "soft", True, True),
        ("localCalibratedBest", "best", True, True), ("localRawSoft", "soft", False, True),
        ("globalCalibratedSoft", "soft", True, False), ("calibratedMedian", "median", True, True)]:
        save("orderedPool_" + name, combine(data, np.column_stack(experts), policy, calibrate, local))


if __name__ == "__main__":
    main()
