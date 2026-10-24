import sys
from pathlib import Path
import unittest
import datetime as dt
from zoneinfo import ZoneInfo
import numpy as np
sys.path.insert(0,str(Path(__file__).parents[1]))
from research_sleep_neural_observer import completed_intervals,make_input,parameters


class NeuralObserverTests(unittest.TestCase):
    def test_completed_union_excludes_future_ends_and_handles_overlaps(self):
        s=np.array([[0,100,0],[50,150,0],[200,300,0],[250,400,0],[500,600,0]],dtype=float)
        lower,union=completed_intervals(s,300)
        self.assertEqual(lower,0);self.assertEqual(union,[[0,150],[200,300]])
        _,recent=completed_intervals(s,300,100/86400)
        self.assertEqual(recent,[[200,300]])

    def test_forecast_inputs_ignore_future_sleep_rows(self):
        s=np.array([[0,100,0],[200,300,0],[500,600,0]],dtype=float)
        future=np.vstack([s,[350,700,0],[800,900,0]])
        self.assertEqual(make_input(s,np.array([100.,300.]),'America/Los_Angeles'),
                         make_input(future,np.array([100.,300.]),'America/Los_Angeles'))
        # No actual next-start labels are accepted by the observer input API.
        self.assertEqual(len(parameters()),14)

    def test_local_calendar_preserves_dst_transition(self):
        tz=ZoneInfo('America/Los_Angeles')
        now=dt.datetime(2026,3,9,10,tzinfo=tz).timestamp()
        s=np.array([[now-7*86400,now-6*86400,0],[now-3600,now,0]])
        lines=make_input(s,np.array([now]),'America/Los_Angeles').splitlines()
        nq,np_,no=map(int,lines[0].split());self.assertEqual((nq,np_,no),(1,14,2))
        offsets=[list(map(float,row.split())) for row in lines[1+np_:1+np_+no]]
        self.assertEqual([v[1] for v in offsets],[-8,-7])
        expected=dt.datetime(2026,3,8,3,tzinfo=tz).timestamp()/3600
        self.assertEqual(offsets[1][0],expected)
