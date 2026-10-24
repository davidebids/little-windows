import sys
from pathlib import Path
import unittest
import numpy as np

sys.path.insert(0, str(Path(__file__).parents[1]))
from research_sleep_tabular_prior import replay


class TabularPriorReplayTests(unittest.TestCase):
    def fixture(self):
        n = 100
        wakes = np.arange(n) * 3600.
        return dict(X=np.arange(n, dtype=float)[:, None], y=np.arange(n) + 30.,
                    wakes=wakes, available=wakes + 600)

    def test_single_queries_resolved_labels_and_prefix(self):
        data = self.fixture()
        data["available"][0] = data["wakes"][-1] + 86400
        seen = []
        class Model:
            def fit(self, x, y):
                seen.extend(x[:, 0].astype(int))
                self.point = float(np.median(y))
            def predict(self, x, output_type):
                self_outer.assertEqual(x.shape[0], 1)
                return {k: [self.point] for k in ["mean", "median", "mode"]}
        self_outer = self
        fallback = np.full(100, 30.)
        full, fits = replay(data, fallback, Model)
        self.assertGreater(fits, 0)
        self.assertNotIn(0, seen)
        alternate = dict(data, y=data["y"].copy())
        alternate["y"][0] = 10000
        changed, _ = replay(alternate, fallback, Model)
        prefix, _ = replay({k: v[:80] for k, v in data.items()}, fallback[:80], Model)
        for name in full:
            np.testing.assert_array_equal(full[name], changed[name])
            np.testing.assert_array_equal(full[name][:80], prefix[name])

    def test_nonfinite_output_fails_without_dropping_a_case(self):
        class Model:
            def fit(self, x, y):
                pass
            def predict(self, x, output_type):
                return {k: [np.nan] for k in ["mean", "median", "mode"]}
        with self.assertRaises(ValueError):
            replay(self.fixture(), np.full(100, 30.), Model)

    def test_short_history_expires_old_labels_and_requires_support(self):
        data = self.fixture()
        snapshots = []
        class Model:
            def fit(self, x, y):
                snapshots.append(x[:, 0].astype(int))
            def predict(self, x, output_type):
                return {k: [60.] for k in ["mean", "median", "mode"]}
        fallback = np.full(100, 30.)
        outputs, fits = replay(data, fallback, Model, lookback_days=1)
        self.assertEqual(fits, 0)
        for point in outputs.values():
            np.testing.assert_array_equal(point, fallback)
        replay(data, fallback, Model, lookback_days=3)
        # Last fit is at position 88: the 72-hour history starts at row 16.
        self.assertEqual(min(snapshots[-1]), 16)
        self.assertEqual(max(snapshots[-1]), 87)
        for invalid in [0, -1, np.inf]:
            with self.assertRaises(ValueError):
                replay(data, fallback, Model, lookback_days=invalid)
