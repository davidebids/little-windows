#!/usr/bin/env python3
"""Ablate the residual-correction cap while holding forecast inputs fixed."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np

from research_sleep_ensemble import combine, metrics


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["source", "features", "baseline", "members", "incumbent", "output"]:
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root):
        parser.error("Keep history-derived results outside the repository")
    baseline, members, incumbent = [json.loads(p.read_text()) for p in [args.baseline, args.members, args.incumbent]]
    source_hash = hashlib.sha256(args.source.read_bytes()).hexdigest()
    assert all(r["audit"]["sourceSHA256"] == source_hash for r in [baseline, members, incumbent])
    data = dict(np.load(args.features, allow_pickle=False))
    indices = data["indices"].astype(int).tolist()
    base = {r["index"]: r for r in baseline["events"]}
    current = {r["index"]: r for r in incumbent["events"]}
    assert set(indices) == set(base) == set(current)
    np.testing.assert_allclose([base[i]["actual"] for i in indices], data["available"], rtol=0, atol=1e-6)
    np.testing.assert_allclose([base[i]["wakeMinutes"] for i in indices], data["y"], rtol=0, atol=1e-6)
    assert list(members["events"]) == ["specialist_" + k for k in ["previousKind", "wakePhase", "cycleStage"]]
    experts = [(np.array([base[i]["prediction"] for i in indices]) - data["wakes"]) / 60]
    for rows in members["events"].values():
        by_index = {r["index"]: r for r in rows}
        assert set(indices) == set(by_index)
        np.testing.assert_allclose([by_index[i]["actual"] for i in indices], data["y"], rtol=0, atol=1e-6)
        experts.append(np.array([by_index[i]["prediction"] for i in indices]))
    experts = np.column_stack(experts)
    current_points = (np.array([current[i]["prediction"] for i in indices]) - data["wakes"]) / 60
    np.testing.assert_allclose(combine(data, experts, policy="best"), current_points, rtol=0, atol=1e-6)
    result = dict(audit=dict(sourceSHA256=source_hash, careExposure="completed", featureCount=len(data["names"]),
        modelFamily="correction-cap ablation", lookbackDays=30, halfLifeDays=10, toleranceMinutes=30,
        baselineResultSHA256=hashlib.sha256(args.baseline.read_bytes()).hexdigest(),
        memberResultSHA256=hashlib.sha256(args.members.read_bytes()).hexdigest(),
        incumbentResultSHA256=hashlib.sha256(args.incumbent.read_bytes()).hexdigest(),
        featureCacheSHA256=hashlib.sha256(args.features.read_bytes()).hexdigest(),
        defaultControlMatchesIncumbent=True,
        rule="Only past residual-correction amplitude changes; issued experts and fixed 30-minute scoring tolerance remain unchanged"),
        models={}, events={})
    mask = np.ones(len(indices), dtype=bool)
    for cap in [60, 120, None]:
        for policy in ["best", "soft", "median"]:
            name = "correction" + (str(cap) if cap is not None else "Unbounded") + "_" + policy
            prediction = combine(data, experts, policy=policy, correction_limit=cap)
            result["models"][name] = dict(all=metrics(data["y"], prediction, mask), correctionLimit=cap, policy=policy)
            result["events"][name] = [dict(index=i, actual=float(y), prediction=float(p)) for i, y, p in zip(indices, data["y"], prediction)]
            args.output.write_text(json.dumps(result, indent=2) + "\n")
            print(name, json.dumps(result["models"][name]), flush=True)


if __name__ == "__main__":
    main()
