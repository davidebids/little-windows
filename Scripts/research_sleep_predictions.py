#!/usr/bin/env python3
"""Causal research benchmark for stronger next-sleep models; never modifies app data.

Inputs and per-event outputs must remain outside the repository. Requires numpy,
scipy and scikit-learn. Every feature is computed at the last recorded wake;
training labels become available only when the following sleep has started.
This is a research benchmark, not an app runtime dependency.
"""
import argparse
import csv
import datetime as dt
import hashlib
import json
from pathlib import Path
import re
import sys
import time
from zoneinfo import ZoneInfo

import numpy as np
from sklearn.ensemble import ExtraTreesRegressor, HistGradientBoostingClassifier, HistGradientBoostingRegressor
from sklearn.impute import SimpleImputer
from sklearn.mixture import GaussianMixture
from sklearn.decomposition import NMF
from sklearn.compose import TransformedTargetRegressor
from sklearn.gaussian_process import GaussianProcessRegressor
from sklearn.gaussian_process.kernels import ConstantKernel, Matern, RBF, WhiteKernel
from sklearn.linear_model import Ridge
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.svm import SVR
from scipy.ndimage import gaussian_filter1d
from scipy.optimize import minimize, nnls
from scipy.special import logsumexp, ndtr
from threadpoolctl import threadpool_limits

sys.path.insert(0, str(Path(__file__).resolve().parent / "SleepReplay"))
from portable_forest import PortableForest


def load_history(path, birth_date, zone):
    tz = ZoneInfo(zone)
    def parse(value):
        return dt.datetime.strptime(value, "%Y-%m-%d %H:%M").replace(tzinfo=tz).timestamp()
    birth = parse(birth_date + " 00:00")
    rows = list(csv.DictReader(path.open(encoding="utf-8-sig")))
    sleeps, care = [], []
    for row in rows:
        if not row.get("Start"):
            continue
        start = parse(row["Start"])
        end = parse(row["End"]) if row.get("End") else start
        if row["Type"] == "Sleep":
            if end > start:
                local = dt.datetime.fromtimestamp(start, tz)
                end_local = dt.datetime.fromtimestamp(end, tz)
                night = local.hour >= 19 or local.hour < 6 or end_local.date() > local.date()
                sleeps.append([start, end, float(night)])
        else:
            care.append((start, end, row["Type"]))
    sleeps.sort()
    for i, sleep in enumerate(sleeps):
        hour = dt.datetime.fromtimestamp(sleep[0], tz).hour
        if not sleep[2] and hour < 9 and i:
            previous = sleeps[i - 1]
            sleep[2] = float(previous[2] and sleep[0] - previous[1] <= 90 * 60)
    return np.asarray(sleeps), care, birth, tz


def feature_rows(sleeps, care, birth, tz, include_started_care=False):
    """No target-event fields enter features, including its kind or duration."""
    features, labels, wakes, available, indices = [], [], [], [], []
    names = None
    care_types = ["Feed", "Diaper", "Solids", "Meds", "Bath", "Tummy time"]
    care_arrays = {kind: np.asarray([[s, e] for s, e, k in care if k == kind], dtype=float).reshape(-1, 2) for kind in care_types}
    history_targets = []
    for i, current in enumerate(sleeps[:-1]):
        now = current[1]
        actual = sleeps[i + 1, 0]
        if actual <= now or np.any(sleeps[:i + 1, 1] > now):
            continue
        history = sleeps[:i + 1]
        history = history[history[:, 1] <= now]
        local = dt.datetime.fromtimestamp(now, tz)
        day_start = local.replace(hour=0, minute=0, second=0, microsecond=0).timestamp()
        minute = local.hour * 60 + local.minute
        durations = (history[:, 1] - history[:, 0]) / 60
        gaps = (history[1:, 0] - history[:-1, 1]) / 60
        f = {"ageDays": (now - birth) / 86400, "wakeMinute": minute,
             "weekday": local.weekday(), "lastDuration": durations[-1], "lastNight": current[2]}
        for harmonic in [1, 2, 3]:
            f[f"clockSin{harmonic}"] = np.sin(2 * np.pi * harmonic * minute / 1440)
            f[f"clockCos{harmonic}"] = np.cos(2 * np.pi * harmonic * minute / 1440)
        for lag in range(1, 7):
            f[f"durationLag{lag}"] = durations[-lag] if len(durations) >= lag else np.nan
            f[f"wakeLag{lag}"] = gaps[-lag] if len(gaps) >= lag else np.nan
        today = history[history[:, 0] >= day_start]
        f["sleepsToday"] = len(today)
        f["napsToday"] = np.sum(today[:, 2] == 0)
        f["sleepMinutesToday"] = np.sum(np.maximum(0, np.minimum(history[:, 1], now) - np.maximum(history[:, 0], day_start))) / 60
        # Logical-episode context uses only interruptions that have already happened.
        start = len(history) - 1
        while start and 0 <= history[start, 0] - history[start - 1, 1] <= 20 * 60:
            start -= 1
        f["episodeSpan"] = (now - history[start, 0]) / 60
        f["episodeSleepMinutes"] = np.sum(durations[start:])
        f["episodeSegments"] = len(history) - start
        f["wakeBeforeEpisode"] = gaps[start - 1] if start else np.nan
        for hours in [3, 6, 12, 24, 48]:
            lower = now - hours * 3600
            f[f"sleepMinutes{hours}h"] = np.sum(np.maximum(0, np.minimum(history[:, 1], now) - np.maximum(history[:, 0], lower))) / 60
            f[f"sleepCount{hours}h"] = np.sum(history[:, 0] >= lower)
        # Banks of observed homeostatic states: exponential approach to 1 awake,
        # decay toward 0 asleep. These are model features, not medical estimates.
        for awake_tau, sleep_tau in [(60, 30), (120, 60), (240, 120), (480, 240), (960, 480)]:
            state, cursor = .5, history[max(0, len(history) - 150), 0]
            for s, e, _ in history[-150:]:
                if s > cursor:
                    state = 1 - (1 - state) * np.exp(-(s - cursor) / (awake_tau * 60))
                state *= np.exp(-max(0, e - max(s, cursor)) / (sleep_tau * 60))
                cursor = max(cursor, e)
            f[f"homeostat{awake_tau}_{sleep_tau}"] = state
        for kind, values in care_arrays.items():
            known = values[(values[:, 0] <= now) & (values[:, 1] <= now)]
            if len(known):
                last = known[np.argmax(known[:, 1])]
                f[f"last{kind}Minutes"] = min(2880, (now - last[1]) / 60)
                f[f"last{kind}Duration"] = (last[1] - last[0]) / 60
            else:
                f[f"last{kind}Minutes"], f[f"last{kind}Duration"] = np.nan, np.nan
            for hours in [3, 12, 24]:
                f[f"{kind}Count{hours}h"] = np.sum(known[:, 0] >= now - hours * 3600) if len(known) else 0
            # Alternative input exposure: a started timer can be known before
            # it finishes. Expose only start time and elapsed time at this wake,
            # never the eventual duration or future end time.
            if include_started_care:
                started = values[values[:, 0] <= now]
                running = started[started[:, 1] > now]
                f[f"last{kind}StartMinutes"] = min(2880, (now - np.max(started[:, 0])) / 60) if len(started) else np.nan
                f[f"{kind}Running"] = float(len(running) > 0)
                f[f"{kind}RunningElapsed"] = (now - np.max(running[:, 0])) / 60 if len(running) else 0
        # Rolling target summaries are labels of PREVIOUS transitions only.
        previous = [(w, a, y, clock, night) for w, a, y, clock, night in history_targets if a <= now]
        for days in [7, 14, 28, 60]:
            eligible = [p for p in previous if p[0] >= now - days * 86400]
            for context in ["all", "clock", "kind"]:
                chosen = eligible
                if context == "clock":
                    chosen = [p for p in chosen if min(abs(p[3] - minute), 1440 - abs(p[3] - minute)) <= 120]
                elif context == "kind":
                    chosen = [p for p in chosen if p[4] == current[2]]
                vals = [p[2] for p in chosen]
                f[f"prior{days}d_{context}_median"] = np.median(vals) if vals else np.nan
                f[f"prior{days}d_{context}_shortFraction"] = np.mean(np.asarray(vals) <= 20) if vals else np.nan
        if names is None:
            names = list(f)
        assert list(f) == names
        features.append([f[n] for n in names])
        labels.append((actual - now) / 60)
        wakes.append(now)
        available.append(actual)
        indices.append(i)
        history_targets.append((now, actual, labels[-1], minute, current[2]))
    return dict(X=np.asarray(features), y=np.asarray(labels), wakes=np.asarray(wakes),
                available=np.asarray(available), indices=np.asarray(indices), names=names)


def structured_features(records, wakes, bins=64):
    """Fixed hashing of completed-record conditions; no vocabulary fit or notes."""
    vectors, ends, starts, sleep = [], [], [], []
    for record in records:
        vector = np.zeros(bins)
        for field in ["Start Condition", "Start Location", "End Condition"]:
            value = record.get(field, "").strip().lower()
            if not value:
                continue
            # Hash categories and word tokens; never retain source text in features.
            tokens = ["value=" + value] + ["word=" + word for word in set(re.findall(r"[a-z]+", value))]
            for token in tokens:
                encoded = (record["Type"] + "/" + field + "/" + token).encode("utf-8")
                digest = hashlib.blake2b(encoded, digest_size=8).digest()
                slot = int.from_bytes(digest, "little") % bins
                vector[slot] += 1 if digest[-1] < 128 else -1
        vectors.append(vector)
        ends.append(record["endEpoch"])
        starts.append(record["startEpoch"])
        sleep.append(record["Type"] == "Sleep")
    vectors = np.asarray(vectors).reshape(-1, bins)
    ends, starts, sleep = np.asarray(ends), np.asarray(starts), np.asarray(sleep)
    output = []
    for now in wakes:
        known = np.flatnonzero((ends <= now) & (starts <= now))
        prior_sleep = known[sleep[known]]
        last = vectors[prior_sleep[np.argmax(ends[prior_sleep])]] if len(prior_sleep) else np.zeros(bins)
        recent = known[starts[known] >= now - 12 * 3600]
        if len(recent):
            weights = np.exp2(-(now - ends[recent]) / (3 * 3600))
            aggregate = np.sum(vectors[recent] * weights[:, None], axis=0) / max(1, np.sqrt(np.sum(weights)))
        else:
            aggregate = np.zeros(bins)
        output.append(np.r_[last, aggregate])
    return np.asarray(output)


def read_structured_records(path, zone):
    def parse(value):
        return dt.datetime.strptime(value, "%Y-%m-%d %H:%M").replace(tzinfo=zone).timestamp()
    output = []
    with path.open(encoding="utf-8-sig") as stream:
        for row in csv.DictReader(stream):
            if not row.get("Start"):
                continue
            start = parse(row["Start"])
            end = parse(row["End"]) if row.get("End") else start
            output.append({key: row.get(key, "") for key in ["Type", "Start Condition", "Start Location", "End Condition"]} |
                          dict(startEpoch=start, endEpoch=end))
    return output


def candidate(name):
    if name.startswith("portable_"):
        _, trees, leaf = name.split("_")
        return PortableForest(int(trees), int(leaf))
    if name.startswith("neural_"):
        parts = name.split("_")
        if len(parts) not in [3, 4] or (len(parts) == 4 and parts[3] not in ["regularized", "compact"]):
            raise ValueError(name)
        stronger = len(parts) > 3
        return WakeNeural(int(parts[2]), parts[1], alpha=.1 if stronger else .01, max_iter=1000 if stronger else 200)
    if name.startswith("gp_"):
        _, kernel, transform = name.split("_")
        return WakeGaussianProcess(kernel, transform == "log")
    if name.startswith("loghist_"):
        leaf = int(name.split("_")[1])
        return TransformedTargetRegressor(
            regressor=candidate("hist_absolute_error_" + str(leaf) + "_10"),
            func=np.log1p, inverse_func=np.expm1)
    if name.startswith("density_"):
        _, components, transform = name.split("_")
        return WakeDensity(int(components), transform == "log")
    if name.startswith("analog_"):
        _, method, neighbors = name.split("_")
        return WakeAnalogs(method, int(neighbors))
    if name.startswith("mixture"):
        return WakeMixture(threshold=float(name.split("_")[1]))
    if name.startswith("hist"):
        loss, leaf, regularization = name[len("hist_"):].rsplit("_", 2)
        return make_pipeline(SimpleImputer(add_indicator=True, keep_empty_features=True), HistGradientBoostingRegressor(loss=loss, max_iter=180, learning_rate=.055,
            max_leaf_nodes=int(leaf), min_samples_leaf=12, l2_regularization=float(regularization),
            early_stopping=False, random_state=42))
    if name.startswith("extra"):
        leaf = int(name.split("_")[1])
        return make_pipeline(SimpleImputer(add_indicator=True, keep_empty_features=True), ExtraTreesRegressor(n_estimators=120, min_samples_leaf=leaf, max_features=.8,
            criterion="absolute_error", random_state=42, n_jobs=1))
    if name.startswith("svr"):
        c = float(name.split("_")[1])
        return make_pipeline(SimpleImputer(add_indicator=True, keep_empty_features=True), StandardScaler(), SVR(C=c, epsilon=5))
    if name == "ridge":
        return make_pipeline(SimpleImputer(add_indicator=True, keep_empty_features=True), StandardScaler(), Ridge(alpha=100))
    raise ValueError(name)


def sequence_features(data, length=12):
    """Ordered previous outcomes available at each wake, not eventual outcomes."""
    names = list(data["names"])
    columns = [names.index(name) for name in ["lastDuration", "clockSin1", "clockCos1"]]
    output = np.full((len(data["y"]), length * 5), np.nan)
    for i, now in enumerate(data["wakes"]):
        known = np.flatnonzero((np.arange(len(data["y"])) < i) & (data["available"] <= now))
        for lag, j in enumerate(known[-length:][::-1]):
            duration, sine, cosine = data["X"][j, columns]
            output[i, lag * 5:(lag + 1) * 5] = [duration, data["y"][j], sine, cosine, (now - data["wakes"][j]) / 3600]
    return output


class WakeNeural:
    """Small deterministic tanh network with a robust or squared training loss."""
    def __init__(self, width=16, loss="huber", alpha=.01, max_iter=200):
        self.width, self.loss, self.alpha = width, loss, alpha
        self.max_iter = max_iter

    @staticmethod
    def unpack(theta, columns, width):
        split = columns * width
        return theta[:split].reshape(columns, width), theta[split:split + width], theta[split + width:split + 2 * width], theta[-1]

    @staticmethod
    def objective(theta, x, y, width, alpha, loss):
        w1, b1, w2, b2 = WakeNeural.unpack(theta, x.shape[1], width)
        hidden = np.tanh(x @ w1 + b1)
        error = hidden @ w2 + b2 - y
        if loss == "huber":
            delta = .1
            absolute = np.abs(error)
            value = np.mean(np.where(absolute <= delta, .5 * error ** 2 / delta, absolute - .5 * delta))
            derivative = np.clip(error / delta, -1, 1) / len(y)
        elif loss == "squared":
            value = np.mean(.5 * error ** 2)
            derivative = error / len(y)
        else:
            raise ValueError(loss)
        value += .5 * alpha * (np.sum(w1 ** 2) + np.sum(w2 ** 2))
        hidden_gradient = derivative[:, None] * w2 * (1 - hidden ** 2)
        gradient = np.r_[(x.T @ hidden_gradient + alpha * w1).ravel(), np.sum(hidden_gradient, axis=0),
                          hidden.T @ derivative + alpha * w2, np.sum(derivative)]
        return float(value), gradient

    def fit(self, x, y):
        self.inputs = make_pipeline(SimpleImputer(keep_empty_features=True), StandardScaler())
        x = self.inputs.fit_transform(x)
        self.center = float(np.median(y))
        self.scale = max(30., float(np.quantile(y, .75) - np.quantile(y, .25)))
        self.columns = x.shape[1]
        rng = np.random.default_rng(42)
        initial = np.r_[rng.normal(0, 1 / np.sqrt(self.columns), self.columns * self.width),
                        np.zeros(self.width), rng.normal(0, 1 / np.sqrt(self.width), self.width), 0.]
        fitted = minimize(self.objective, initial, args=(x, (y - self.center) / self.scale, self.width, self.alpha, self.loss),
                          jac=True, method="L-BFGS-B", options={"maxiter": self.max_iter, "ftol": 1e-8})
        self.theta = fitted.x
        self.optimization = dict(converged=bool(fitted.success), iterations=int(fitted.nit), objective=float(fitted.fun),
                                 inputFeatureCount=self.columns, regularization=self.alpha, iterationLimit=self.max_iter)
        return self

    def predict(self, x):
        x = self.inputs.transform(x)
        w1, b1, w2, b2 = self.unpack(self.theta, self.columns, self.width)
        return (np.tanh(x @ w1 + b1) @ w2 + b2) * self.scale + self.center


class WakeGaussianProcess:
    """Learn similarity scales and observation noise from this profile's past."""
    def __init__(self, kernel="rbf", logarithmic=True):
        self.kernel, self.logarithmic = kernel, logarithmic

    def fit(self, x, y):
        self.inputs = make_pipeline(SimpleImputer(keep_empty_features=True), StandardScaler())
        x = self.inputs.fit_transform(x)
        base = RBF(np.ones(x.shape[1]), (.1, 100)) if self.kernel == "rbf" else Matern(np.ones(x.shape[1]), (.1, 100), nu=1.5)
        kernel = ConstantKernel(1., (.1, 10)) * base + WhiteKernel(.3, (.01, 10))
        def optimize(objective, initial, bounds):
            fitted = minimize(objective, initial, jac=True, bounds=bounds, method="L-BFGS-B", options={"maxiter": 50})
            return fitted.x, fitted.fun
        self.model = GaussianProcessRegressor(kernel=kernel, normalize_y=True, alpha=1e-6,
                                              optimizer=optimize, random_state=42)
        self.model.fit(x, np.log1p(y) if self.logarithmic else y)
        return self

    def predict(self, x):
        result = self.model.predict(self.inputs.transform(x))
        return np.expm1(result) if self.logarithmic else result


class WakeDensity:
    """Conditional Gaussian-mixture median; all fitting sees past labels only."""
    def __init__(self, components=3, logarithmic=True):
        self.components, self.logarithmic = components, logarithmic

    def fit(self, x, y):
        self.imputer = SimpleImputer(keep_empty_features=True)
        x = self.imputer.fit_transform(x)
        target = np.log1p(y) if self.logarithmic else y
        self.scaler = StandardScaler().fit(np.column_stack([x, target]))
        joint = self.scaler.transform(np.column_stack([x, target]))
        self.model = GaussianMixture(n_components=min(self.components, max(1, len(y) // 12)),
                                     covariance_type="full", reg_covar=.1, max_iter=150,
                                     n_init=2, random_state=42).fit(joint)
        covariance = self.model.covariances_
        self.inverse = np.linalg.inv(covariance[:, :-1, :-1])
        self.logdet = np.linalg.slogdet(covariance[:, :-1, :-1])[1]
        self.slope = np.einsum("ki,kij->kj", covariance[:, -1, :-1], self.inverse)
        self.conditional_sd = np.sqrt(np.maximum(covariance[:, -1, -1] -
                                                  np.sum(self.slope * covariance[:, :-1, -1], axis=1), 1e-8))
        return self

    def posterior(self, x, y):
        target = np.log1p(y) if self.logarithmic else y
        joint = np.column_stack([self.imputer.transform(x), target])
        return self.model.predict_proba(self.scaler.transform(joint))

    def predict(self, x, prior=None):
        x = self.imputer.transform(x)
        x = (x - self.scaler.mean_[:-1]) / self.scaler.scale_[:-1]
        output = []
        for row in x:
            delta = row - self.model.means_[:, :-1]
            log_weights = np.log(np.maximum(self.model.weights_ if prior is None else prior, 1e-12)) - .5 * (self.logdet +
                np.einsum("ki,kij,kj->k", delta, self.inverse, delta))
            weights = np.exp(log_weights - logsumexp(log_weights))
            means = self.model.means_[:, -1] + np.sum(self.slope * delta, axis=1)
            low, high = 1., 480.
            for _ in range(30):
                middle = (low + high) / 2
                value = np.log1p(middle) if self.logarithmic else middle
                z = (value - self.scaler.mean_[-1]) / self.scaler.scale_[-1]
                probability = np.sum(weights * ndtr((z - means) / self.conditional_sd))
                if probability < .5:
                    low = middle
                else:
                    high = middle
            output.append((low + high) / 2)
        return np.asarray(output)


class WakeAnalogs:
    """Past-outcome analogs with a fitted distance or forest-leaf similarity."""
    def __init__(self, method="metric", neighbors=15):
        self.method, self.neighbors = method, neighbors

    def fit(self, x, y):
        self.imputer = SimpleImputer(keep_empty_features=True)
        x = self.imputer.fit_transform(x)
        self.y = y.copy()
        if self.method == "forest":
            self.forest = ExtraTreesRegressor(n_estimators=80, min_samples_leaf=self.neighbors,
                                              max_features=.8, random_state=42, n_jobs=1).fit(x, y)
            self.leaves = self.forest.apply(x)
            return self
        scale = np.quantile(x, .75, axis=0) - np.quantile(x, .25, axis=0)
        self.scale = np.where(scale > 1e-8, scale, 1.)
        self.x = x / self.scale
        self.weights = np.full(x.shape[1], 1 / x.shape[1])
        if self.method == "metric":
            rng = np.random.default_rng(42)
            left = rng.integers(len(y), size=5000)
            right = rng.integers(len(y), size=5000)
            differences = np.minimum(np.abs(self.x[left] - self.x[right]), 5.)
            target = np.minimum(np.abs(y[left] - y[right]), 180.) / 60
            learned, _ = nnls(differences, target)
            if np.sum(learned) > 1e-8:
                self.weights = .9 * learned / np.sum(learned) + .1 / x.shape[1]
        elif self.method != "uniform":
            raise ValueError(self.method)
        return self

    def predict(self, x):
        x = self.imputer.transform(x)
        output = []
        for row in x:
            if self.method == "forest":
                same = self.leaves == self.forest.apply(row[None, :])[0]
                weights = np.sum(same / np.maximum(np.sum(same, axis=0), 1), axis=1)
                selected = np.flatnonzero(weights > 0)
                weights = weights[selected]
            else:
                distance = np.minimum(np.abs(self.x - row / self.scale), 5.) @ self.weights
                selected = np.argsort(distance)[:self.neighbors]
                weights = np.exp(-distance[selected] / max(distance[selected[-1]], 1e-8))
            order = np.argsort(self.y[selected])
            cumulative = np.cumsum(weights[order])
            output.append(self.y[selected[order[np.searchsorted(cumulative, cumulative[-1] / 2)]]])
        return np.asarray(output)


class WakeMixture:
    """Separate short returns from full wake windows, using past labels only."""
    def __init__(self, threshold=.5):
        self.threshold = threshold

    def fit(self, x, y):
        self.imputer = SimpleImputer(add_indicator=True, keep_empty_features=True)
        x = self.imputer.fit_transform(x)
        short = y <= 20
        self.short_probability = float(np.mean(short))
        self.classifier = None
        if len(np.unique(short)) == 2:
            self.classifier = HistGradientBoostingClassifier(max_iter=150, max_leaf_nodes=7,
                min_samples_leaf=12, l2_regularization=10, early_stopping=False, random_state=42).fit(x, short)
        self.regressors = []
        for selected in [short, ~short]:
            if np.sum(selected) >= 20:
                model = HistGradientBoostingRegressor(loss="absolute_error", max_iter=150,
                    max_leaf_nodes=7, min_samples_leaf=10, l2_regularization=10,
                    early_stopping=False, random_state=42).fit(x[selected], y[selected])
            else:
                model = float(np.median(y[selected])) if np.any(selected) else (5. if len(self.regressors) == 0 else 120.)
            self.regressors.append(model)
        return self

    def predict(self, x):
        x = self.imputer.transform(x)
        p = self.classifier.predict_proba(x)[:, 1] if self.classifier is not None else np.full(len(x), self.short_probability)
        components = [model.predict(x) if hasattr(model, "predict") else np.full(len(x), model) for model in self.regressors]
        return np.where(p >= self.threshold, components[0], components[1])


def run_candidate(name, data, fallback, lookback_days, refit_every, diagnostics=None, training_half_life_days=None):
    if training_half_life_days is not None and (training_half_life_days <= 0 or not name.startswith("hist_")):
        raise ValueError("Positive training half-life currently supports histogram boosting only")
    if name.startswith("clockPhase_"):
        return run_clock_phase(name, data, fallback, lookback_days, refit_every)
    if name.startswith("twoProcess"):
        return run_two_process(name, data, fallback, lookback_days, refit_every)
    if name.startswith("dailyPattern"):
        return run_daily_pattern(name, data, fallback, lookback_days)
    if name.startswith("hazard"):
        return run_hazard(name, data, fallback, lookback_days, refit_every)
    X, y, wakes, available = [data[k] for k in ["X", "y", "wakes", "available"]]
    if name.startswith("neural_") and not name.endswith("_compact"):
        X = np.column_stack([X, sequence_features(data)])
    sequential = name.startswith("sequence_")
    if (name.startswith(("density_", "gp_")) or sequential) and "names" in data:
        selected = ["ageDays", "clockSin1", "clockCos1", "lastDuration", "lastNight",
                    "wakeLag1", "napsToday", "sleepMinutes6h", "homeostat240_120"]
        X = X[:, [list(data["names"]).index(feature) for feature in selected]]
    predictions = fallback.copy()
    model, last_fit = None, -refit_every
    train_counts = np.zeros(len(y), dtype=int)
    with threadpool_limits(limits=1):
        for i, now in enumerate(wakes):
            train = np.flatnonzero((np.arange(len(y)) < i) & (available <= now) & (wakes >= now - lookback_days * 86400))
            if len(train) >= 40 and i - last_fit >= refit_every:
                model = candidate(name.replace("sequence_", "density_", 1) if sequential else name)
                if training_half_life_days is None:
                    model.fit(X[train], y[train])
                else:
                    weights = np.exp2(-(now - wakes[train]) / (training_half_life_days * 86400))
                    model.fit(X[train], y[train], histgradientboostingregressor__sample_weight=weights)
                if diagnostics is not None and hasattr(model, "optimization"):
                    diagnostics.append(model.optimization)
                if sequential:
                    states = model.posterior(X[train], y[train])
                    indices = np.asarray(data.get("indices", np.arange(len(y))))
                    adjacent = np.diff(indices[train]) == 1
                    transitions = states[:-1][adjacent].T @ states[1:][adjacent]
                    transitions += .5 * model.model.weights_[None, :]
                    transitions /= np.sum(transitions, axis=1, keepdims=True)
                last_fit = i
                train_counts[i] = len(train)
            if model is not None:
                if sequential:
                    # Filtering uses completed outcomes only; no backward smoothing.
                    history = train[-32:]
                    membership = model.posterior(X[history], y[history]) if len(history) else []
                    state = model.model.weights_.copy()
                    previous = None
                    for index, probability in zip(history, membership):
                        adjacent = previous is not None and indices[index] == indices[previous] + 1
                        prior = state @ transitions if adjacent else model.model.weights_
                        state = prior * np.maximum(probability, 1e-12) / model.model.weights_
                        state /= np.sum(state)
                        previous = index
                    prior = state @ transitions if previous is not None and indices[i] == indices[previous] + 1 else model.model.weights_
                    prediction = model.predict(X[i:i + 1], prior=prior)[0]
                else:
                    prediction = model.predict(X[i:i + 1])[0]
                predictions[i] = np.clip(prediction, 1, 480)
    return predictions, train_counts


def run_clock_phase(name, data, fallback, lookback_days, refit_every):
    """Predict a circular clock phase, then select the closest future minute."""
    x, y, wakes, available = [data[k] for k in ["X", "y", "wakes", "available"]]
    zone = ZoneInfo(str(data.get("zone", "UTC")))
    def phase(epoch):
        local = dt.datetime.fromtimestamp(float(epoch), zone)
        return (local.hour * 60 + local.minute + local.second / 60) * (2 * np.pi / 1440)
    actual_phase = np.array([phase(wake + gap * 60) for wake, gap in zip(wakes, y)])
    targets = np.column_stack([np.sin(actual_phase), np.cos(actual_phase)])
    predictions, counts = fallback.copy(), np.zeros(len(y), dtype=int)
    models, last_fit = None, -refit_every
    leaf = int(name.split("_")[1])
    with threadpool_limits(limits=1):
        for i, now in enumerate(wakes):
            train = np.flatnonzero((np.arange(len(y)) < i) & (available <= now) & (wakes >= now - lookback_days * 86400))
            if len(train) >= 40 and i - last_fit >= refit_every:
                models = [candidate("hist_squared_error_" + str(leaf) + "_10") for _ in range(2)]
                for k, model in enumerate(models):
                    model.fit(x[train], targets[train, k])
                last_fit = i
                counts[i] = len(train)
            if models is not None:
                vector = np.array([model.predict(x[i:i + 1])[0] for model in models])
                if np.linalg.norm(vector) >= .1:
                    future = np.array([phase(now + gap * 60) for gap in range(1, 481)])
                    distance = (np.sin(future) - vector[0]) ** 2 + (np.cos(future) - vector[1]) ** 2
                    predictions[i] = np.argmin(distance) + 1
    return predictions, counts


def wake_minutes(data):
    names, x = data["names"], data["X"]
    if "wakeMinute" in names:
        return x[:, names.index("wakeMinute")]
    return np.mod(np.arctan2(x[:, names.index("clockSin1")], x[:, names.index("clockCos1")]), 2 * np.pi) * 1440 / (2 * np.pi)


def two_process_bank(data):
    """Independent adaptation of published homeostatic/circadian equations.

    Wake: S(t)=1-(1-S0)*exp(-t/tau_w). Sleep decays exponentially.
    First future crossing of b+a*sin(clock+phase) predicts sleep onset.
    All wake states were assimilated from completed historical sleeps only.
    References and distinctions from the full neuronal model are in the README.
    """
    if "twoProcessBank" in data:
        return data["twoProcessBank"]
    names, x = data["names"], data["X"]
    minutes = wake_minutes(data)
    t = np.arange(1, 481)
    sinusoids = [(0., 0.)] + [(amplitude, phase) for amplitude in [.1, .2, .3] for phase in range(0, 1440, 180)]
    columns = []
    for awake_tau, sleep_tau in [(60, 30), (120, 60), (240, 120), (480, 240), (960, 480)]:
        key = f"homeostat{awake_tau}_{sleep_tau}"
        if key not in names:
            continue
        state = x[:, names.index(key)]
        future_state = 1 - (1 - state[:, None]) * np.exp(-t[None, :] / awake_tau)
        for amplitude, phase in sinusoids:
            difference = future_state - amplitude * np.sin(2 * np.pi * (minutes[:, None] + t[None, :] - phase) / 1440)
            for threshold in np.linspace(.1, .9, 17):
                crossed = difference >= threshold
                first = np.argmax(crossed, axis=1) + 1
                first[~np.any(crossed, axis=1)] = 480
                columns.append(first.astype(np.uint16))
    bank = np.column_stack(columns)
    data["twoProcessBank"] = bank
    return bank


def run_two_process(name, data, fallback, lookback_days, refit_every):
    bank = two_process_bank(data)
    y, wakes, available = [data[k] for k in ["y", "wakes", "available"]]
    predictions, counts = fallback.copy(), np.zeros(len(y), dtype=int)
    selected, last_fit = None, -refit_every
    clock = wake_minutes(data)
    for i, now in enumerate(wakes):
        train = np.flatnonzero((np.arange(len(y)) < i) & (available <= now) & (wakes >= now - lookback_days * 86400))
        if len(train) >= 40 and i - last_fit >= refit_every:
            weights = np.exp2(-(now - wakes[train]) / (14 * 86400))
            if name == "twoProcessLocal":
                distance = np.abs(clock[train] - clock[i])
                weights *= np.exp(-np.minimum(distance, 1440 - distance) / 120)
            errors = np.abs(bank[train].astype(float) - y[train, None])
            scores = np.average(errors, axis=0, weights=weights)
            selected = int(np.argmin(scores))
            counts[i], last_fit = len(train), i
        if selected is not None:
            predictions[i] = bank[i, selected]
    return predictions, counts


def run_daily_pattern(name, data, fallback, lookback_days):
    """NMF daily-onset-pattern adaptation; not the paper's population forecast.

    Fit only complete previous days. Infer the current day's coefficients from
    starts already observed, with a recent-coefficient prior. Gaussian smoothing
    of a future event must never enter the observed prefix.
    """
    tz = ZoneInfo(data["zone"])
    starts = data["sleeps"][:, 0]
    dates = [dt.datetime.fromtimestamp(t, tz).date() for t in starts]
    origin = min(dates)
    days = np.array([(d - origin).days for d in dates])
    minutes = np.array([dt.datetime.fromtimestamp(t, tz).hour * 60 + dt.datetime.fromtimestamp(t, tz).minute for t in starts])
    bins = 288
    daily = np.zeros((int(max(days)) + 1, bins))
    for day, minute in zip(days, minutes):
        daily[day, int(minute // 5)] += 1
    # This matrix is used only for completed-day training slices, never as the
    # partial current-day observation (which would leak backward smoothing).
    daily = gaussian_filter1d(daily, sigma=2, axis=1, mode="wrap")
    predictions, counts = fallback.copy(), np.zeros(len(fallback), dtype=int)
    basis, coefficients, last_fit_day = None, None, -7
    for i, now in enumerate(data["wakes"]):
        local = dt.datetime.fromtimestamp(now, tz)
        day = (local.date() - origin).days
        minute = local.hour * 60 + local.minute
        if day >= 14 and day - last_fit_day >= 7:
            training = daily[max(1, day - lookback_days):day]
            rank = min(5, len(training) - 1)
            if rank >= 2:
                model = NMF(n_components=rank, init="nndsvda", random_state=42, max_iter=250, tol=.001)
                with threadpool_limits(limits=1):
                    coefficients = model.fit_transform(training)
                basis = model.components_
                last_fit_day = day
                counts[i] = len(training)
        if basis is None:
            continue
        # Use an observed-onset vector assembled from known starts only.
        known = (days == day) & (starts <= now)
        observed = np.zeros(bins)
        for t in minutes[known]:
            observed[int(t // 5)] += 1
        observed = gaussian_filter1d(observed, sigma=2, mode="constant")
        prefix = min(bins, int(minute // 5) + 1)
        prior = np.mean(coefficients[-min(7, len(coefficients)):], axis=0)
        strength = 3.0
        design = np.vstack([basis[:, :prefix].T, np.sqrt(strength) * np.eye(len(prior))])
        target = np.concatenate([observed[:prefix], np.sqrt(strength) * prior])
        fitted, _ = nnls(design, target)
        curve = fitted @ basis
        forecast_minutes = np.arange(1, 481)
        future_bins = np.mod((minute + forecast_minutes) / 5, bins)
        density = np.interp(future_bins, np.arange(bins), curve, period=bins) / 5
        cumulative = np.cumsum(density)
        if cumulative[-1] >= .5:
            prediction = float(np.searchsorted(cumulative, .5) + 1)
        else:
            prediction = float(np.argmax(density) + 1)
        overnight = local.hour < 6 or local.hour >= 21
        if name != "dailyPatternDay" or not overnight:
            predictions[i] = prediction
    return predictions, counts


def hazard_features(x, elapsed, names):
    """Future features evolve deterministically from the forecast origin only."""
    if "wakeMinute" in names:
        clock = x[:, names.index("wakeMinute")]
    else:
        clock = np.mod(np.arctan2(x[:, names.index("clockSin1")], x[:, names.index("clockCos1")]), 2 * np.pi) * 1440 / (2 * np.pi)
    phase = 2 * np.pi * (clock + elapsed) / 1440
    extra = [elapsed, np.sin(phase), np.cos(phase)]
    for awake_tau, sleep_tau in [(120, 60), (240, 120)]:
        key = f"homeostat{awake_tau}_{sleep_tau}"
        if key in names:
            state = x[:, names.index(key)]
            extra.append(1 - (1 - state) * np.exp(-elapsed / awake_tau))
    return np.column_stack([x] + extra)


def run_hazard(name, data, fallback, lookback_days, refit_every):
    """Discrete-time next-event model; future care events never enter a curve."""
    x, y, wakes, available = [data[k] for k in ["X", "y", "wakes", "available"]]
    step = 5.
    grid = np.arange(0, 480, step) + step / 2
    exposure_x, exposure_y = [], []
    for row, value in zip(x, y):
        bins = max(1, min(len(grid), int(np.ceil(value / step))))
        exposure_x.append(hazard_features(np.repeat(row[None, :], bins, axis=0), grid[:bins], data["names"]))
        target = np.zeros(bins, dtype=int)
        if value <= 480:
            target[-1] = 1
        exposure_y.append(target)
    predictions, counts = fallback.copy(), np.zeros(len(y), dtype=int)
    model, last_fit = None, -refit_every
    with threadpool_limits(limits=1):
        for i, now in enumerate(wakes):
            train = np.flatnonzero((np.arange(len(y)) < i) & (available <= now) & (wakes >= now - lookback_days * 86400))
            if len(train) >= 40 and i - last_fit >= refit_every:
                tx = np.vstack([exposure_x[j] for j in train])
                ty = np.concatenate([exposure_y[j] for j in train])
                model = make_pipeline(SimpleImputer(add_indicator=True, keep_empty_features=True),
                    HistGradientBoostingClassifier(max_iter=150, max_leaf_nodes=15, min_samples_leaf=30,
                        l2_regularization=10, early_stopping=False, random_state=42)).fit(tx, ty)
                last_fit, counts[i] = i, len(train)
            if model is None:
                continue
            future = hazard_features(np.repeat(x[i:i + 1], len(grid), axis=0), grid, data["names"])
            hazard = np.clip(model.predict_proba(future)[:, 1], 1e-6, 1 - 1e-6)
            survival_before = np.concatenate([[1.], np.cumprod(1 - hazard[:-1])])
            mass = survival_before * hazard
            if name == "hazardMode":
                width = int(60 / step) + 1
                rolling = np.convolve(mass, np.ones(width), mode="same")
                predictions[i] = grid[int(np.argmax(rolling))]
            else:
                cdf = np.cumsum(mass)
                at = int(np.searchsorted(cdf, .5))
                predictions[i] = grid[min(at, len(grid) - 1)]
    return predictions, counts


def metrics(y, predictions, mask):
    errors = np.abs(y[mask] - predictions[mask])
    if not len(errors):
        return dict(count=0, mae=None, median=None, p90=None, within2=None, within15=None, within30=None)
    return dict(count=int(len(errors)), mae=float(np.mean(errors)), median=float(np.median(errors)),
                p90=float(np.quantile(errors, .9)), within2=float(np.mean(errors <= 2) * 100),
                within15=float(np.mean(errors <= 15) * 100), within30=float(np.mean(errors <= 30) * 100))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--birth-date", required=True)
    parser.add_argument("--time-zone", required=True)
    parser.add_argument("--baseline", type=Path, required=True, help="Full Swift replay JSON, same archive")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--models", nargs="+", default=["hist_absolute_error_7_10", "hist_absolute_error_15_10", "hist_squared_error_7_10", "extra_5", "extra_15", "svr_100", "ridge"])
    parser.add_argument("--lookback-days", type=int, default=60)
    parser.add_argument("--refit-every", type=int, default=24)
    parser.add_argument("--feature-set", choices=["complete", "compact"], default="complete")
    parser.add_argument("--care-exposure", choices=["completed", "started"], default="completed",
                        help="Started requires assuming timers were logged when started; completed matches the original replay")
    parser.add_argument("--feature-cache", type=Path, help="Optional private .npz cache for additional local experiments")
    parser.add_argument("--structured-context", action="store_true", help="Hash past completed conditions and locations; no notes or caregiver fields")
    parser.add_argument("--training-half-life-days", type=float, help="Recency weighting during histogram-boosting fitting, not just calibration")
    args = parser.parse_args()
    if args.lookback_days <= 0 or args.refit_every <= 0:
        parser.error("Lookback and refit intervals must be positive")
    if args.training_half_life_days is not None and (args.training_half_life_days <= 0 or any(not name.startswith("hist_") for name in args.models)):
        parser.error("Positive training half-life currently supports histogram boosting only")
    root = Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root):
        parser.error("Keep personal results outside the repository")
    sleeps, care, birth, tz = load_history(args.input, args.birth_date, args.time_zone)
    data = feature_rows(sleeps, care, birth, tz, include_started_care=args.care_exposure == "started")
    data["sleeps"] = sleeps
    data["zone"] = str(tz)
    if args.feature_set == "compact":
        selected = ["ageDays", "clockSin1", "clockCos1", "clockSin2", "clockCos2", "lastDuration", "lastNight",
                    "durationLag2", "wakeLag1", "wakeLag2", "wakeLag3", "napsToday", "sleepMinutesToday",
                    "episodeSpan", "episodeSegments", "wakeBeforeEpisode", "sleepMinutes6h", "sleepMinutes24h",
                    "homeostat120_60", "homeostat240_120", "lastFeedMinutes", "FeedCount3h",
                    "prior7d_clock_median", "prior7d_clock_shortFraction", "prior14d_kind_median"]
        positions = [data["names"].index(name) for name in selected]
        data["X"] = data["X"][:, positions]
        data["names"] = selected
    if args.structured_context:
        hashed = structured_features(read_structured_records(args.input, tz), data["wakes"])
        data["X"] = np.column_stack([data["X"], hashed])
        data["names"] += ["structuredLastSleep" + str(i) for i in range(64)] + ["structuredRecent" + str(i) for i in range(64)]
    if args.feature_cache:
        if args.feature_cache.resolve().is_relative_to(root):
            parser.error("Keep personal feature caches outside the repository")
        np.savez_compressed(args.feature_cache, **data)
    baseline = json.loads(args.baseline.read_text())
    expected = {r["index"]: r for r in baseline["events"]}
    assert set(data["indices"]) == set(expected), "Benchmark and Swift must score identical transitions"
    fallback = np.array([(expected[i]["prediction"] - data["wakes"][j]) / 60 for j, i in enumerate(data["indices"])])
    masks = {"all": np.ones(len(data["y"]), dtype=bool),
             "development": data["indices"] < int(len(sleeps) * .6),
             "validation": (data["indices"] >= int(len(sleeps) * .6)) & (data["indices"] < int(len(sleeps) * .8)),
             "finalPeriod": data["indices"] >= int(len(sleeps) * .8)}
    day = np.array([expected[i]["context"] == "daytime" for i in data["indices"]])
    masks.update({name + "Daytime": mask & day for name, mask in list(masks.items())})
    result = dict(audit=dict(sourceSHA256=hashlib.sha256(args.input.read_bytes()).hexdigest(),
        featureCount=len(data["names"]), featureSet=args.feature_set, careExposure=args.care_exposure,
        structuredContext=args.structured_context,
        trainingHalfLifeDays=args.training_half_life_days,
        lookbackDays=args.lookback_days, refitEvery=args.refit_every,
        scoredTransitions=len(data["y"]), rule="Features known at wake; chronological retraining; no random split; all transitions; Swift fallback during warmup"),
        featureNames=data["names"], models={"appV5": {k: metrics(data["y"], fallback, m) for k, m in masks.items()}}, events={})
    for name in args.models:
        started = time.monotonic()
        diagnostics = []
        predictions, train_counts = run_candidate(name, data, fallback, args.lookback_days, args.refit_every, diagnostics, args.training_half_life_days)
        result["models"][name] = {k: metrics(data["y"], predictions, m) for k, m in masks.items()}
        result["models"][name]["seconds"] = time.monotonic() - started
        result["models"][name]["refits"] = int(np.sum(train_counts > 0))
        if diagnostics:
            result["models"][name]["optimizationFits"] = diagnostics
            result["models"][name]["inputFeatureCount"] = diagnostics[0]["inputFeatureCount"]
        result["events"][name] = [dict(index=int(i), actual=float(y), prediction=float(p)) for i, y, p in zip(data["indices"], data["y"], predictions)]
        args.output.write_text(json.dumps(result, indent=2))
        print(name, json.dumps(result["models"][name]), flush=True)


if __name__ == "__main__":
    main()
