#!/usr/bin/env python3
"""Check the external GRF bridge on analytic and query-isolation examples."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from research_sleep_grf import native_fit, plans


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--nonhonest", action="store_true")
    parser.add_argument("--features", type=Path, help="Optional external cache for real-history query-prefix checks")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root):
        parser.error("Keep aggregate research reports outside the repository")
    build = json.loads((args.build / "build-check.json").read_text())
    binary = args.build / "replay"
    assert build["passed"] and hashlib.sha256(binary.read_bytes()).hexdigest() == build["binarySHA256"]
    assert hashlib.sha256((root / "Scripts/SleepReplay/GRFReplay.cpp").read_bytes()).hexdigest() == build["bridgeSHA256"]
    checks = []
    x = np.column_stack([np.ones(80), np.zeros(80), np.full(80, np.nan)])
    for method in ["median", "ll_standard", "ll_residual"]:
        r = native_fit(binary, x, np.full(80, 60.), x[:2], method, honesty=not args.nonhonest)
        np.testing.assert_allclose(r["predictions"], 60, rtol=0, atol=1e-6)
        assert r["nonfiniteQueryCount"] == 0
        checks.append(dict(case="constantAndMissing", method=method, passed=True))
    rng = np.random.default_rng(42)
    x = rng.normal(size=(120, 4))
    y = 80 + 5 * x[:, 0] - 4 * x[:, 1]
    queries = np.array([[0., 0., 0., 0.], [2., -1., .5, .5]])
    expected = 80 + 5 * queries[:, 0] - 4 * queries[:, 1]
    for method in ["ll_standard", "ll_residual"]:
        r = native_fit(binary, x, y, queries, method, honesty=not args.nonhonest)
        difference = float(np.max(np.abs(np.array(r["predictions"]) - expected)))
        assert difference <= .05, (method, difference)
        checks.append(dict(case="analyticLine", method=method, maximumDifference=difference, passed=True))
    for method in ["median", "ll_standard", "ll_residual"]:
        short = native_fit(binary, x, y, queries[:1], method, honesty=not args.nonhonest)
        longer = native_fit(binary, x, y, np.vstack([queries, np.full((1, 4), 1000.)]), method, honesty=not args.nonhonest)
        np.testing.assert_allclose(short["predictions"], longer["predictions"][:1], rtol=0, atol=1e-8)
        assert short["lambda"] == longer["lambda"]
        checks.append(dict(case="futureQueryIsolation", method=method, passed=True))
    cache_hash = None
    if args.features:
        data = dict(np.load(args.features, allow_pickle=False))
        schedule = plans(data, np.zeros(len(data["y"]), dtype=int))
        assert schedule
        middle = schedule[len(schedule) // 2]
        train, query = middle["train"], np.array(middle["queries"][:3])
        assert len(query) > 1
        for method in ["median", "ll_standard", "ll_residual"]:
            short = native_fit(binary, data["X"][train], data["y"][train], data["X"][query[:1]], method,
                honesty=not args.nonhonest)
            longer = native_fit(binary, data["X"][train], data["y"][train], data["X"][query], method,
                honesty=not args.nonhonest)
            assert short["nonfiniteQueryCount"] == longer["nonfiniteQueryCount"] == 0
            np.testing.assert_allclose(short["predictions"], longer["predictions"][:1], rtol=0, atol=1e-8)
            assert short["lambda"] == longer["lambda"]
            checks.append(dict(case="archiveQueryPrefix", method=method, fitPosition=int(middle["index"]), passed=True))
        cache_hash = hashlib.sha256(args.features.read_bytes()).hexdigest()
    result = dict(passed=True, upstreamBuild=build, trees=2000, honesty=not args.nonhonest, checks=checks,
        featureCacheSHA256=cache_hash,
        scope="Authors' core tests plus neutral bridge/layout/analytic/query-isolation checks; sleep accuracy is evaluated separately")
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
