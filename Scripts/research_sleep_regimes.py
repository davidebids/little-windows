#!/usr/bin/env python3
"""Compare wake-context specialists with an already-issued app forecast.

Only the preceding sleep kind, wake clock, and completed nap count choose the
specialist. The next sleep's kind, duration, and target gap never choose it.
Private feature caches and per-event outputs must stay outside the repository.
"""
import argparse
import hashlib
import json
from pathlib import Path
import time
import subprocess
import tempfile

import numpy as np
from threadpoolctl import threadpool_limits

from research_sleep_predictions import WakeAnalogs, metrics


def regimes(data, policy):
    x, names = data["X"], list(data["names"])
    night = x[:, names.index("lastNight")] > .5
    if policy == "previousKind":
        return night.astype(int)
    clock = np.mod(np.arctan2(x[:, names.index("clockSin1")],
                              x[:, names.index("clockCos1")]), 2 * np.pi) * 1440 / (2 * np.pi)
    overnight = (clock < 360) | (clock >= 1260)
    if policy == "wakePhase":
        return np.where(overnight, 0, np.where(night, 1, 2))
    if policy == "cycleStage":
        naps = x[:, names.index("napsToday")]
        return np.where(overnight, 0, np.where(night, 1, np.where(naps < 2, 2, 3)))
    raise ValueError("Unknown specialist policy")


def run(data, fallback, policy, lookback_days=60, refit_every=24, model_factory=None):
    if min(lookback_days, refit_every) <= 0:
        raise ValueError("Positive lookback and refit cadence required")
    x, y, wakes, available = [data[k] for k in ["X", "y", "wakes", "available"]]
    groups = regimes(data, policy)
    predictions, counts = fallback.copy(), np.zeros(len(y), dtype=int)
    models, fitted_at = {}, {}
    factory = model_factory or (lambda: WakeAnalogs("forest", 5))
    with threadpool_limits(limits=1):
        for i, now in enumerate(wakes):
            group = int(groups[i])
            train = np.flatnonzero((np.arange(len(y)) < i) & (available <= now) &
                (wakes >= now - lookback_days * 86400) & (groups == group))
            if len(train) >= 40 and i - fitted_at.get(group, -refit_every) >= refit_every:
                models[group] = factory().fit(x[train], y[train])
                fitted_at[group] = i
                counts[i] = len(train)
            if group in models:
                predictions[i] = models[group].predict(x[i:i + 1])[0]
    return predictions, counts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--features", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--native", action="store_true", help="Use the actual Swift forest instead of the library forest")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root):
        parser.error("Keep personal results outside the repository")
    baseline = json.loads(args.baseline.read_text())
    source_hash = hashlib.sha256(args.source.read_bytes()).hexdigest()
    assert baseline["audit"]["sourceSHA256"] == source_hash
    data = dict(np.load(args.features, allow_pickle=False))
    expected = {r["index"]: r for r in baseline["events"]}
    assert set(expected) == set(data["indices"])
    np.testing.assert_allclose([expected[int(i)]["actual"] for i in data["indices"]], data["available"], rtol=0, atol=1e-6)
    np.testing.assert_allclose([expected[int(i)]["wakeMinutes"] for i in data["indices"]], data["y"], rtol=0, atol=1e-6)
    np.testing.assert_allclose(data["available"] - data["wakes"], data["y"] * 60, rtol=0, atol=1e-6)
    fallback = np.array([(expected[int(index)]["prediction"] - wake) / 60
                         for index, wake in zip(data["indices"], data["wakes"])])
    all_rows = np.ones(len(fallback), dtype=bool)
    output = dict(audit=dict(sourceSHA256=source_hash, careExposure="completed", featureCount=len(data["names"]),
        lookbackDays=60, refitEvery=24, fallbackAlgorithm=baseline["algorithm"],
        modelFamily="native" if args.native else "library",
        rule="Causal context selects group; 40 available within-group labels required; all transitions scored"),
        models={}, events={}, baselineDiagnostics={})
    workspace = tempfile.TemporaryDirectory(prefix="lw-sleep-specialists-")
    folder = Path(workspace.name)
    if args.native:
        subprocess.run(["xcrun", "swiftc", "-O", "-parse-as-library", "-module-cache-path", str(folder / "cache"),
            str(root / "LittleWindows/Services/PortableSleepForest.swift"),
            str(root / "Scripts/SleepReplay/RegimeReplay.swift"), "-o", str(folder / "replay")], check=True)
    for policy in ["previousKind", "wakePhase", "cycleStage"]:
        groups = regimes(data, policy)
        output["baselineDiagnostics"][policy] = {str(g): metrics(data["y"], fallback, groups == g) for g in np.unique(groups)}
        started = time.monotonic()
        if args.native:
            payload = dict(x=[[float(v) if np.isfinite(v) else None for v in row] for row in data["X"]],
                y=data["y"].tolist(), wakes=data["wakes"].tolist(), available=data["available"].tolist(),
                groups=groups.tolist(), fallback=fallback.tolist(), lookbackDays=60, refitEvery=24)
            (folder / "input.json").write_text(json.dumps(payload))
            subprocess.run([str(folder / "replay"), str(folder / "input.json"), str(folder / "output.json")], check=True)
            native = json.loads((folder / "output.json").read_text())
            prediction, counts = np.array(native["predictions"]), np.array(native["trainingCounts"])
        else:
            prediction, counts = run(data, fallback, policy)
        name = ("nativeSpecialist_" if args.native else "specialist_") + policy
        output["models"][name] = dict(all=metrics(data["y"], prediction, all_rows),
            refits=int(np.sum(counts > 0)), seconds=time.monotonic() - started,
            byGroup={str(g): metrics(data["y"], prediction, groups == g) for g in np.unique(groups)})
        output["events"][name] = [dict(index=int(i), actual=float(y), prediction=float(p))
            for i, y, p in zip(data["indices"], data["y"], prediction)]
        args.output.write_text(json.dumps(output, indent=2))
        print(name, json.dumps(output["models"][name]), flush=True)
    workspace.cleanup()


if __name__ == "__main__":
    main()
