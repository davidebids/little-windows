"""Paired comparisons must preserve pairing and the direction of improvements."""
import importlib.util
from pathlib import Path
import unittest

import numpy as np

spec = importlib.util.spec_from_file_location("sleep_uncertainty", Path(__file__).parents[1] / "summarize_sleep_uncertainty.py")
uncertainty = importlib.util.module_from_spec(spec)
spec.loader.exec_module(uncertainty)


class PairedUncertaintyTests(unittest.TestCase):
    def test_identical_forecasts_have_exactly_zero_paired_gain(self):
        actual, forecasts = np.array([10., 100., 30.]), np.array([20., 50., 80.])
        result = uncertainty.summarize(actual, forecasts, forecasts, ["day1", "day1", "day2"], 100)
        for key in ["maeImprovementMinutes", "within30ImprovementPercentagePoints"]:
            self.assertEqual(result["metrics"][key]["estimate"], 0.)
            self.assertEqual(result["metrics"][key]["interval95"], [0., 0.])

    def test_improvement_sign_and_cohort_weighting(self):
        actual = np.array([10., 20., 30.])
        result = uncertainty.summarize(actual, actual, actual + [60., 60., 0.], ["day1", "day1", "day2"], 100)
        self.assertEqual(result["metrics"]["maeImprovementMinutes"]["estimate"], 40.)
        self.assertAlmostEqual(result["metrics"]["within30ImprovementPercentagePoints"]["estimate"], 200 / 3)


if __name__ == "__main__":
    unittest.main()
