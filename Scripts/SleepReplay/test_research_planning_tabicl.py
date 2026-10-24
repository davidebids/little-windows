import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_tabicl import replay

class PlanningTabICLTests(unittest.TestCase):
    def fixture(self,n=100):
        w=np.arange(n,dtype=float)*86400
        d=dict(X=np.arange(n,dtype=float)[:,None],y=np.arange(n,dtype=float)+30,wakes=w)
        c=dict(labels=np.ones(n,int),knownAt=w+600,wakeClock=np.full(n,600.),X=np.zeros((n,11)))
        return d,c,np.full(n,100.)
    def model(self,seen=None,bad=False):
        outer=self
        class Model:
            def fit(self,X,y):
                if seen is not None:seen.append(X[:,0].copy())
                self.point=float(np.median(y))
            def predict(self,X,output_type):
                outer.assertEqual(len(X),1);outer.assertEqual(output_type,['mean','median'])
                return {k:[np.nan if bad else self.point] for k in ['mean','median']}
        return Model
    def test_single_query_only_resolved_planning_training(self):
        d,c,b=self.fixture();c['labels'][0]=0;c['knownAt'][1]=1e20;d['y'][2]=10;seen=[]
        replay(d,c,b,self.model(seen));self.assertTrue(seen)
        for train in seen:
            for j in [0,1,2]:self.assertNotIn(j,train)
    def test_current_future_outcomes_and_prefix(self):
        d,c,b=self.fixture();full,_=replay(d,c,b,self.model());cut=80
        pre,_=replay({k:v[:cut] for k,v in d.items()},{k:v[:cut] for k,v in c.items()},b[:cut],self.model())
        d['y'][cut-1:]=400;c['labels'][cut-1:]=2;d['X'][cut:]=999
        changed,_=replay(d,c,b,self.model())
        for k in full:
            np.testing.assert_array_equal(full[k][:cut],pre[k]);np.testing.assert_array_equal(full[k][:cut],changed[k][:cut])
    def test_expiry_sparse_history_and_night(self):
        d,c,b=self.fixture(150);seen=[];c['wakeClock'][-1]=120;p,_=replay(d,c,b,self.model(seen))
        self.assertGreaterEqual(seen[-1].min(),68)
        for v in p.values():self.assertEqual(v[-1],100)
        d,c,b=self.fixture(20);p,diag=replay(d,c,b,self.model());self.assertEqual(diag['refits'],0)
        for v in p.values():np.testing.assert_array_equal(v,b)
    def test_nonfinite_prediction_fails_without_dropping_case(self):
        d,c,b=self.fixture()
        with self.assertRaises(ValueError):replay(d,c,b,self.model(bad=True))

if __name__=='__main__':unittest.main()
