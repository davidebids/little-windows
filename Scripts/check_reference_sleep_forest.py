#!/usr/bin/env python3
"""Compare native random-split trees with the installed research library.

Synthetic checks are always run. Optional private caches add historical fit
snapshots; only aggregate comparisons survive the temporary workspace.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import numpy as np
import sklearn
from sklearn.ensemble import ExtraTreesRegressor
from sklearn.impute import SimpleImputer
from research_sleep_predictions import WakeAnalogs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--features", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--trees", type=int, default=80)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root):
        parser.error("Keep history-derived reports outside the repository")
    rng = np.random.default_rng(42)
    x = rng.normal(size=(120, 9))
    x[:, 1] = 1
    x[:, 2] = np.nan
    x[::7, 3] = np.nan
    y = np.round(20 + 15 * x[:, 0] + 5 * x[:, 4] ** 2, 1)
    cases = [("synthetic", x, y, x[:12])]
    cases.append(("constantTarget", x, np.full(len(y), 10.), x[:12]))
    if args.features:
        data = dict(np.load(args.features, allow_pickle=False))
        for i in [40, 400, 800, 1400, len(data["y"]) - 1]:
            now = data["wakes"][i]
            known = np.flatnonzero((np.arange(len(data["y"])) < i) & (data["available"] <= now) & (data["wakes"] >= now - 60 * 86400))
            cases.append(("historicalFit" + str(i), data["X"][known], data["y"][known], data["X"][max(0, i - 3):i + 1]))
    sources = [root / "LittleWindows/Services/ReferenceSleepForest.swift", root / "Scripts/SleepReplay/ReferenceForestReplay.swift"]
    checks = []
    with tempfile.TemporaryDirectory(prefix="lw-reference-forest-") as folder:
        folder = Path(folder)
        subprocess.run(["xcrun", "swiftc", "-O", "-parse-as-library", "-module-cache-path", str(folder / "cache"),
            *map(str, sources), "-o", str(folder / "forest")], check=True)
        for name, x, y, query in cases:
            imputer = SimpleImputer(keep_empty_features=True).fit(x)
            model = ExtraTreesRegressor(n_estimators=args.trees, min_samples_leaf=5, max_features=.8,
                random_state=42, n_jobs=1).fit(imputer.transform(x), y)
            payload = dict(x=[[float(v) if np.isfinite(v) else None for v in row] for row in x],
                y=y.tolist(), query=[[float(v) if np.isfinite(v) else None for v in row] for row in query], trees=args.trees)
            (folder / "input.json").write_text(json.dumps(payload))
            subprocess.run([str(folder / "forest"), str(folder / "input.json"), str(folder / "output.json")], check=True)
            native = json.loads((folder / "output.json").read_text())
            seeds = np.random.RandomState(42).randint(np.iinfo(np.int32).max, size=args.trees).tolist()
            assert native["seeds"] == seeds, "Forest random seeds differ"
            differences = []
            for k, (tree, nodes) in enumerate(zip(model.estimators_, native["trees"])):
                expected = tree.tree_
                if len(nodes) != expected.node_count:
                    differences.append(dict(tree=k, reason="nodeCount", expected=int(expected.node_count), actual=len(nodes)))
                    continue
                training_leaves = tree.apply(imputer.transform(x).astype(np.float32))
                for j, node in enumerate(nodes):
                    if node["feature"] != expected.feature[j] or node["left"] != expected.children_left[j] or node["right"] != expected.children_right[j] or abs(node["threshold"] - expected.threshold[j]) > 1e-10:
                        differences.append(dict(tree=k, node=j, reason="split", expectedFeature=int(expected.feature[j]), actualFeature=node["feature"], thresholdDifference=float(node["threshold"] - expected.threshold[j])))
                        break
                    if node["count"] != expected.n_node_samples[j] or abs(node["mean"] - expected.value[j, 0, 0]) > 1e-8:
                        differences.append(dict(tree=k, node=j, reason="nodeStatistics"))
                        break
                    if node["feature"] < 0:
                        if sorted(node["members"]) != np.flatnonzero(training_leaves == j).tolist():
                            differences.append(dict(tree=k, node=j, reason="leafMembers"))
                            break
            leaves = model.apply(imputer.transform(query))
            leaf_mismatches = int(np.sum(leaves != np.array(native["leaves"])))
            analog = WakeAnalogs("forest", 5).fit(x, y)
            # WakeAnalogs always fits 80 trees, so point parity uses its full setting.
            point_difference = None if args.trees != 80 else float(np.max(np.abs(analog.predict(query) - native["predictions"])))
            check = dict(case=name, rows=len(x), trees=args.trees, differentTrees=len(differences),
                leafMismatches=leaf_mismatches, maximumPointDifference=point_difference, examples=differences[:4])
            checks.append(check)
            print(json.dumps(check), flush=True)
    result = dict(passed=all(c["differentTrees"] == 0 and c["leafMismatches"] == 0 and (c["maximumPointDifference"] is None or c["maximumPointDifference"] <= 1e-6) for c in checks),
        checks=checks, libraryVersion=sklearn.__version__, sourceFilesSHA256={p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
        scope="Native tree/leaf/point comparisons for selected fit snapshots, not a full chronological replay")
    args.output.write_text(json.dumps(result, indent=2))
    assert result["passed"], "Reference forest mismatch"


if __name__ == "__main__":
    main()
