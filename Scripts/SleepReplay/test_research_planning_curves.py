import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_curves import replay


class PlanningCurveTests(unittest.TestCase):
    def fixture(self,n=80):
        age=np.arange(n,dtype=float); wakes=1e6+age*86400; y=60+age
        X=np.zeros((n,11)); X[:,0]=age; X[:,4:6]=60; X[:,6]=1
        d=dict(wakes=wakes,y=y,available=wakes+y*60)
        c=dict(X=X,labels=np.ones(n,dtype=int),wakeClock=np.full(n,600.),ordinal=np.zeros(n),knownAt=d['available']+3600)
        return d,c,np.full(n,90.)

    def test_learns_age_trend_without_current_outcome(self):
        d,c,forest=self.fixture(); predictions,diag=replay(d,c,forest)
        p=predictions['planningCurve_pooled_direct_p0.05']
        np.testing.assert_array_equal(p[:20],forest[:20])
        self.assertLess(float(np.mean(abs(p[30:]-d['y'][30:]))),.01)
        self.assertGreater(float(np.mean(abs(forest[30:]-d['y'][30:]))),10)
        for record in diag.values():self.assertLess(record['maximumEqualityResidual'],1e-6)

    def test_prefix_and_unresolved_label_isolation(self):
        d,c,forest=self.fixture(); c['knownAt'][40]=1e20
        full,_=replay(d,c,forest)
        prefix,_=replay({k:v[:65] for k,v in d.items()},{k:v[:65] for k,v in c.items()},forest[:65])
        changed=dict(d,y=d['y'].copy()); changed['y'][40]=9999
        altered,_=replay(changed,c,forest)
        for name,p in full.items():
            np.testing.assert_array_equal(p[:65],prefix[name]);np.testing.assert_array_equal(p,altered[name])
            self.assertTrue(np.all((p>=1)&(p<=480)))

    def test_current_and_future_cohort_changes_do_not_route_current_forecast(self):
        d,c,forest=self.fixture(); full,_=replay(d,c,forest)
        d2={k:v.copy() for k,v in d.items()};c2={k:v.copy() for k,v in c.items()}
        d2['y'][64:]=2;c2['labels'][64:]=0
        changed,_=replay(d2,c2,forest)
        for name,p in full.items():np.testing.assert_array_equal(p[:65],changed[name][:65])

if __name__=='__main__':unittest.main()
