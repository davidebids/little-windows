import datetime as dt
import importlib.util
from pathlib import Path
import sys
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_boost import diary_features,replay,night_summary,positioned_replay
from zoneinfo import ZoneInfo


class PlanningBoostTests(unittest.TestCase):
    def fixture(self):
        start=dt.datetime(2025,1,1,tzinfo=dt.timezone.utc).timestamp()
        wakes=start+np.arange(3)*86400+36000
        X=np.zeros((3,11));X[:,5]=[30,60,45]
        data=dict(X=X.copy(),wakes=wakes,y=np.array([120.,90.,130.]))
        context=dict(X=X,day=np.array(['2025-01-01','2025-01-02','2025-01-03']),labels=np.ones(3,int),ordinal=np.zeros(3),wakeClock=np.full(3,600.),targetClock=np.array([720.,690.,730.]),knownAt=wakes+15000)
        sleeps=np.array([[start+48*3600,start+55*3600,1],[start+56*3600,start+57*3600,0],[start+72*3600,start+79*3600,1]],float)
        return data,context,sleeps

    def test_manual_calendar_day_position_and_night_features(self):
        d,c,s=self.fixture();v=diary_features(d,c,s,'UTC')
        np.testing.assert_array_equal(v[2,:5],[105,45,600,705,2])
        np.testing.assert_array_equal(v[2,30:35],[90,60,600,690,1])
        np.testing.assert_array_equal(v[2,60:64],[420,180,420,60])
        np.testing.assert_array_equal(v[2,67:],[105,90])
        self.assertTrue(np.isnan(v[0,:4]).all())
        np.testing.assert_array_equal(v[:2],diary_features({k:a[:2] for k,a in d.items()},{k:a[:2] for k,a in c.items()},s,'UTC'))

    def test_unresolved_and_current_outcomes_and_future_sleeps_are_isolated(self):
        d,c,s=self.fixture();c['knownAt'][1]=d['wakes'][2]+1
        before=diary_features(d,c,s,'UTC')
        d['y'][1]=999;c['labels'][1]=0;c['targetClock'][1]=0
        np.testing.assert_array_equal(before,diary_features(d,c,s,'UTC'))
        d['y'][2]=2;c['labels'][2]=0;c['targetClock'][2]=0;s[-1,1]+=86400
        np.testing.assert_array_equal(before,diary_features(d,c,s,'UTC'))

    def test_night_duration_uses_elapsed_time_across_pacific_daylight_change(self):
        tz=ZoneInfo('America/Los_Angeles')
        start=dt.datetime(2025,3,8,20,tzinfo=tz).timestamp()
        end=dt.datetime(2025,3,9,7,tzinfo=tz).timestamp()
        observed=np.array([[start,end,1.]])
        actual,clock,minutes=night_summary(observed,dt.date(2025,3,9),tz)
        self.assertEqual(actual,end);self.assertEqual(clock,420);self.assertEqual(minutes,600)

    @unittest.skipUnless(importlib.util.find_spec('lightgbm'),'Optional LightGBM research dependency not installed')
    def test_boost_prefix_unknown_labels_empty_columns_and_overnight_preservation(self):
        n=90;i=np.arange(n);wakes=1e6+i*86400.
        X=np.column_stack([i.astype(float),np.full(n,np.nan),np.sin(i)])
        C=np.zeros((n,11));C[:,0]=i;C[:,5]=60;C[:,6]=1;C[:,7]=1
        d=dict(X=X,y=80.+i%40,wakes=wakes);c=dict(X=C,labels=np.ones(n,int),knownAt=wakes+18000,wakeClock=np.full(n,600.))
        c['knownAt'][30]=1e20;c['wakeClock'][::12]=120.
        extra=np.full((n,69),np.nan);extra[:,0]=i;base=np.full(n,110.)
        full,diag=replay(d,c,base,extra,iterations=10)
        short,_=replay({k:v[:75] for k,v in d.items()},{k:v[:75] for k,v in c.items()},base[:75],extra[:75],iterations=10)
        d2={k:v.copy() for k,v in d.items()};c2={k:v.copy() for k,v in c.items()};d2['y'][30]=9999;c2['labels'][30]=0
        altered,_=replay(d2,c2,base,extra,iterations=10)
        for name,p in full.items():
            np.testing.assert_array_equal(p[:75],short[name]);np.testing.assert_array_equal(p,altered[name]);np.testing.assert_array_equal(p[::12],base[::12])
            self.assertTrue(np.isfinite(p).all());self.assertGreater(diag[name]['maximumDroppedAllMissingColumns'],0)
        d2['y'][74:]=1;c2['labels'][74:]=0
        changed,_=replay(d2,c2,base,extra,iterations=10)
        for name,p in full.items():np.testing.assert_array_equal(p[:75],changed[name][:75])


    @unittest.skipUnless(importlib.util.find_spec('lightgbm'),'Optional LightGBM research dependency not installed')
    def test_position_models_and_recent_mean_use_known_order_and_preserve_prefix(self):
        n=90;i=np.arange(n);wakes=1e6+i*86400.;X=np.zeros((n,11));X[:,0]=i;X[:,5]=60
        d=dict(X=X.copy(),wakes=wakes,y=100.+10*(i%2))
        c=dict(X=X,labels=np.ones(n,int),ordinal=i%2,knownAt=wakes+18000,wakeClock=np.full(n,600.))
        c['knownAt'][20]=1e20;c['wakeClock'][::17]=120
        extra=np.full((n,69),np.nan);extra[:,0]=123;extra[:,4]=3;extra[:,5]=231;extra[:,9]=3;base=np.full(n,110.)
        full,_=positioned_replay(d,c,base,extra,iterations=5)
        prefix,_=positioned_replay({k:v[:75] for k,v in d.items()},{k:v[:75] for k,v in c.items()},base[:75],extra[:75],iterations=5)
        self.assertEqual(full['recentMean5_byPosition'][60],123)
        self.assertEqual(full['recentMean5_byPosition'][61],231)
        d2={k:v.copy() for k,v in d.items()};c2={k:v.copy() for k,v in c.items()};d2['y'][20]=999;c2['labels'][20]=0
        changed,_=positioned_replay(d2,c2,base,extra,iterations=5)
        for name,p in full.items():
            np.testing.assert_array_equal(p[:40],base[:40]);np.testing.assert_array_equal(p[::17],base[::17]);np.testing.assert_array_equal(p,changed[name]);np.testing.assert_array_equal(p[:75],prefix[name])

if __name__=='__main__':unittest.main()
