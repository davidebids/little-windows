"""Synthetic checks for conditional distribution decisions and availability."""
import sys
from pathlib import Path
import unittest
import numpy as np

sys.path.insert(0, str(Path(__file__).parents[1]))
from research_sleep_distribution import ConditionalWakeDistribution, point_estimates, run


class DistributionTests(unittest.TestCase):
    def test_fixed_tolerance_decision_matches_exhaustive_candidate_search(self):
        rng = np.random.default_rng(42)
        for _ in range(30):
            values = rng.integers(1, 240, 30).astype(float)
            weights = rng.random(30)
            median, mode = point_estimates(values, weights)
            candidates = np.r_[values - 30, values + 30, median]
            masses = [np.sum(weights[np.abs(values - p) <= 30 + 1e-9]) for p in candidates]
            achieved = np.sum(weights[np.abs(values - mode) <= 30 + 1e-9])
            self.assertAlmostEqual(achieved, max(masses), places=9)
            self.assertGreaterEqual(mode, np.min(values) - 30)
            self.assertLessEqual(mode, np.max(values) + 30)

    def test_distribution_weights_retain_small_and_long_support(self):
        self.assertEqual(point_estimates([5, 10, 100, 120], [.3, .3, .2, .2])[0], 10)
        self.assertEqual(point_estimates([5, 10, 100, 120], [.2, .2, .3, .3])[0], 100)
        self.assertEqual(point_estimates([5, 5, 100], [.25, .25, .5])[0], 5)
        with self.assertRaises(ValueError):
            point_estimates([1, 2], [-1, 2])

    def test_single_class_and_empty_feature_columns_are_finite(self):
        x = np.column_stack([np.ones(50), np.full(50, np.nan)])
        for y in [np.full(50, 5.), np.full(50, 120.)]:
            model = ConditionalWakeDistribution().fit(x, y)
            prediction = model.predict(x[:2])
            np.testing.assert_allclose(prediction, np.full((2, 2), y[0]))

    def test_unavailable_targets_and_future_rows_do_not_change_issued_forecast(self):
        n = 100
        data = dict(X=np.arange(n, dtype=float)[:, None], y=np.arange(n, dtype=float),
            wakes=np.arange(n, dtype=float) * 3600, available=np.arange(n, dtype=float) * 3600 + 600)
        data["available"][0] = data["wakes"][-1] + 86400
        fitted = []
        class Spy:
            def fit(self, x, y):
                fitted.extend(x[:, 0].astype(int))
                self.value = float(np.median(y))
                return self
            def predict(self, x):
                return np.full((len(x), 2), self.value)
        first, _ = run(data, np.zeros(n), "forest", model_factory=Spy)
        alternate = dict(data, y=data["y"].copy())
        alternate["y"][0] = 1e8
        second, _ = run(alternate, np.zeros(n), "forest", model_factory=Spy)
        np.testing.assert_array_equal(first, second)
        self.assertTrue(fitted)
        self.assertNotIn(0, fitted)
        prefix = {k: v[:80] for k, v in data.items()}
        shortened, _ = run(prefix, np.zeros(80), "forest", model_factory=Spy)
        np.testing.assert_array_equal(shortened, first[:80])


if __name__ == "__main__":
    unittest.main()
