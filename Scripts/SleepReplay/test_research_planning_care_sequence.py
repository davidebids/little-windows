import sys
from pathlib import Path
import unittest
import numpy as np
import torch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_care_sequence import fit_trajectory,choose_duration,replay
from research_sleep_care_recurrent import fit_model,predict_model

class PlanningCareSequenceTests(unittest.TestCase):
    def fixture(self,n=80):
        rng=np.random.default_rng(7);w=np.arange(n,dtype=float)*86400
        d=dict(wakes=w,y=70+10*np.sin(np.arange(n)),X=rng.normal(size=(n,3)))
        c=dict(knownAt=w+600,labels=np.ones(n,int),wakeClock=np.full(n,600.),X=np.zeros((n,11)))
        return d,c,np.full(n,75.),rng.normal(size=(n,16,11))
    def test_trajectory_snapshots_match_independent_cold_fits(self):
        torch.set_num_threads(2);torch.use_deterministic_algorithms(True)
        rng=np.random.default_rng(42);P=rng.normal(size=(24,16,11));C=rng.normal(size=(24,4));y=10*C[:,0];weights=np.linspace(.5,1,24)
        snapshots=fit_trajectory(P,C,y,weights,(2,4,6))
        for epoch,fit in snapshots.items():
            independent=fit_model(P,C,y,weights,epoch)
            np.testing.assert_array_equal(predict_model(fit,P[:3],C[:3]),predict_model(independent,P[:3],C[:3]))
            self.assertEqual(fit[-2:],independent[-2:])
    def test_selection_includes_app_and_scores_clipped_forecast(self):
        d,c,b,P=self.fixture();training=np.arange(20);val=np.arange(20,28);C=d['X']
        trajectory=lambda *args:{2:2,4:4}
        predict=lambda fit,p,x:np.full(len(x),1000.)
        d['y'][val]=480
        selected,loss=choose_duration(P,C,d,b,training,val,d['wakes'][30],(2,4),trajectory,predict)
        self.assertEqual(selected,2);self.assertEqual(loss[2],0);self.assertEqual(loss[4],0)
        d['y'][val]=b[val]
        selected,loss=choose_duration(P,C,d,b,training,val,d['wakes'][30],(2,4),trajectory,predict)
        self.assertEqual(selected,0)
    def test_shared_planning_validation_and_maturity_purge(self):
        d,c,b,P=self.fixture();c['labels'][1]=0;c['knownAt'][2]=1e20;c['knownAt'][30]=d['wakes'][35]+100;seen=[]
        def choose(p,x,data,base,training,val,now,epochs):
            seen.append((training.copy(),val.copy()))
            self.assertTrue((c['knownAt'][training]<=d['wakes'][val[0]]).all())
            return 0,{}
        out,diag=replay(d,c,b,P,epochs=(1,2,3),choose=choose)
        for training,val in seen[:4]:
            np.testing.assert_array_equal(val,seen[0][1]);self.assertNotIn(2,training);self.assertNotIn(30,training)
        self.assertIn(1,seen[0][0])
        for training,_ in seen[1:4]:self.assertNotIn(1,training)
        self.assertEqual(diag['refits'],2)
        for p in out.values():np.testing.assert_array_equal(p,b)
    def test_real_gru_current_future_outcomes_and_prefix(self):
        d,c,b,P=self.fixture(70);d['y']=100+2*np.sin(np.arange(70));full,_=replay(d,c,b,P,epochs=(1,2,3));cut=60
        self.assertTrue(any(np.any(v!=b) for v in full.values()))
        prefix,_=replay({k:v[:cut] for k,v in d.items()},{k:v[:cut] for k,v in c.items()},b[:cut],P[:cut],epochs=(1,2,3))
        d['y'][cut-1:]=9999;c['labels'][cut-1:]=0;P[cut:]=999
        changed,_=replay(d,c,b,P,epochs=(1,2,3))
        for name in full:
            np.testing.assert_array_equal(full[name][:cut],prefix[name]);np.testing.assert_array_equal(full[name][:cut],changed[name][:cut])
    def test_invalid_pattern_sparse_night_and_nonfinite_prediction(self):
        d,c,b,P=self.fixture();c['wakeClock'][78]=120;P[79]=np.nan
        choose=lambda *args:(2,{})
        fit=lambda *args:('fit',1)
        predict=lambda model,p,x:np.full(len(x),5.)
        out,_=replay(d,c,b,P,epochs=(1,2,3),choose=choose,fit=fit,predict=predict)
        for p in out.values():
            self.assertEqual(p[77],80);self.assertEqual(p[78],75);self.assertEqual(p[79],75)
        d,c,b,P=self.fixture(20);out,diag=replay(d,c,b,P,epochs=(1,2,3))
        self.assertEqual(diag['refits'],0)
        for p in out.values():np.testing.assert_array_equal(p,b)
        d,c,b,P=self.fixture()
        with self.assertRaises(RuntimeError):replay(d,c,b,P,epochs=(1,2,3),choose=choose,fit=fit,predict=lambda *args:np.array([np.nan]))

if __name__=='__main__':unittest.main()
