#!/usr/bin/env python3
"""Causal short-return/full-wake distributions, scored on every transition.

Class probabilities mix historical leaf distributions instead of choosing one
class's median. This is an independent quantile-forest-style experiment, not a
published infant accuracy claim. No app data is imported or modified.
"""
import argparse
import hashlib
import json
from pathlib import Path
import time

import numpy as np
from sklearn.ensemble import ExtraTreesClassifier, ExtraTreesRegressor, HistGradientBoostingClassifier
from sklearn.impute import SimpleImputer
from threadpoolctl import threadpool_limits
from research_sleep_predictions import metrics


def point_estimates(values, weights, half_width=30.):
    values, weights = np.asarray(values, dtype=float), np.asarray(weights, dtype=float)
    if not len(values) or values.shape != weights.shape or half_width <= 0 or not np.all(np.isfinite(values)) or \
            not np.all(np.isfinite(weights)) or np.any(weights < 0) or np.sum(weights) <= 0:
        raise ValueError("Expected finite outcomes and nonnegative distribution weights")
    order = np.argsort(values, kind="stable")
    y, w = values[order], weights[order] / np.sum(weights)
    cumulative = np.r_[0., np.cumsum(w)]
    median = float(y[np.searchsorted(cumulative[1:], .5 - 1e-12)])
    best_mass, best_cost, mode = -1., float("inf"), median
    for left in range(len(y)):
        right = np.searchsorted(y, y[left] + 2 * half_width, side="right") - 1
        mass = cumulative[right + 1] - cumulative[left]
        if mass < best_mass - 1e-12:
            continue
        center = float(np.clip(median, y[right] - half_width, y[left] + half_width))
        cost = float(np.dot(w, np.abs(y - center)))
        if mass > best_mass + 1e-12 or cost < best_cost - 1e-12 or (abs(cost - best_cost) <= 1e-12 and center < mode):
            best_mass, best_cost, mode = float(mass), cost, center
    return median, mode


class ConditionalWakeDistribution:
    def __init__(self, classifier="forest"):
        if classifier not in ["forest", "boosted"]:
            raise ValueError("Unknown classifier")
        self.classifier_kind = classifier

    def fit(self, x, y):
        self.imputer = SimpleImputer(keep_empty_features=True)
        x = self.imputer.fit_transform(x)
        self.y = np.asarray(y, dtype=float).copy()
        short = self.y <= 20
        self.probability = float(np.mean(short))
        self.classifier = None
        if len(np.unique(short)) == 2:
            if self.classifier_kind == "forest":
                self.classifier = ExtraTreesClassifier(n_estimators=80, min_samples_leaf=8,
                    max_features=.8, random_state=42, n_jobs=1)
            else:
                self.classifier = HistGradientBoostingClassifier(max_iter=150, max_leaf_nodes=7,
                    min_samples_leaf=12, l2_regularization=10, early_stopping=False, random_state=42)
            self.classifier.fit(x, short)
        self.components = []
        for mask in [short, ~short]:
            indices = np.flatnonzero(mask)
            forest, leaves = None, None
            if len(indices) >= 10:
                forest = ExtraTreesRegressor(n_estimators=80, min_samples_leaf=5,
                    max_features=.8, random_state=42, n_jobs=1).fit(x[indices], self.y[indices])
                leaves = forest.apply(x[indices])
            self.components.append((indices, forest, leaves))
        return self

    def predict(self, x):
        x = self.imputer.transform(x)
        probabilities = self.classifier.predict_proba(x)[:, 1] if self.classifier is not None else np.full(len(x), self.probability)
        output = []
        for row, p in zip(x, probabilities):
            weights = np.zeros(len(self.y))
            for (indices, forest, leaves), probability in zip(self.components, [p, 1 - p]):
                if not len(indices):
                    continue
                if forest is None:
                    local = np.ones(len(indices))
                else:
                    same = leaves == forest.apply(row[None, :])[0]
                    local = np.sum(same / np.maximum(np.sum(same, axis=0), 1), axis=1)
                weights[indices] = probability * local / np.sum(local)
            output.append(point_estimates(self.y, weights))
        return np.asarray(output)


def run(data, fallback, classifier, model_factory=None):
    x, y, wakes, available = [data[k] for k in ["X", "y", "wakes", "available"]]
    predictions = np.column_stack([fallback, fallback])
    fitted_at, model, refits = -24, None, 0
    factory = model_factory or (lambda: ConditionalWakeDistribution(classifier))
    with threadpool_limits(limits=1):
        for i, now in enumerate(wakes):
            train = np.flatnonzero((np.arange(len(y)) < i) & (available <= now) & (wakes >= now - 60 * 86400))
            if len(train) >= 40 and i - fitted_at >= 24:
                model = factory().fit(x[train], y[train])
                fitted_at, refits = i, refits + 1
            if model is not None:
                predictions[i] = model.predict(x[i:i + 1])[0]
    return predictions, refits


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["features", "baseline", "source", "output"]:
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root):
        parser.error("Keep personal results outside the repository")
    base = json.loads(args.baseline.read_text())
    assert base["audit"]["sourceSHA256"] == hashlib.sha256(args.source.read_bytes()).hexdigest()
    data = dict(np.load(args.features, allow_pickle=False))
    rows = {r["index"]: r for r in base["events"]}
    assert set(rows) == set(data["indices"])
    np.testing.assert_allclose([rows[int(i)]["actual"] for i in data["indices"]], data["available"], rtol=0, atol=1e-6)
    np.testing.assert_allclose([rows[int(i)]["wakeMinutes"] for i in data["indices"]], data["y"], rtol=0, atol=1e-6)
    np.testing.assert_allclose(data["available"] - data["wakes"], data["y"] * 60, rtol=0, atol=1e-6)
    fallback = np.array([(rows[int(index)]["prediction"] - wake) / 60 for index, wake in zip(data["indices"], data["wakes"])])
    after_nap = data["X"][:, list(data["names"]).index("lastNight")] < .5
    result = dict(audit=dict(sourceSHA256=base["audit"]["sourceSHA256"], careExposure="completed",
        fallbackAlgorithm=base["algorithm"], shortReturnThresholdMinutes=20, lookbackDays=60, refitEvery=24,
        rule="Mix conditional historical distributions using wake-time class probabilities; fixed +/-30-minute tolerance"),
        models={}, events={})
    for classifier in ["forest", "boosted"]:
        started = time.monotonic()
        forecasts, refits = run(data, fallback, classifier)
        for k, point in enumerate(["median", "toleranceMode"]):
            for localized in [False, True]:
                prediction = np.where(after_nap, forecasts[:, k], fallback) if localized else forecasts[:, k]
                name = "distribution_" + classifier + "_" + point + ("_afterNap" if localized else "")
                result["models"][name] = dict(all=metrics(data["y"], prediction, np.ones(len(prediction), dtype=bool)),
                    afterNap=metrics(data["y"], prediction, after_nap), refits=refits, seconds=time.monotonic() - started)
                result["events"][name] = [dict(index=int(i), actual=float(y), prediction=float(p))
                    for i, y, p in zip(data["indices"], data["y"], prediction)]
                print(name, result["models"][name]["all"], flush=True)
        args.output.write_text(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
