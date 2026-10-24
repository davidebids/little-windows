import sys
from pathlib import Path
import unittest
import numpy as np

sys.path.insert(0, str(Path(__file__).parents[1]))
from research_sleep_ensemble import combine


class CorrectionLimitTests(unittest.TestCase):
    def fixture(self):
        n = 50
        wakes = np.arange(n, dtype=float) * 3600
        return dict(X=np.column_stack([np.zeros(n), np.ones(n), np.full(n, 60.)]),
            names=["clockSin1", "clockCos1", "lastDuration"], y=np.full(n, 180.),
            wakes=wakes, available=wakes + 600), np.full((n, 4), 60.)

    def test_larger_cap_changes_correction_but_not_tolerance_definition(self):
        data, members = self.fixture()
        self.assertEqual(combine(data, members, policy="best")[-1], 90)
        self.assertEqual(combine(data, members, policy="best", correction_limit=60)[-1], 120)
        self.assertEqual(combine(data, members, policy="best", correction_limit=None)[-1], 180)
        for invalid in [-1, np.inf, np.nan]:
            with self.assertRaises(ValueError):
                combine(data, members, correction_limit=invalid)

    def test_unavailable_outcomes_and_future_rows_remain_excluded(self):
        data, members = self.fixture()
        data["available"][0] = data["wakes"][-1] + 86400
        alternate = dict(data, y=data["y"].copy())
        alternate["y"][0] = 10000
        prefix = {k: v[:40] if k != "names" else v for k, v in data.items()}
        for cap in [60, 120, None]:
            for policy in ["best", "soft", "median"]:
                full = combine(data, members, policy=policy, correction_limit=cap)
                np.testing.assert_array_equal(full, combine(alternate, members, policy=policy, correction_limit=cap))
                np.testing.assert_array_equal(full[:40], combine(prefix, members[:40], policy=policy, correction_limit=cap))


if __name__ == "__main__":
    unittest.main()
