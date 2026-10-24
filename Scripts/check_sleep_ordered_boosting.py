#!/usr/bin/env python3
"""Native-library causal replay checks, separate from measured sleep accuracy."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from catboost import CatBoostRegressor
import catboost
from research_sleep_ordered_boosting import replay


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.resolve().is_relative_to(Path(__file__).resolve().parents[1]):
        parser.error("Keep aggregate research reports outside the repository")
    rng = np.random.default_rng(42)
    n = 100
    x = rng.normal(size=(n, 5))
    x[::5, 2] = np.nan
    wakes = np.arange(n) * 3600.
    data = dict(X=x, y=60 + 5 * x[:, 0], wakes=wakes, available=wakes + 600)
    data["available"][0] = wakes[-1] + 86400
    fallback = np.full(n, 60.)
    checks = []
    for scheme, loss, residual in [("Ordered", "MAE", False), ("Plain", "MAE", False),
                                   ("Ordered", "RMSE", False), ("Ordered", "MAE", True)]:
        for depth in [4, 6]:
            params = dict(iterations=400, learning_rate=.05, depth=depth, l2_leaf_reg=10,
                loss_function=loss, boosting_type=scheme, has_time=True, random_seed=42,
                thread_count=1, allow_writing_files=False, verbose=False)
            factory = lambda: CatBoostRegressor(**params)
            full, _ = replay(data, fallback, factory, residual)
            prefix = {k: v[:80] for k, v in data.items()}
            short, _ = replay(prefix, fallback[:80], factory, residual)
            np.testing.assert_array_equal(full[:80], short)
            alternate = dict(data, y=data["y"].copy())
            alternate["y"][0] = 10000
            changed, _ = replay(alternate, fallback, factory, residual)
            np.testing.assert_array_equal(full, changed)
            # The native default rejects constant targets; enable only for this
            # fixture. Real-history replay retains the recorded original flags.
            constant_factory = lambda: CatBoostRegressor(**params, allow_const_label=True)
            constant, _ = replay(dict(data, y=np.full(n, 60.)), fallback, constant_factory, residual)
            np.testing.assert_allclose(constant, 60, rtol=0, atol=1e-3)
            checks.append(dict(scheme=scheme, loss=loss, residual=residual, depth=depth,
                               prefix=True, unavailableLabelIsolation=True, constantAndMissing=True))
    result = dict(passed=True, version=catboost.__version__, checks=checks,
        replaySHA256=hashlib.sha256(Path(__file__).with_name("research_sleep_ordered_boosting.py").read_bytes()).hexdigest(),
        scope="Exact replay parameters for prefix/unavailable-label checks; constant fixture additionally enables allow_const_label; does not establish sleep accuracy")
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result))


if __name__ == "__main__":
    main()
