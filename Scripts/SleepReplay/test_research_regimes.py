"""Specialist model causality checks, with synthetic data only."""
import sys
from pathlib import Path
import unittest
import numpy as np

sys.path.insert(0, str(Path(__file__).parents[1]))
from research_sleep_regimes import regimes, run


class SpecialistTests(unittest.TestCase):
    def fixture(self):
        n = 120
        clock = np.resize([120, 480, 900], n) / 1440 * 2 * np.pi
        x = np.column_stack([np.arange(n), np.resize([1, 1, 0], n), np.sin(clock), np.cos(clock), np.resize([0, 0, 2], n)])
        wakes = np.arange(n, dtype=float) * 3600
        return dict(X=x, y=np.arange(n, dtype=float), wakes=wakes, available=wakes + 600,
            names=["identifier", "lastNight", "clockSin1", "clockCos1", "napsToday"])

    def test_gate_uses_no_future_target(self):
        data = self.fixture()
        for policy in ["previousKind", "wakePhase", "cycleStage"]:
            expected = regimes(data, policy)
            alternate = dict(data, y=data["y"] + 10000, available=data["available"] + 1e8)
            np.testing.assert_array_equal(expected, regimes(alternate, policy))

    def test_unavailable_labels_and_future_rows_do_not_change_forecasts(self):
        data = self.fixture()
        data["available"][0] = data["wakes"][-1] + 86400
        fitted = []
        class Model:
            def fit(self, x, y):
                fitted.extend(x[:, 0].astype(int))
                self.value = float(np.median(y))
                return self
            def predict(self, x):
                return np.full(len(x), self.value)
        first, _ = run(data, np.zeros(120), "previousKind", refit_every=1, model_factory=Model)
        alternate = dict(data, y=data["y"].copy())
        alternate["y"][0] = 10000
        second, _ = run(alternate, np.zeros(120), "previousKind", refit_every=1, model_factory=Model)
        np.testing.assert_array_equal(first, second)
        self.assertTrue(fitted)
        self.assertNotIn(0, fitted)
        prefix = {k: v[:100] if k != "names" else v for k, v in data.items()}
        shortened, _ = run(prefix, np.zeros(100), "previousKind", refit_every=1, model_factory=Model)
        np.testing.assert_array_equal(shortened, first[:100])


if __name__ == "__main__":
    unittest.main()
