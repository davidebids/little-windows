import sys
from pathlib import Path
import unittest
import numpy as np

sys.path.insert(0, str(Path(__file__).parents[1]))
from research_sleep_local_regression import LocalForestRegression
from research_sleep_regimes import run


class LocalRegressionTests(unittest.TestCase):
    def test_local_line_can_extrapolate_smooth_known_trend(self):
        x = np.arange(1., 51.)[:, None]
        y = 15 + 3 * x[:, 0]
        for loss, penalty in [("mean", 1e-8), ("median", 1e-4)]:
            model = LocalForestRegression([0], loss=loss, penalty=penalty).fit(x, y)
            self.assertAlmostEqual(model.predict(np.array([[55.]]))[0], 180, places=2)
            self.assertEqual(model.solver_failures, 0)

    def test_missing_constant_columns_and_median_outlier(self):
        for invalid in [0, -1, np.nan, np.inf]:
            with self.assertRaises(ValueError):
                LocalForestRegression([0], penalty=invalid)
        x = np.column_stack([np.ones(21), np.full(21, np.nan)])
        y = np.full(21, 20.); y[-1] = 400
        median = LocalForestRegression([0, 1], loss="median", penalty=.1).fit(x, y)
        mean = LocalForestRegression([0, 1], loss="mean", penalty=1).fit(x, y)
        self.assertAlmostEqual(median.predict(x[:1])[0], 20)
        self.assertAlmostEqual(mean.predict(x[:1])[0], np.mean(y))

    def test_unavailable_target_and_prefix_invariance(self):
        n = 65
        wakes = np.arange(n, dtype=float) * 3600
        x = np.column_stack([np.arange(n), np.zeros(n), np.ones(n), np.ones(n), np.zeros(n)])
        data = dict(X=x, names=["identifier", "clockSin1", "clockCos1", "lastNight", "napsToday"],
            y=20 + np.arange(n), wakes=wakes, available=wakes + 600)
        data["available"][0] = wakes[-1] + 86400
        alternate = dict(data, y=data["y"].copy());alternate["y"][0] = 10000
        prefix = {k: v[:60] if k != "names" else v for k, v in data.items()}
        for loss in ["mean", "median"]:
            def factory():return LocalForestRegression([0], loss=loss, penalty=.1)
            full, _ = run(data, np.full(n, 30.), "previousKind", model_factory=factory)
            changed, _ = run(alternate, np.full(n, 30.), "previousKind", model_factory=factory)
            short, _ = run(prefix, np.full(60, 30.), "previousKind", model_factory=factory)
            np.testing.assert_allclose(full, changed, rtol=0, atol=1e-8)
            np.testing.assert_allclose(full[:60], short, rtol=0, atol=1e-8)


if __name__ == "__main__":
    unittest.main()
