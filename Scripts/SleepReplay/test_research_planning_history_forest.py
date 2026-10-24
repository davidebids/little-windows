import sys
from pathlib import Path
import unittest

import numpy as np

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_history_forest import history_inputs,replay


def fixture(n=55):
    wakes=1700000040.+np.arange(n)*86400
    d=dict(X=np.zeros((n,2)),y=30.+np.arange(n),wakes=wakes)
    c=dict(X=np.zeros((n,11)),knownAt=wakes+3600,labels=np.ones(n))
    return d,c,np.full(n,60.)


class Probe:
    def __init__(self,records):self.records=records
    def fit(self,X,y):
        self.records.append((X.copy(),y.copy()));self.value=float(np.mean(y));return self
    def predict(self,X):
        assert len(X)==1
        return np.array([self.value])


class HistoryForestTests(unittest.TestCase):
    def test_inputs_only_include_completed_history_and_unknown_pre_history(self):
        sleeps=np.array([[-90000,-89000],[-3000,-2000],[0,600],[700,900]],float)
        full=history_inputs(sleeps,np.array([600.]))
        past=history_inputs(sleeps[:-1],np.array([600.]))
        np.testing.assert_array_equal(full,past)
        self.assertAlmostEqual(full[0,0],2/3)

    def test_padded_control_and_training_maturity(self):
        d,c,b=fixture(90);c['knownAt'][1]=d['wakes'][12];c['labels'][2]=0;d['y'][3]=20
        H=np.full((90,96),.25);records=[]
        out,diag=replay(d,c,b,H,factory=lambda:Probe(records))
        self.assertEqual(diag['refits'][0],dict(query=6,labels=3))
        np.testing.assert_array_equal(records[0][1],d['y'][[0,4,5]])
        self.assertEqual(records[0][0].shape[1],5)
        np.testing.assert_array_equal(records[1][0][:,-96:],0.)
        np.testing.assert_array_equal(records[2][0][:,-96:],.25)
        self.assertLessEqual(diag['refits'][-1]['labels'],60)

    def test_prefix_current_target_and_future_inputs_are_isolated(self):
        d,c,b=fixture();H=np.zeros((len(b),96));full,diag=replay(d,c,b,H,factory=lambda:Probe([]))
        cut=37;ds={k:v[:cut] for k,v in d.items()};cs={k:v[:cut] for k,v in c.items()}
        prefix,pdiag=replay(ds,cs,b[:cut],H[:cut],factory=lambda:Probe([]))
        for name in full:np.testing.assert_array_equal(full[name][:cut],prefix[name])
        self.assertEqual([r for r in diag['refits'] if r['query']<cut],pdiag['refits'])
        changed={k:v.copy() for k,v in d.items()};changed['y'][cut-1:]=400;changed['X'][cut:]=999
        hc=H.copy();hc[cut:]=1
        altered,_=replay(changed,c,b,hc,factory=lambda:Probe([]))
        for name in full:np.testing.assert_array_equal(full[name][:cut],altered[name][:cut])

    def test_invalid_inputs_or_forecasts_fail_without_dropping_cases(self):
        d,c,b=fixture(6);H=np.zeros((6,96))
        with self.assertRaises(ValueError):replay(d,c,b,H[:5])
        class Bad(Probe):
            def predict(self,X):return np.array([np.nan])
        with self.assertRaises(ValueError):replay(d,c,b,H,factory=lambda:Bad([]))


if __name__=='__main__':unittest.main()
