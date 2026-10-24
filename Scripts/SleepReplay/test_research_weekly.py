"""Calendar encoding and forecast availability checks with neutral examples."""
import datetime as dt
from pathlib import Path
import sys
import unittest
from zoneinfo import ZoneInfo

import numpy as np

sys.path.insert(0, str(Path(__file__).parents[1]))
from research_sleep_weekly import weekly_features
from research_sleep_regimes import run


class WeeklyTests(unittest.TestCase):
    def fixture(self):
        n = 120
        wakes = dt.datetime(2024, 3, 1, tzinfo=ZoneInfo("America/Los_Angeles")).timestamp() + np.arange(n) * 7200
        phase = np.resize([120, 480, 900], n) / 1440 * 2 * np.pi
        return dict(X=np.column_stack([np.arange(n), np.sin(phase), np.cos(phase), np.ones(n), np.zeros(n)]),
            names=np.array(["identifier", "clockSin1", "clockCos1", "lastNight", "napsToday"]),
            wakes=wakes, available=wakes + 600, y=np.full(n, 10.))

    def test_weekday_uses_local_calendar_across_dst(self):
        data = self.fixture()
        data["wakes"] = np.array([dt.datetime(2024, 3, 10, 7, 30, tzinfo=dt.timezone.utc).timestamp(),
            dt.datetime(2024, 3, 10, 10, 30, tzinfo=dt.timezone.utc).timestamp()])
        data["X"] = data["X"][:2]
        encoded = weekly_features(data, "America/Los_Angeles", "weekday")["X"][:, -7:]
        self.assertEqual(np.argmax(encoded[0]), 5)  # Saturday before the UTC/local date boundary.
        self.assertEqual(np.argmax(encoded[1]), 6)  # Sunday after spring-forward.
        np.testing.assert_array_equal(encoded.sum(axis=1), 1)

    def test_week_clock_wraps_continuously_at_monday(self):
        data = self.fixture()
        data["wakes"] = np.array([dt.datetime(2024, 3, 10, 23, 59, tzinfo=ZoneInfo("America/Los_Angeles")).timestamp(),
            dt.datetime(2024, 3, 11, 0, 0, tzinfo=ZoneInfo("America/Los_Angeles")).timestamp()])
        data["X"] = data["X"][:2]
        encoded = weekly_features(data, "America/Los_Angeles", "weeklyClock")["X"][:, -4:]
        self.assertLess(np.max(np.abs(encoded[0] - encoded[1])), .002)

    def test_features_and_fits_exclude_future_outcomes(self):
        data = self.fixture()
        data["available"][0] = data["wakes"][-1] + 86400
        class Model:
            def fit(self, x, y):
                self.value = float(np.median(y))
                return self
            def predict(self, x):
                return np.full(len(x), self.value)
        for encoding in ["weekday", "weeklyClock"]:
            encoded = weekly_features(data, "America/Los_Angeles", encoding)
            changed = dict(data, y=data["y"].copy())
            changed["y"][0] = 10000
            alternate = weekly_features(changed, "America/Los_Angeles", encoding)
            np.testing.assert_array_equal(encoded["X"], alternate["X"])
            first, _ = run(encoded, np.zeros(120), "previousKind", refit_every=1, model_factory=Model)
            second, _ = run(alternate, np.zeros(120), "previousKind", refit_every=1, model_factory=Model)
            np.testing.assert_array_equal(first, second)
            prefix = {k: v[:100] if k != "names" else v for k, v in data.items()}
            short = weekly_features(prefix, "America/Los_Angeles", encoding)
            np.testing.assert_array_equal(short["X"], encoded["X"][:100])
            prediction, _ = run(short, np.zeros(100), "previousKind", refit_every=1, model_factory=Model)
            np.testing.assert_array_equal(prediction, first[:100])


if __name__ == "__main__":
    unittest.main()
