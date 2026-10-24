import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_prior import replay

class PlanningPriorTests(unittest.TestCase):
    def fixture(self,n=100):
        w=np.arange(n,dtype=float)*86400
        d=dict(X=np.arange(n,dtype=float)[:,None],y=np.arange(n,dtype=float)+30,wakes=w)
        c=dict(labels=np.ones(n,int),knownAt=w+600,wakeClock=np.full(n,600.),X=np.zeros((n,11)))
        return d,c,np.full(n,100.)
    def model(self,seen=None,nonfinite=False):
        outer=self
        class Model:
            def fit(self,X,y):
                if seen is not None:seen.append(X[:,0].copy())
                self.point=float(np.median(y))
            def predict(self,X,output_type):
                outer.assertEqual(len(X),1);outer.assertEqual(output_type,'main')
                return {k:[np.nan if nonfinite else self.point] for k in ['mean','median','mode']}
        return Model
    def test_only_resolved_planning_labels_and_individual_queries(self):
        d,c,b=self.fixture();c['labels'][0]=0;c['knownAt'][1]=1e20;d['y'][2]=10;seen=[]
        replay(d,c,b,self.model(seen))
        self.assertTrue(seen)
        for train in seen:
            self.assertNotIn(0,train);self.assertNotIn(1,train);self.assertNotIn(2,train)
    def test_current_future_outcome_and_prefix_invariance(self):
        d,c,b=self.fixture();full,_=replay(d,c,b,self.model());cut=80
        pre,_=replay({k:v[:cut] for k,v in d.items()},{k:v[:cut] for k,v in c.items()},b[:cut],self.model())
        d['y'][cut-1:]=400;c['labels'][cut-1:]=2;d['X'][cut:]=999
        changed,_=replay(d,c,b,self.model())
        for k in full:
            np.testing.assert_array_equal(full[k][:cut],pre[k]);np.testing.assert_array_equal(full[k][:cut],changed[k][:cut])
    def test_expired_history_and_overnight_fallback(self):
        d,c,b=self.fixture(150);seen=[];c['wakeClock'][-1]=120
        p,_=replay(d,c,b,self.model(seen))
        self.assertGreaterEqual(seen[-1].min(),68)
        for v in p.values():self.assertEqual(v[-1],100)
        d,c,b=self.fixture(20);p,diag=replay(d,c,b,self.model());self.assertEqual(diag['refits'],0)
        for v in p.values():np.testing.assert_array_equal(v,b)
    def test_nonfinite_output_fails_instead_of_dropping_case(self):
        d,c,b=self.fixture()
        with self.assertRaises(ValueError):replay(d,c,b,self.model(nonfinite=True))

if __name__=='__main__':unittest.main()
