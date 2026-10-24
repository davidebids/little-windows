import csv
import datetime as dt
import sys
import tempfile
import unittest
from pathlib import Path
from zoneinfo import ZoneInfo
import numpy as np
sys.path.insert(0,str(Path(__file__).parents[1]))
from research_sleep_behavior_schedule import structure,replay,weighted_median


class BehaviorScheduleTests(unittest.TestCase):
    def test_completed_nap_segments_inform_ordinal_without_merging_targets(self):
        pairs=[('09:00','10:00'),('10:05','10:40'),('13:00','14:00'),('16:00','17:00')]
        zone=ZoneInfo('America/Los_Angeles')
        stamp=lambda v:dt.datetime.strptime('2001-01-01 '+v,'%Y-%m-%d %H:%M').replace(tzinfo=zone).timestamp()
        wakes=np.array([stamp(v[1]) for v in pairs[:-1]]); available=np.array([stamp(v[0]) for v in pairs[1:]])
        data=dict(indices=np.arange(3),wakes=wakes,available=available,y=(available-wakes)/60,
            names=['ageDays','wakeLag1','sleepMinutes6h','sleepMinutes24h'],X=np.ones((3,4)))
        with tempfile.TemporaryDirectory() as folder:
            p=Path(folder)/'sleep.csv'
            with p.open('w') as f:
                writer=csv.DictWriter(f,fieldnames=['Type','Start','End']); writer.writeheader()
                for start,end in pairs: writer.writerow(dict(Type='Sleep',Start='2001-01-01 '+start,End='2001-01-01 '+end))
            context=structure(p,data,{i:dict(actualKind='nap') for i in range(3)},'America/Los_Angeles')
        self.assertEqual(len(context['labels']),3); np.testing.assert_array_equal(context['labels'],[0,1,1])
        np.testing.assert_array_equal(context['ordinal'],[1,1,2])
        self.assertEqual(context['X'][1,5],95.); self.assertEqual(context['X'][1,6],2.)
        self.assertEqual(context['knownAt'][0],stamp('10:40'))
        self.assertEqual(context['knownAt'][1],stamp('14:00'))

    def test_weighted_median_and_delayed_type_label_prefix_isolation(self):
        self.assertEqual(weighted_median(np.array([120.,5.,180.]),np.array([1.,8.,1.])),5.)
        n=100; rng=np.random.default_rng(42); wakes=np.arange(n)*21600.; y=60+10*np.sin(np.arange(n)); data=dict(wakes=wakes,available=wakes+y*60,y=y)
        X=rng.uniform(size=(n,11)); X[:,5]=30+30*X[:,5]; X[:,3]=np.arange(n)%2
        context=dict(X=X,labels=np.arange(n)%3,knownAt=data['available']+3600,
            targetClock=np.full(n,1200.),wakeClock=np.full(n,600.),day=np.array([str(i//4) for i in range(n)]),ordinal=np.arange(n)%3)
        context['knownAt'][50]=1e20; base=np.full(n,60.)
        full,diag=replay(data,context,base)
        short,_=replay({k:v[:80] for k,v in data.items()},{k:v[:80] for k,v in context.items()},base[:80])
        altered=dict(data,y=y.copy()); altered['y'][50]=99999
        changed=dict(context,labels=context['labels'].copy(),targetClock=context['targetClock'].copy())
        changed['labels'][50]=2; changed['targetClock'][50]=0
        alternate,_=replay(altered,changed,base)
        self.assertEqual(len(full),8)
        for name,p in full.items():
            np.testing.assert_array_equal(p[:80],short[name]); np.testing.assert_array_equal(p,alternate[name])
            self.assertTrue(np.all((p>=1)&(p<=480)))
        self.assertGreater(diag['5']['learnedQueries'],50)
