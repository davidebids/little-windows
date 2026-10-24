#!/usr/bin/env python3
"""Past-only constrained median regression over originally issued forecasts."""
import argparse
import hashlib
import json
from pathlib import Path
import time
import numpy as np
from scipy.optimize import linprog
from scipy import sparse
from research_sleep_ensemble import metrics
from sleep_research_metadata import care_exposure


def fit_weights(members, actual, weights, regularization=0):
    """Minimize weighted absolute error plus L1 distance to the first expert."""
    members, actual, weights = [np.asarray(v, dtype=float) for v in [members, actual, weights]]
    if members.ndim != 2 or members.shape[0] != len(actual) or weights.shape != actual.shape:
        raise ValueError("Expected aligned forecasts, outcomes and observation weights")
    if not members.shape[1] or not len(actual) or not all(np.isfinite(v).all() for v in [members, actual, weights]):
        raise ValueError("Expected finite nonempty inputs")
    if np.any(weights < 0) or weights.sum() <= 0 or not np.isfinite(regularization) or regularization < 0:
        raise ValueError("Expected nonnegative weights and regularization")
    n, k = members.shape
    # On the simplex, ||beta - e_0||_1 = 2 * sum(beta[1:]).
    cost = np.r_[0., np.full(k - 1, 2 * regularization), weights / weights.sum()]
    error = -sparse.eye(n, format="csr")
    constraints = sparse.vstack([sparse.hstack([members, error]), sparse.hstack([-members, error])], format="csr")
    equality = sparse.csr_matrix(np.r_[np.ones(k), np.zeros(n)][None, :])
    solution = linprog(cost, A_ub=constraints, b_ub=np.r_[actual, -actual],
        A_eq=equality, b_eq=[1.], bounds=[(0, 1)] * k + [(0, None)] * n, method="highs")
    if not solution.success:
        raise ValueError("Convex fit failed: " + solution.message)
    beta = solution.x[:k]
    if not np.isfinite(beta).all() or np.min(beta) < -1e-8 or abs(beta.sum() - 1) > 1e-8:
        raise ValueError("Invalid convex weights")
    beta = np.maximum(beta, 0)
    return beta / beta.sum()


def replay(data, members, days=30, local=False, regularization=0):
    y, wakes, available = [data[k] for k in ["y", "wakes", "available"]]
    names = list(data["names"])
    clock = np.mod(np.arctan2(data["X"][:, names.index("clockSin1")],
                             data["X"][:, names.index("clockCos1")]), 2 * np.pi) * 1440 / (2 * np.pi)
    duration = data["X"][:, names.index("lastDuration")]
    output = members[:, 0].copy()
    fits = 0
    for i, now in enumerate(wakes):
        train = np.flatnonzero((np.arange(len(y)) < i) & (available <= now) & (wakes >= now - days * 86400))
        if len(train) < 40:
            continue
        weights = np.exp2(-(now - wakes[train]) / ((10 if days == 30 else 14) * 86400))
        if local:
            distance = np.abs(clock[train] - clock[i])
            context = np.exp(-np.minimum(distance, 1440 - distance) / 120)
            context *= np.exp(-np.abs(np.log((duration[train] + 10) / (duration[i] + 10))) / .7)
            candidate = weights * context
            if candidate.sum() ** 2 / max(1e-12, candidate @ candidate) >= 8:
                weights = candidate
        beta = fit_weights(members[train], y[train], weights, regularization)
        output[i] = np.clip(members[i] @ beta, 1, 480)
        fits += 1
    return output, fits


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["features", "baseline", "members", "output"]:
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    if args.output.resolve().is_relative_to(Path(__file__).resolve().parents[1]):
        parser.error("Keep history-derived results outside the repository")
    data = dict(np.load(args.features, allow_pickle=False))
    base, selected = [json.loads(p.read_text()) for p in [args.baseline, args.members]]
    assert base["audit"]["sourceSHA256"] == selected["audit"]["sourceSHA256"] and care_exposure(selected) == "completed"
    indices = data["indices"].astype(int).tolist()
    rows = {r["index"]: r for r in base["events"]}
    assert set(rows) == set(indices)
    np.testing.assert_allclose([rows[i]["actual"] for i in indices], data["available"], rtol=0, atol=1e-6)
    np.testing.assert_allclose([rows[i]["wakeMinutes"] for i in indices], data["y"], rtol=0, atol=1e-6)
    members = [(np.array([rows[i]["prediction"] for i in indices]) - data["wakes"]) / 60]
    for events in selected["events"].values():
        by = {r["index"]: r for r in events}
        assert set(by) == set(indices)
        np.testing.assert_allclose([by[i]["actual"] for i in indices], data["y"], rtol=0, atol=1e-6)
        members.append(np.array([by[i]["prediction"] for i in indices]))
    members = np.column_stack(members)
    result = dict(audit=dict(sourceSHA256=base["audit"]["sourceSHA256"], careExposure="completed",
        featureCacheSHA256=hashlib.sha256(args.features.read_bytes()).hexdigest(),
        baselineResultSHA256=hashlib.sha256(args.baseline.read_bytes()).hexdigest(),
        membersResultSHA256=hashlib.sha256(args.members.read_bytes()).hexdigest(),
        scriptSHA256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        members=[base.get("algorithm", "appBaseline"), *selected["events"]],
        selection=selected["audit"].get("selection"), minimumLabels=40,
        objective="Weighted median regression with nonnegative simplex weights; optional L1 shrinkage toward issued app forecast",
        sourceURL="https://arxiv.org/abs/1803.06730",
        adaptation="Median/point version; rolling recency/context weighting and baseline shrinkage are research extensions, not an infant-specific published result"), models={}, events={})
    for days in [30, 60]:
        for local in [False, True]:
            for regularization in [0., 1.]:
                started = time.monotonic()
                prediction, fits = replay(data, members, days, local, regularization)
                name = f"convex_d{days}_{'local' if local else 'global'}_r{regularization:g}"
                result["models"][name] = dict(all=metrics(data["y"], prediction, np.ones(len(indices), dtype=bool)),
                    fits=fits, days=days, local=local, regularization=regularization, seconds=time.monotonic() - started)
                result["events"][name] = [dict(index=i, actual=float(y), prediction=float(p))
                    for i, y, p in zip(indices, data["y"], prediction)]
                args.output.write_text(json.dumps(result, indent=2) + "\n")
                print(name, json.dumps(result["models"][name]), flush=True)


if __name__ == "__main__":
    main()
