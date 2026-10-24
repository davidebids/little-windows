import sys
from pathlib import Path
import unittest

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_drift_gp import PlanningProcess, replay


def fixture(n=60):
    wakes=1700000040.+np.arange(n)*86400
    d=dict(X=np.column_stack([np.arange(n),np.zeros(n)]), y=40.+np.arange(n), wakes=wakes)
    c=dict(X=np.zeros((n,11)), knownAt=wakes+3600, labels=np.ones(n))
    return d,c,np.full(n,60.)


class Probe:
    def __init__(self, linear):
        self.linear=linear;self.optimization=[];self.boundWarnings=0
    def fit(self,X,y):
        self.value=float(np.mean(y))
        return self
    def predict(self,X):
        assert len(X)==1
        return np.array([self.value])


class DriftProcessTests(unittest.TestCase):
    def test_linear_covariance_can_extrapolate_beyond_training_targets(self):
        X=np.linspace(-1,1,12)[:,None];y=3*X[:,0]
        model=PlanningProcess(True,optimize=False).fit(X,y)
        self.assertGreater(float(model.predict(np.array([[3.]]))[0]),y.max())
        self.assertFalse(model.optimization)

    def test_real_optimized_fit_is_repeatable_with_missing_inputs(self):
        X=np.column_stack([np.linspace(0,1,10),np.full(10,np.nan)])
        y=np.linspace(0,2,10)
        a=PlanningProcess(True).fit(X,y);b=PlanningProcess(True).fit(X,y)
        np.testing.assert_array_equal(a.predict(X[:2]),b.predict(X[:2]))
        self.assertEqual(a.optimization,b.optimization)
        self.assertTrue(np.isfinite(a.predict(X)).all())

    def test_prefix_current_target_and_early_expiry_policy(self):
        d,c,base=fixture(90);c['knownAt'][1]=d['wakes'][12];c['labels'][2]=0;d['y'][3]=20
        out,diag=replay(d,c,base,factory=Probe)
        self.assertEqual(diag['refits'][0]['query'],6)
        self.assertEqual(diag['refits'][0]['labels'],3)
        cut=37
        ds={k:v[:cut] for k,v in d.items()};cs={k:v[:cut] for k,v in c.items()}
        short,sd=replay(ds,cs,base[:cut],factory=Probe)
        for name in out:np.testing.assert_array_equal(out[name][:cut],short[name])
        self.assertEqual([r for r in diag['refits'] if r['query']<cut],sd['refits'])
        changed={k:v.copy() for k,v in d.items()};changed['y'][cut-1:]=400;changed['X'][cut:]=999
        cc={k:v.copy() for k,v in c.items()};cc['labels'][cut-1:]=2
        altered,_=replay(changed,cc,base,factory=Probe)
        for name in out:np.testing.assert_array_equal(out[name][:cut],altered[name][:cut])
        self.assertLessEqual(diag['refits'][-1]['labels'],60)

    def test_nonfinite_forecast_fails_without_dropping_cases(self):
        d,c,base=fixture(6)
        class Bad(Probe):
            def predict(self,X):return np.array([np.nan])
        with self.assertRaises(ValueError):replay(d,c,base,factory=Bad)


if __name__=='__main__':unittest.main()
