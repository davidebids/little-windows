import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_warmup import warmup


class PlanningWarmupTests(unittest.TestCase):
    def fixture(self,n=70):
        i=np.arange(n);wakes=1e6+i*86400.;y=np.full(n,100.)
        d=dict(wakes=wakes,y=y);X=np.zeros((n,11));c=dict(X=X,labels=np.ones(n,dtype=int),knownAt=wakes+12000,wakeClock=np.full(n,600.))
        return d,c,np.full(n,200.),np.full(n,100.)

    def test_mature_forecast_preserved_and_label_maturity_controls_boundary(self):
        d,c,forest,curve=self.fixture();c['knownAt'][30]=1e20
        result,active=warmup(d,c,forest,curve)
        self.assertTrue(active[40]);self.assertFalse(active[41])
        np.testing.assert_array_equal(result['warmupAgeCurve'][41:],forest[41:])
        np.testing.assert_array_equal(result['warmupRecentMedian'][41:],forest[41:])
        np.testing.assert_array_equal(result['warmupRecentMedian'][:3],forest[:3])
        np.testing.assert_array_equal(result['warmupRecentMedian'][3:41],np.full(38,100.))

    def test_prefix_unavailable_and_future_labels_isolated(self):
        d,c,forest,curve=self.fixture();c['knownAt'][15]=1e20
        full,active=warmup(d,c,forest,curve)
        prefix,_=warmup({k:v[:35] for k,v in d.items()},{k:v[:35] for k,v in c.items()},forest[:35],curve[:35])
        d2={k:v.copy() for k,v in d.items()};c2={k:v.copy() for k,v in c.items()};d2['y'][15]=9999;d2['y'][34:]=1;c2['labels'][34:]=0
        changed,_=warmup(d2,c2,forest,curve)
        for name in full:
            np.testing.assert_array_equal(full[name][:35],prefix[name]);np.testing.assert_array_equal(full[name][:35],changed[name][:35])

if __name__=='__main__':unittest.main()
