import sys
from pathlib import Path
import unittest
import numpy as np

sys.path.insert(0, str(Path(__file__).parents[1]))
from research_sleep_grf import replay


class GRFReplayTests(unittest.TestCase):
    def fixture(self):
        n = 100
        wakes = np.arange(n, dtype=float) * 3600
        return dict(X=np.arange(n, dtype=float)[:, None], y=20 + np.arange(n),
            wakes=wakes, available=wakes + 600)

    def test_batched_fits_preserve_availability_and_prefix(self):
        data = self.fixture();data["available"][0] = data["wakes"][-1] + 86400
        trained = []
        def fitter(x, y, queries, method):
            trained.extend(x[:, 0].astype(int))
            point = float(np.median(y))
            return dict(predictions=[point] * len(queries), basePredictions=[], **{"lambda": .1})
        full, _, info = replay(data, np.full(100, 30.), np.zeros(100), "median", fitter)
        self.assertNotIn(0, trained)
        self.assertGreater(info["refits"], 0)
        alternate = dict(data, y=data["y"].copy());alternate["y"][0] = 10000
        changed, _, _ = replay(alternate, np.full(100, 30.), np.zeros(100), "median", fitter)
        prefix = {k: v[:80] for k, v in data.items()}
        short, _, _ = replay(prefix, np.full(80, 30.), np.zeros(80), "median", fitter)
        np.testing.assert_array_equal(full, changed)
        np.testing.assert_array_equal(full[:80], short)

    def test_nonfinite_predictions_keep_scored_fallback_and_count_failure(self):
        data = self.fixture()
        def fitter(x, y, queries, method):
            return dict(predictions=[None] * len(queries), basePredictions=[], **{"lambda": .1})
        full, _, info = replay(data, np.full(100, 30.), np.zeros(100), "median", fitter)
        np.testing.assert_array_equal(full, 30)
        self.assertEqual(info["unavailablePredictions"], 60)


if __name__ == "__main__":
    unittest.main()
