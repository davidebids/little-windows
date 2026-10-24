import sys
from pathlib import Path
import unittest
import numpy as np

sys.path.insert(0, str(Path(__file__).parents[1]))
from research_sleep_ordered_boosting import replay


class OrderedReplayTests(unittest.TestCase):
    def test_resolved_label_filter_and_prefix_for_direct_and_residual(self):
        n = 100
        wakes = np.arange(n, dtype=float) * 3600
        data = dict(X=np.arange(n, dtype=float)[:, None], y=np.arange(n) + 30.,
                    wakes=wakes, available=wakes + 600)
        data["available"][0] = wakes[-1] + 86400
        seen = []
        class Model:
            def fit(self, x, y, sample_weight):
                seen.extend(x[:, 0].astype(int))
                self.point = float(np.average(y, weights=sample_weight))
            def predict(self, x):
                return np.full(len(x), self.point)
        fallback = np.linspace(20, 60, n)
        for residual in [False, True]:
            full, fits = replay(data, fallback, Model, residual)
            self.assertGreater(fits, 0)
            self.assertNotIn(0, seen)
            alternate = dict(data, y=data["y"].copy())
            alternate["y"][0] = 10000
            np.testing.assert_array_equal(full, replay(alternate, fallback, Model, residual)[0])
            prefix = {k: v[:80] for k, v in data.items()}
            np.testing.assert_array_equal(full[:80], replay(prefix, fallback[:80], Model, residual)[0])

    def test_nonfinite_output_is_a_failure(self):
        n = 50
        class Model:
            def fit(self, *args, **kwargs):
                pass
            def predict(self, x):
                return [np.nan]
        data = dict(X=np.zeros((n, 1)), y=np.ones(n), wakes=np.arange(n) * 3600.,
                    available=np.arange(n) * 3600. + 60)
        with self.assertRaises(ValueError):
            replay(data, np.ones(n), Model)
