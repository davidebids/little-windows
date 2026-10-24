import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0, str(Path(__file__).parents[1]))
from research_sleep_sequence_prior import CONTEXT_NAMES, query_at, replay, decision_points


class SequencePriorTests(unittest.TestCase):
    def fixture(self):
        n = 90
        return dict(y=np.arange(n, dtype=float), wakes=np.arange(n) * 3600.,
            available=np.arange(n) * 3600. + 600,
            X=np.repeat(np.arange(n, dtype=float)[:, None], len(CONTEXT_NAMES), axis=1), names=CONTEXT_NAMES)

    def test_query_omits_unavailable_targets_and_only_exposes_current_covariates(self):
        d = self.fixture();d["available"][55] = 1e10
        q = query_at(d, 60, 48, True)
        self.assertNotIn(55, q["target"])
        self.assertNotIn(60, q["target"])
        np.testing.assert_array_equal(q["future_covariates"]["ageDays"], [60])
        alternate = dict(d, y=d["y"].copy());alternate["y"][[55, 60]] = 10000
        np.testing.assert_array_equal(q["target"], query_at(alternate, 60, 48, True)["target"])

    def test_replay_prefix_and_missing_label_are_isolated(self):
        d = self.fixture();d["available"][0] = 1e10
        def predictor(query, length):
            return np.full(9, np.median(query["target"]))
        levels = np.arange(1, 10) / 10
        configs = [("test", 128, True)]
        full, _ = replay(d, np.full(90, 60.), predictor, levels, configs)
        prefix = {k: v[:70] if k != "names" else v for k, v in d.items()}
        short, _ = replay(prefix, np.full(70, 60.), predictor, levels, configs)
        alternate = dict(d, y=d["y"].copy());alternate["y"][0] = 10000
        changed, _ = replay(alternate, np.full(90, 60.), predictor, levels, configs)
        for name in full:
            np.testing.assert_array_equal(full[name][:70], short[name])
            np.testing.assert_array_equal(full[name], changed[name])

    def test_distribution_decision_handles_bimodality_and_invalid_predictions(self):
        levels = np.arange(1, 10) / 10
        points, crossed = decision_points([10, 10, 10, 10, 70, 130, 130, 130, 130], levels)
        self.assertEqual(points["median"], 70)
        self.assertIn(points["risk"], [40, 100])
        self.assertEqual(crossed, 0)
        with self.assertRaises(ValueError):
            decision_points(np.full(9, np.nan), levels)
