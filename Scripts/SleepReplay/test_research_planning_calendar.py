import datetime as dt
import sys
from pathlib import Path
import unittest

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_calendar import replay
from research_sleep_weekly import weekly_features


class Probe:
    def __init__(self, records):
        self.records = records
    def fit(self, x, y):
        self.records.append((x.copy(), y.copy()))
        self.value = float(np.mean(y))
        return self
    def predict(self, x):
        assert len(x) == 1
        return np.array([self.value])


def fixture(n=55):
    origin = dt.datetime(2026, 1, 1, tzinfo=dt.timezone.utc).timestamp()
    data = dict(X=np.zeros((n, 2)), names=np.array(['a', 'b']),
                wakes=origin + np.arange(n)*86400, y=30.+np.arange(n))
    context = dict(X=np.zeros((n, 11)), knownAt=data['wakes']+3600, labels=np.ones(n), wakeClock=np.zeros(n))
    return data, context, np.full(n, 120.)


class CalendarTests(unittest.TestCase):
    def test_local_calendar_and_dst(self):
        # UTC Monday is still Sunday before Pacific midnight; DST uses local time.
        wakes = np.array([dt.datetime(2026, 3, 9, 6, 30, tzinfo=dt.timezone.utc).timestamp(),
                          dt.datetime(2026, 3, 9, 7, 30, tzinfo=dt.timezone.utc).timestamp()])
        d = dict(X=np.zeros((2, 1)), names=np.array(['x']), wakes=wakes)
        onehot = weekly_features(d, 'America/Los_Angeles', 'weekday')['X'][:, 1:]
        np.testing.assert_array_equal(onehot, np.eye(7)[[6, 0]])
        phase = 2*np.pi*np.array([6*1440+1410, 30])/(7*1440)
        expected = np.column_stack([np.sin(phase), np.cos(phase), np.sin(2*phase), np.cos(2*phase)])
        np.testing.assert_allclose(weekly_features(d, 'America/Los_Angeles', 'weeklyClock')['X'][:, 1:], expected, rtol=0, atol=1e-14)

    def test_real_maturity_expiry_and_early_refits(self):
        d, c, b = fixture(90)
        c['knownAt'][1] = d['wakes'][12]  # Earlier origin, unresolved until later.
        c['labels'][2] = 0
        d['y'][3] = 20  # Brief return is not a planning label.
        records = []
        out, diag = replay(d, c, b, factory=lambda: Probe(records))
        self.assertEqual(diag['refits'][0], dict(query=6, labels=3))
        np.testing.assert_array_equal(records[0][1], d['y'][[0, 4, 5]])
        self.assertNotIn(d['y'][1], records[0][1])
        self.assertTrue(all(x['query'] < y['query'] for x, y in zip(diag['refits'], diag['refits'][1:])))
        for _, targets in records[-3:]:
            self.assertNotIn(d['y'][0], targets)  # Expired after 60 days.
        np.testing.assert_array_equal(out['calendarWeekday'][:6], b[:6])
        self.assertEqual(diag['featureCounts'], dict(planningForestControl=5, calendarWeekday=12, calendarWeeklyClock=9))

    def test_future_rows_and_current_target_do_not_change_issued_point(self):
        d, c, b = fixture()
        records = []
        full, diag = replay(d, c, b, factory=lambda: Probe(records))
        cut = 37
        ds = {k: v[:cut] if len(v) == len(b) else v for k, v in d.items()}
        cs = {k: v[:cut] for k, v in c.items()}
        prefix, pd = replay(ds, cs, b[:cut], factory=lambda: Probe([]))
        for name in full:
            np.testing.assert_array_equal(full[name][:cut], prefix[name])
        self.assertEqual([x for x in diag['refits'] if x['query'] < cut], pd['refits'])
        altered = {k: v.copy() for k, v in d.items()}
        altered['y'][cut-1:] = 400
        altered['X'][cut:] = 999
        cc = {k: v.copy() for k, v in c.items()}
        cc['labels'][cut-1:] = 2
        changed, _ = replay(altered, cc, b, factory=lambda: Probe([]))
        for name in full:
            np.testing.assert_array_equal(full[name][:cut], changed[name][:cut])

    def test_nonfinite_prediction_fails_without_dropping_cases(self):
        d, c, b = fixture(6)
        class Bad(Probe):
            def predict(self, x):
                return np.array([np.nan])
        with self.assertRaises(ValueError):
            replay(d, c, b, factory=lambda: Bad([]))


if __name__ == '__main__':
    unittest.main()
