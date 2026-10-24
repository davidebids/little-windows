import sys
from pathlib import Path
import unittest
import numpy as np

sys.path.insert(0, str(Path(__file__).parents[1]))
from research_sleep_convex import fit_weights, replay


class ConvexForecastTests(unittest.TestCase):
    def test_complementary_experts_and_baseline_regularization(self):
        members = np.tile([40., 80.], (50, 1))
        beta = fit_weights(members, np.full(50, 60.), np.ones(50))
        np.testing.assert_allclose(beta, [.5, .5], atol=1e-8)
        np.testing.assert_allclose(fit_weights(members, np.full(50, 60.), np.ones(50), 100), [1, 0], atol=1e-8)
        with self.assertRaises(ValueError):
            fit_weights(members, np.full(50, 60.), np.zeros(50))

    def test_prefix_and_unavailable_labels_remain_excluded(self):
        n = 70
        wakes = np.arange(n) * 3600.
        data = dict(X=np.column_stack([np.zeros(n), np.ones(n), np.full(n, 60.)]),
            names=["clockSin1", "clockCos1", "lastDuration"], y=np.full(n, 60.),
            wakes=wakes, available=wakes + 600)
        data["available"][0] = wakes[-1] + 86400
        members = np.tile([40., 80.], (n, 1))
        for local in [False, True]:
            full, fits = replay(data, members, local=local)
            self.assertGreater(fits, 0)
            alternate = dict(data, y=data["y"].copy())
            alternate["y"][0] = 10000
            changed, _ = replay(alternate, members, local=local)
            prefix = {k: v[:55] if k != "names" else v for k, v in data.items()}
            shortened, _ = replay(prefix, members[:55], local=local)
            np.testing.assert_array_equal(full, changed)
            np.testing.assert_array_equal(full[:55], shortened)
