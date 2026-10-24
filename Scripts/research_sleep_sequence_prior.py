#!/usr/bin/env python3
"""Local event-indexed gap forecasting with a pretrained sequence model."""
import argparse
import hashlib
import json
from pathlib import Path
import time
import numpy as np
from research_sleep_ensemble import combine, metrics

CONTEXT_NAMES = ["ageDays", "clockSin1", "clockCos1", "lastDuration", "lastNight", "episodeSpan", "wakeBeforeEpisode"]
CONFIGS = [("univariate128", 128, False), ("univariate512", 512, False), ("wakeContext512", 512, True)]


def query_at(data, index, length, context):
    now = data["wakes"][index]
    known = np.flatnonzero((np.arange(len(data["y"])) < index) & (data["available"] <= now)
                          & (data["wakes"] >= now - 60 * 86400))[-length:]
    if len(known) < 40:
        return None
    query = dict(target=np.asarray(data["y"][known], dtype=np.float32))
    if context:
        names = list(data["names"])
        query["past_covariates"] = {name: np.asarray(data["X"][known, names.index(name)], dtype=np.float32)
                                    for name in CONTEXT_NAMES}
        # API "future" means the next event index. All these values are
        # already known at the current wake, before its target is observed.
        query["future_covariates"] = {name: np.asarray(data["X"][[index], names.index(name)], dtype=np.float32)
                                      for name in CONTEXT_NAMES}
    return query


def decision_points(values, levels):
    values, levels = np.asarray(values, dtype=float), np.asarray(levels, dtype=float)
    if values.shape != levels.shape or not np.isfinite(values).all() or not np.all(np.diff(levels) > 0):
        raise ValueError("Expected finite forecasts at increasing quantile levels")
    if not 0 < levels[0] < levels[-1] < 1 or not np.any(levels == .5):
        raise ValueError("Expected interior quantiles including the median")
    median = float(np.clip(values[np.flatnonzero(levels == .5)[0]], 1, 480))
    # A discrete quantile quadrature, not a claim of a calibrated density.
    monotone = np.sort(np.clip(values, 1, 480))
    mass = np.diff(np.r_[0., (levels[:-1] + levels[1:]) / 2, 1.])
    candidates = np.unique(np.clip(np.r_[monotone, monotone - 30, monotone + 30, median], 1, 480))
    distance = np.abs(candidates[:, None] - monotone[None, :])
    risk = (distance + 30 * (distance > 30)) @ mass
    chosen = min(range(len(candidates)), key=lambda i: (risk[i], abs(candidates[i] - median), candidates[i]))
    return dict(median=median, risk=float(candidates[chosen])), int(np.any(np.diff(values) < 0))


def replay(data, fallback, predictor, levels, configs=CONFIGS, progress=None):
    outputs, diagnostics = {}, {}
    for name, length, context in configs:
        points = {key: fallback.copy() for key in ["median", "risk"]}
        issued, crossing = 0, 0
        for i in range(len(fallback)):
            query = query_at(data, i, length, context)
            if query is None:
                continue
            prediction, crossed = decision_points(predictor(query, length), levels)
            for key in points:
                points[key][i] = prediction[key]
            issued, crossing = issued + 1, crossing + crossed
            if progress and issued % 200 == 0:
                progress(name, issued)
        outputs.update({name + "_" + key: value for key, value in points.items()})
        diagnostics[name] = dict(issuedQueries=issued, crossedQuantileQueries=crossing,
                                 contextLimit=length, knownWakeCovariates=context)
    return outputs, diagnostics


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["source", "features", "baseline", "bootstrap", "model", "output"]:
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    if args.output.resolve().is_relative_to(Path(__file__).resolve().parents[1]):
        parser.error("Keep private predictions and model weights outside the repository")
    import torch
    import chronos
    from chronos import Chronos2Pipeline
    torch.set_num_threads(2)
    torch.manual_seed(42)
    bootstrap = json.loads(args.bootstrap.read_text())
    assert bootstrap["passed"]
    for name, digest in bootstrap["modelFiles"].items():
        assert hashlib.sha256((args.model / name).read_bytes()).hexdigest() == digest
    pipeline = Chronos2Pipeline.from_pretrained(args.model, device_map="cpu", dtype=torch.float32)
    pipeline.model.eval()
    data = dict(np.load(args.features, allow_pickle=False))
    base = json.loads(args.baseline.read_text())
    digest = hashlib.sha256(args.source.read_bytes()).hexdigest()
    assert digest == base["audit"]["sourceSHA256"]
    indices = data["indices"].astype(int).tolist()
    rows = {r["index"]: r for r in base["events"]}
    assert set(indices) == set(rows)
    np.testing.assert_allclose([rows[i]["actual"] for i in indices], data["available"], rtol=0, atol=1e-6)
    np.testing.assert_allclose([rows[i]["wakeMinutes"] for i in indices], data["y"], rtol=0, atol=1e-6)
    fallback = (np.array([rows[i]["prediction"] for i in indices]) - data["wakes"]) / 60
    def predictor(query, length):
        result = pipeline.predict([query], prediction_length=1, context_length=length,
                                  batch_size=256, cross_learning=False)[0]
        assert tuple(result.shape) == (1, len(pipeline.quantiles), 1)
        return result[0, :, 0].detach().cpu().numpy()
    started = time.monotonic()
    def progress(name, issued):
        print(json.dumps(dict(configuration=name, issuedQueries=issued, seconds=time.monotonic() - started)), flush=True)
    forecasts, diagnostics = replay(data, fallback, predictor, pipeline.quantiles, progress=progress)
    result = dict(audit=dict(sourceSHA256=digest, careExposure="completed", library="chronos-forecasting",
        version=chronos.__version__, torchVersion=torch.__version__, device="cpu", threads=2, dtype="float32",
        modelFiles=bootstrap["modelFiles"], modelQuantiles=pipeline.quantiles, crossLearning=False,
        featureCacheSHA256=hashlib.sha256(args.features.read_bytes()).hexdigest(),
        baselineResultSHA256=hashlib.sha256(args.baseline.read_bytes()).hexdigest(),
        scriptSHA256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), contextNames=CONTEXT_NAMES,
        diagnostics=diagnostics, lookbackDays=60, minimumLabels=40,
        rule="Event-indexed resolved gaps; single-query inference; current wake covariates known before target; no fine-tuning",
        decisionRule="Native median and custom discrete-quantile absolute-error plus 30-minute miss penalty",
        sourceURLs=["https://arxiv.org/abs/2510.15821", "https://github.com/amazon-science/chronos-forecasting"]), models={}, events={})
    def save(name, prediction):
        result["models"][name] = dict(all=metrics(data["y"], prediction, np.ones(len(indices), dtype=bool)))
        result["events"][name] = [dict(index=i, actual=float(y), prediction=float(p))
            for i, y, p in zip(indices, data["y"], prediction)]
        args.output.write_text(json.dumps(result, indent=2) + "\n")
        print(name, json.dumps(result["models"][name]), flush=True)
    for name, prediction in forecasts.items():
        save(name, prediction)
    members = np.column_stack([fallback, *forecasts.values()])
    for name, policy, calibrate, local in [("localCalibratedSoft", "soft", True, True),
        ("localCalibratedBest", "best", True, True), ("localRawSoft", "soft", False, True),
        ("globalCalibratedSoft", "soft", True, False), ("calibratedMedian", "median", True, True)]:
        save("sequencePrior_" + name, combine(data, members, policy, calibrate, local))


if __name__ == "__main__":
    main()
