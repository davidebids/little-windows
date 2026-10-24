import importlib.util
from pathlib import Path
import unittest
import sys

import numpy as np

sys.path.insert(0, str(Path(__file__).parents[1]))

spec = importlib.util.spec_from_file_location("sleep_ensemble", Path(__file__).parents[1] / "research_sleep_ensemble.py")
ensemble = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ensemble)


class EnsembleCausalityTests(unittest.TestCase):
    def fixture(self):
        size = 90
        clock = np.arange(size) % 24 * 60
        x = np.column_stack([np.sin(2 * np.pi * clock / 1440), np.cos(2 * np.pi * clock / 1440), np.full(size, 60.)])
        wakes = np.arange(size, dtype=float) * 3600
        data = dict(X=x, names=["clockSin1", "clockCos1", "lastDuration"],
                    y=np.full(size, 80.), wakes=wakes, available=wakes + 600)
        members = np.column_stack([np.full(size, 60.), np.full(size, 90.), np.full(size, 130.)])
        return data, members

    def test_unavailable_labels_cannot_change_calibration_or_selection(self):
        data, members = self.fixture()
        data["available"][0] = data["wakes"][-1] + 86400
        original = ensemble.combine(data, members)
        data["y"][0] = 10000
        changed = ensemble.combine(data, members)
        np.testing.assert_array_equal(original, changed)

    def test_future_forecasts_cannot_change_an_earlier_choice(self):
        data, members = self.fixture()
        original = ensemble.combine(data, members)
        members[60:] = 400
        changed = ensemble.combine(data, members)
        np.testing.assert_array_equal(original[:60], changed[:60])

    def test_appending_future_data_preserves_the_entire_prefix(self):
        data, members = self.fixture()
        original = ensemble.combine(data, members)
        prefix = {k: v[:50] if isinstance(v, np.ndarray) else v for k, v in data.items()}
        shortened = ensemble.combine(prefix, members[:50])
        np.testing.assert_array_equal(original[:50], shortened)

    def test_learned_stacking_excludes_unavailable_outcomes(self):
        data, members = self.fixture()
        data["available"][0] = data["wakes"][-1] + 86400
        original = ensemble.learned_combine(data, members)
        data["y"][0] = 10000
        changed = ensemble.learned_combine(data, members)
        np.testing.assert_array_equal(original, changed)

    def test_learned_stacking_preserves_prefix_without_future_features(self):
        data, members = self.fixture()
        original = ensemble.learned_combine(data, members)
        prefix = {k: v[:65] if isinstance(v, np.ndarray) else v for k, v in data.items()}
        shortened = ensemble.learned_combine(prefix, members[:65])
        np.testing.assert_array_equal(original[:65], shortened)
        data["X"][65:] = 10000
        members[65:] = 400
        changed = ensemble.learned_combine(data, members)
        np.testing.assert_array_equal(original[:65], changed[:65])

    def test_adaptive_windows_use_individual_history(self):
        data, _ = self.fixture()
        members = np.tile([20., 150.], (len(data["y"]), 1))
        data["y"][:] = 20.
        first = ensemble.adaptive_window_predictions(data, members)["adaptiveWindow"]
        data["y"][:] = 150.
        second = ensemble.adaptive_window_predictions(data, members)["adaptiveWindow"]
        self.assertEqual(first[-1], 20.)
        self.assertEqual(second[-1], 150.)

    def test_adaptive_windows_ignore_unavailable_labels_and_future_rows(self):
        data, members = self.fixture()
        data["available"][0] = data["wakes"][-1] + 86400
        original = ensemble.adaptive_window_predictions(data, members)
        data["y"][0] = 10000
        prefix = {k: v[:65] if isinstance(v, np.ndarray) else v for k, v in data.items()}
        shortened = ensemble.adaptive_window_predictions(prefix, members[:65])
        for name in original:
            np.testing.assert_array_equal(original[name][:65], shortened[name])

    def test_recent_routine_replaces_old_routine(self):
        data, _ = self.fixture()
        data["wakes"] *= 24
        data["available"] = data["wakes"] + 600
        data["y"][:] = 20.
        data["y"][55:] = 150.
        members = np.tile([20., 150.], (len(data["y"]), 1))
        prediction = ensemble.adaptive_window_predictions(data, members)["adaptiveWindow"]
        self.assertEqual(prediction[50], 20.)
        self.assertEqual(prediction[-1], 150.)


if __name__ == "__main__":
    unittest.main()
