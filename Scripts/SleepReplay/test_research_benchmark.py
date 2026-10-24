"""Synthetic causality checks for the research benchmark; no personal fixtures."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
from zoneinfo import ZoneInfo

import numpy as np

spec = importlib.util.spec_from_file_location("sleep_research", Path(__file__).parents[1] / "research_sleep_predictions.py")
research = importlib.util.module_from_spec(spec)
spec.loader.exec_module(research)


class ResearchCausalityTests(unittest.TestCase):
    def fixture(self):
        origin = 1_735_689_600.0
        sleeps = np.array([[origin + i * 10800, origin + i * 10800 + 3600, float(i % 3 == 0)] for i in range(18)])
        care = [(origin + 2000, origin + 2300, "Feed"), (origin + 130000, origin + 130500, "Bath")]
        return sleeps, care, origin - 100 * 86400, ZoneInfo("UTC")

    def test_feature_is_invariant_to_future_rows(self):
        sleeps, care, birth, zone = self.fixture()
        full = research.feature_rows(sleeps, care, birth, zone)
        prefix = research.feature_rows(sleeps[:9], care[:1], birth, zone)
        self.assertEqual(full["names"], prefix["names"])
        np.testing.assert_allclose(full["X"][:8], prefix["X"], equal_nan=True)

    def test_next_sleep_target_and_duration_do_not_enter_current_features(self):
        sleeps, care, birth, zone = self.fixture()
        original = research.feature_rows(sleeps, care, birth, zone)
        changed = sleeps.copy()
        changed[8, 0] += 600
        changed[8, 1] += 1800
        changed[8, 2] = 1 - changed[8, 2]
        alternate = research.feature_rows(changed, care, birth, zone)
        index = np.flatnonzero(original["indices"] == 7)[0]
        np.testing.assert_allclose(original["X"][index], alternate["X"][index], equal_nan=True)
        self.assertEqual(alternate["y"][index] - original["y"][index], 10)

    def test_training_excludes_labels_not_yet_available(self):
        size = 90
        wakes = np.arange(size, dtype=float) * 3600
        available = wakes + 600
        available[0] = wakes[-1] + 86400
        data = dict(X=np.arange(size, dtype=float).reshape(-1, 1), y=np.arange(size, dtype=float), wakes=wakes, available=available)
        trained_indices = []
        class Spy:
            def fit(self, x, y):
                trained_indices.extend(x[:, 0].astype(int).tolist())
                self.center = float(np.mean(y))
            def predict(self, x):
                return np.full(len(x), self.center)
        with patch.object(research, "candidate", lambda _: Spy()):
            first, _ = research.run_candidate("spy", data, np.ones(size), 60, 1)
            data["y"][0] = 10000
            second, _ = research.run_candidate("spy", data, np.ones(size), 60, 1)
        self.assertTrue(trained_indices)
        self.assertNotIn(0, trained_indices)
        np.testing.assert_array_equal(first, second)

    def test_active_care_exposes_elapsed_time_not_future_duration(self):
        sleeps, care, birth, zone = self.fixture()
        now = sleeps[7, 1]
        first = research.feature_rows(sleeps, care + [(now - 120, now + 300, "Feed")], birth, zone, include_started_care=True)
        second = research.feature_rows(sleeps, care + [(now - 120, now + 1800, "Feed")], birth, zone, include_started_care=True)
        row = np.flatnonzero(first["indices"] == 7)[0]
        np.testing.assert_allclose(first["X"][row], second["X"][row], equal_nan=True)
        self.assertEqual(first["X"][row, first["names"].index("FeedRunningElapsed")], 2)

    def test_daily_pattern_never_smooths_future_start_into_observed_prefix(self):
        origin = 1_735_689_600.0
        sleeps = np.array([[origin + day * 86400 + hour * 3600,
                            origin + day * 86400 + hour * 3600 + 1800, 0.]
                           for day in range(30) for hour in [1, 4, 10, 14, 20]])
        now = origin + 15 * 86400 + 10.5 * 3600
        first = dict(sleeps=sleeps, wakes=np.array([now]), zone="UTC")
        alternate = sleeps.copy()
        index = 15 * 5 + 3
        alternate[index, 0] = now + 300
        alternate[index, 1] = now + 2100
        second = dict(sleeps=alternate, wakes=np.array([now]), zone="UTC")
        a, _ = research.run_daily_pattern("dailyPattern", first, np.array([120.]), 60)
        b, _ = research.run_daily_pattern("dailyPattern", second, np.array([120.]), 60)
        np.testing.assert_array_equal(a, b)

    def test_hazard_training_excludes_unavailable_event_time(self):
        size = 70
        wakes = np.arange(size, dtype=float) * 3600
        available = wakes + 600
        available[0] = wakes[-1] + 86400
        data = dict(X=np.column_stack([np.arange(size), np.full(size, .5), np.full(size, .5)]),
                    names=["wakeMinute", "homeostat120_60", "homeostat240_120"],
                    y=np.full(size, 90.), wakes=wakes, available=available)
        trained = []
        class Spy:
            def fit(self, x, y):
                trained.extend(x[:, 0].astype(int).tolist())
                self.p = (float(np.sum(y)) + 1) / (len(y) + 2)
                return self
            def predict_proba(self, x):
                return np.tile([1 - self.p, self.p], (len(x), 1))
        with patch.object(research, "make_pipeline", lambda *args: Spy()):
            first, _ = research.run_hazard("hazardMedian", data, np.full(size, 120.), 60, 12)
            data["y"][0] = 1
            second, _ = research.run_hazard("hazardMedian", data, np.full(size, 120.), 60, 12)
        self.assertTrue(trained)
        self.assertNotIn(0, trained)
        np.testing.assert_array_equal(first, second)

    def test_fitted_analogs_preserve_prefix_and_exclude_unavailable_outcomes(self):
        size = 90
        wakes = np.arange(size, dtype=float) * 3600
        data = dict(X=np.column_stack([np.arange(size) % 7, np.sin(np.arange(size))]),
                    y=20. + np.arange(size) % 11 * 10,
                    wakes=wakes, available=wakes + 600)
        data["available"][0] = wakes[-1] + 86400
        for method in ["uniform", "metric", "forest"]:
            with self.subTest(method=method):
                first, _ = research.run_candidate("analog_" + method + "_5", data, np.full(size, 60.), 60, 24)
                alternate = {k: v[:65].copy() for k, v in data.items()}
                alternate["y"][0] = 10000
                second, _ = research.run_candidate("analog_" + method + "_5", alternate, np.full(65, 60.), 60, 24)
                np.testing.assert_array_equal(first[:65], second)

    def test_conditional_density_preserves_prefix_and_excludes_unavailable_outcomes(self):
        size = 90
        wakes = np.arange(size, dtype=float) * 3600
        data = dict(X=np.column_stack([np.arange(size) % 7, np.sin(np.arange(size))]),
                    y=20. + np.arange(size) % 11 * 10,
                    wakes=wakes, available=wakes + 600)
        data["available"][0] = wakes[-1] + 86400
        for model in ["density_3_log", "density_3_raw", "sequence_3_log", "sequence_3_raw"]:
            with self.subTest(model=model):
                first, _ = research.run_candidate(model, data, np.full(size, 60.), 60, 24)
                alternate = {k: v[:65].copy() for k, v in data.items()}
                alternate["y"][0] = 10000
                second, _ = research.run_candidate(model, alternate, np.full(65, 60.), 60, 24)
                np.testing.assert_array_equal(first[:65], second)

    def test_structured_features_exclude_future_and_running_records(self):
        records = [dict(Type="Sleep", startEpoch=0., endEpoch=60., **{"Start Condition": "asleep"}),
                   dict(Type="Feed", startEpoch=90., endEpoch=180., **{"End Condition": "finished"}),
                   dict(Type="Sleep", startEpoch=180., endEpoch=240., **{"Start Location": "cot"})]
        first = research.structured_features(records, np.array([120.]))
        records[1]["End Condition"] = "changed unavailable outcome"
        records[2]["Start Location"] = "changed future category"
        second = research.structured_features(records, np.array([120.]))
        np.testing.assert_array_equal(first, second)
        prefix = research.structured_features(records[:1], np.array([120.]))
        np.testing.assert_array_equal(first, prefix)

    def test_structured_features_ignore_notes_and_caregiver_fields(self):
        records = [dict(Type="Sleep", startEpoch=0., endEpoch=60., **{"Start Condition": "asleep"})]
        first = research.structured_features(records, np.array([120.]))
        records[0].update({"Notes": "neutral test note", "Logged By": "Test Caregiver"})
        np.testing.assert_array_equal(first, research.structured_features(records, np.array([120.])))

    def test_transformed_targets_preserve_prefix_and_exclude_unavailable_outcomes(self):
        size = 90
        wakes = np.arange(size, dtype=float) * 3600
        data = dict(X=np.column_stack([np.arange(size) % 7, np.sin(np.arange(size))]),
                    y=20. + np.arange(size) % 11 * 10,
                    wakes=wakes, available=wakes + 600, zone="America/Los_Angeles")
        data["available"][0] = wakes[-1] + 86400
        for name in ["loghist_7", "clockPhase_7", "gp_rbf_log", "gp_matern_raw"]:
            with self.subTest(model=name):
                first, _ = research.run_candidate(name, data, np.full(size, 60.), 60, 24)
                prefix = {k: v[:65].copy() if isinstance(v, np.ndarray) else v for k, v in data.items()}
                prefix["y"][0] = 10000
                second, _ = research.run_candidate(name, prefix, np.full(65, 60.), 60, 24)
                np.testing.assert_array_equal(first[:65], second)

    def sequence_fixture(self):
        size = 90
        clock = np.arange(size) % 24 * 60
        wakes = np.arange(size, dtype=float) * 3600
        data = dict(X=np.column_stack([np.full(size, 60.), np.sin(clock * 2 * np.pi / 1440), np.cos(clock * 2 * np.pi / 1440)]),
                    names=["lastDuration", "clockSin1", "clockCos1"],
                    y=20. + np.arange(size) % 11 * 10, wakes=wakes, available=wakes + 600)
        data["available"][0] = wakes[-1] + 86400
        return data

    def test_ordered_history_features_exclude_unavailable_and_future_outcomes(self):
        data = self.sequence_fixture()
        first = research.sequence_features(data)
        data["y"][0] = 10000
        prefix = {k: v[:65].copy() if isinstance(v, np.ndarray) else v for k, v in data.items()}
        np.testing.assert_allclose(first[:65], research.sequence_features(prefix), equal_nan=True)

    def test_neural_fitting_preserves_prefix_and_excludes_unavailable_outcomes(self):
        data = self.sequence_fixture()
        for name in ["neural_huber_16", "neural_squared_16", "neural_huber_16_compact"]:
            with self.subTest(model=name):
                first, _ = research.run_candidate(name, data, np.full(90, 60.), 60, 24)
                prefix = {k: v[:65].copy() if isinstance(v, np.ndarray) else v for k, v in data.items()}
                prefix["y"][0] = 10000
                second, _ = research.run_candidate(name, prefix, np.full(65, 60.), 60, 24)
                np.testing.assert_array_equal(first[:65], second)

    def test_neural_training_gradient_matches_finite_differences(self):
        rng = np.random.default_rng(42)
        x, y, theta = rng.normal(size=(5, 2)), rng.normal(size=5), rng.normal(size=13) * .2
        for loss in ["huber", "squared"]:
            with self.subTest(loss=loss):
                _, analytic = research.WakeNeural.objective(theta, x, y, 3, .01, loss)
                numeric = []
                for k in range(len(theta)):
                    plus, minus = theta.copy(), theta.copy()
                    plus[k] += 1e-6
                    minus[k] -= 1e-6
                    numeric.append((research.WakeNeural.objective(plus, x, y, 3, .01, loss)[0] -
                                    research.WakeNeural.objective(minus, x, y, 3, .01, loss)[0]) / 2e-6)
                np.testing.assert_allclose(analytic, numeric, atol=1e-7, rtol=1e-5)

    def test_base_training_recency_weights_preserve_label_availability(self):
        size = 90
        wakes = np.arange(size, dtype=float) * 3600
        data = dict(X=np.arange(size, dtype=float).reshape(-1, 1), y=np.arange(size, dtype=float),
                    wakes=wakes, available=wakes + 600)
        data["available"][0] = wakes[-1] + 86400
        fitted = []
        class Spy:
            def fit(self, x, y, **kwargs):
                weights = kwargs["histgradientboostingregressor__sample_weight"]
                fitted.append((x[:, 0].copy(), weights.copy()))
                self.center = np.average(y, weights=weights)
            def predict(self, x):
                return np.full(len(x), self.center)
        with patch.object(research, "candidate", lambda _: Spy()):
            first, _ = research.run_candidate("hist_spy", data, np.full(size, 60.), 60, 24, training_half_life_days=7)
            data["y"][0] = 10000
            second, _ = research.run_candidate("hist_spy", data, np.full(size, 60.), 60, 24, training_half_life_days=7)
        np.testing.assert_array_equal(first, second)
        self.assertTrue(fitted)
        for indices, weights in fitted:
            self.assertNotIn(0, indices)
            self.assertTrue(np.all(np.diff(weights) > 0))

    def test_portable_forest_preserves_prefix_and_unavailable_label_boundary(self):
        data = self.sequence_fixture()
        first, _ = research.run_candidate("portable_10_5", data, np.full(90, 60.), 60, 24)
        prefix = {k: v[:65].copy() if isinstance(v, np.ndarray) else v for k, v in data.items()}
        prefix["y"][0] = 10000
        second, _ = research.run_candidate("portable_10_5", prefix, np.full(65, 60.), 60, 24)
        np.testing.assert_array_equal(first[:65], second)

    def test_portable_forest_uses_median_and_stable_lower_tie(self):
        x = np.column_stack([np.zeros(14), np.full(14, np.nan)])
        y = np.array([10.] * 7 + [20.] * 7)
        model = research.PortableForest(40, 5).fit(x, y)
        np.testing.assert_array_equal(model.predict(np.array([[0., np.nan]])), [10.])


if __name__ == "__main__":
    unittest.main()
