#!/usr/bin/env python3
"""Adapt forest neighborhood weights to local ridge/median regression.

Inspired by equation (3) of https://arxiv.org/abs/1807.11408. This retains
ordinary randomized-tree splits, without the paper's honest/residual splitting
construction. It is not a reproduction or an infant-specific accuracy claim.
"""
import argparse
import hashlib
import json
from pathlib import Path
import time

import numpy as np
from scipy.optimize import linprog
from scipy import sparse

from research_sleep_predictions import WakeAnalogs, metrics
from research_sleep_regimes import run
from research_sleep_ensemble import combine


class LocalForestRegression(WakeAnalogs):
    def __init__(self, columns, loss="mean", penalty=1.):
        super().__init__("forest", 5)
        if loss not in ["mean", "median"] or not np.isfinite(penalty) or penalty <= 0:
            raise ValueError("Unknown loss or invalid slope penalty")
        self.columns, self.loss, self.penalty = columns, loss, penalty
        self.solver_failures = 0

    def fit(self, x, y):
        super().fit(x, y)
        self.local_x = self.imputer.transform(x)[:, self.columns]
        scale = np.quantile(self.local_x, .75, axis=0) - np.quantile(self.local_x, .25, axis=0)
        self.scale = np.where(scale > 1e-8, scale, 1.)
        return self

    def predict(self, x):
        values = self.imputer.transform(x)
        leaves = self.forest.apply(values)
        output = []
        for row, leaf in zip(values, leaves):
            same = self.leaves == leaf
            weights = np.sum(same / np.maximum(np.sum(same, axis=0), 1), axis=1)
            selected = weights > 0
            weights = weights[selected] / np.sum(weights)
            y = self.y[selected]
            delta = (self.local_x[selected] - row[self.columns]) / self.scale
            design = np.column_stack([np.ones(len(y)), delta])
            if self.loss == "mean":
                ridge = np.diag([0.] + [self.penalty] * delta.shape[1])
                coefficients = np.linalg.solve(design.T @ (weights[:, None] * design) + ridge, design.T @ (weights * y))
                point = coefficients[0]
            else:
                # Minimize weighted absolute residuals plus an L1 slope penalty.
                # The intercept is unpenalized and denotes the query prediction.
                penalty = np.array([0.] + [self.penalty] * delta.shape[1])
                objective = np.concatenate([penalty, penalty, weights, weights])
                d = sparse.csr_matrix(design)
                identity = sparse.eye(len(y), format="csr")
                constraint = sparse.hstack([d, -d, identity, -identity], format="csr")
                result = linprog(objective, A_eq=constraint, b_eq=y, bounds=(0, None), method="highs-ds")
                if result.success and np.all(np.isfinite(result.x)):
                    point = result.x[0] - result.x[design.shape[1]]
                else:
                    self.solver_failures += 1
                    order = np.argsort(y)
                    point = y[order[np.searchsorted(np.cumsum(weights[order]), .5)]]
            if not np.isfinite(point):
                raise ValueError("Nonfinite local forecast")
            output.append(np.clip(point, 1, 480))
        return np.asarray(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["source", "features", "baseline", "incumbent", "output"]:
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root):
        parser.error("Keep history-derived results outside the repository")
    baseline, incumbent = [json.loads(p.read_text()) for p in [args.baseline, args.incumbent]]
    source_hash = hashlib.sha256(args.source.read_bytes()).hexdigest()
    assert baseline["audit"]["sourceSHA256"] == incumbent["audit"]["sourceSHA256"] == source_hash
    data = dict(np.load(args.features, allow_pickle=False))
    indices = data["indices"].astype(int).tolist()
    base = {r["index"]: r for r in baseline["events"]}
    current = {r["index"]: r for r in incumbent["events"]}
    assert set(indices) == set(base) == set(current)
    for rows in [base, current]:
        np.testing.assert_allclose([rows[i]["actual"] for i in indices], data["available"], rtol=0, atol=1e-6)
        np.testing.assert_allclose([rows[i]["wakeMinutes"] for i in indices], data["y"], rtol=0, atol=1e-6)
    fallback = np.array([(base[i]["prediction"] - wake) / 60 for i, wake in zip(indices, data["wakes"])])
    selected = ["ageDays", "clockSin1", "clockCos1", "clockSin2", "clockCos2", "lastDuration",
        "wakeLag1", "homeostat120_60", "homeostat240_120"]
    columns = [list(data["names"]).index(name) for name in selected]
    result = dict(audit=dict(sourceSHA256=source_hash, careExposure="completed", featureCount=len(data["names"]),
        localSlopeFeatures=selected, lookbackDays=60, refitEvery=24,
        baselineResultSHA256=hashlib.sha256(args.baseline.read_bytes()).hexdigest(),
        incumbentResultSHA256=hashlib.sha256(args.incumbent.read_bytes()).hexdigest(),
        featureCacheSHA256=hashlib.sha256(args.features.read_bytes()).hexdigest(),
        sourcePaper="https://arxiv.org/abs/1807.11408",
        adaptation="Ordinary forest weights with local ridge mean or L1-penalized median regression; no honest or residual-aware tree splitting"),
        models={}, events={})
    mask = np.ones(len(indices), dtype=bool)

    def save(name, prediction, **details):
        result["models"][name] = dict(all=metrics(data["y"], prediction, mask), **details)
        result["events"][name] = [dict(index=i, actual=float(y), prediction=float(p)) for i, y, p in zip(indices, data["y"], prediction)]
        args.output.write_text(json.dumps(result, indent=2) + "\n")
        print(name, json.dumps(result["models"][name]), flush=True)

    variants = [("localCalibratedSoft", "soft", True, True), ("localCalibratedBest", "best", True, True),
        ("localRawSoft", "soft", False, True), ("globalCalibratedSoft", "soft", True, False),
        ("calibratedMedian", "median", True, True)]
    for loss, penalty in [("mean", 1.), ("median", .1)]:
        experts = [fallback]
        models = []
        def factory():
            model = LocalForestRegression(columns, loss=loss, penalty=penalty)
            models.append(model)
            return model
        for policy in ["previousKind", "wakePhase", "cycleStage"]:
            started = time.monotonic()
            before = len(models)
            prediction, counts = run(data, fallback, policy, model_factory=factory)
            experts.append(prediction)
            save(loss + "_" + policy, prediction, penalty=penalty, refits=int(np.sum(counts > 0)),
                seconds=time.monotonic() - started, solverFailures=sum(m.solver_failures for m in models[before:]))
        for name, policy, calibrate, local in variants:
            prediction = combine(data, np.column_stack(experts), policy=policy, calibrate=calibrate, local=local)
            save(loss + "_" + name, prediction, penalty=penalty)


if __name__ == "__main__":
    main()
