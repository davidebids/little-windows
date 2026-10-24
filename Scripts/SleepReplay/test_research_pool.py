"""Check diagnostic bounds on a fixed pool, not forecasting accuracy."""
import importlib.util
from pathlib import Path
import unittest
import sys

import numpy as np

sys.path.insert(0, str(Path(__file__).parents[1]))

spec = importlib.util.spec_from_file_location("sleep_pool", Path(__file__).parents[1] / "diagnose_sleep_model_pool.py")
pool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pool)


class ModelPoolTests(unittest.TestCase):
    def test_hindsight_blending_can_interpolate_but_not_escape_forecast_range(self):
        result = pool.diagnose(np.array([90., 50.]), np.array([[10., 20.], [40., 60.]]))
        self.assertEqual(result["perfectSelection"]["mae"], 40.)
        self.assertEqual(result["perfectConvexCombination"]["mae"], 35.)
        self.assertEqual(result["perfectConvexCombination"]["within30"], 50.)

    def test_nonfinite_predictions_cannot_silently_improve_the_bound(self):
        with self.assertRaises(ValueError):
            pool.diagnose(np.array([90.]), np.array([[float("nan")]]))


if __name__ == "__main__":
    unittest.main()
