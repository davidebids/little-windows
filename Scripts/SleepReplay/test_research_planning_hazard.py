import sys
from pathlib import Path
import unittest
import numpy as np
from sklearn.ensemble import HistGradientBoostingClassifier
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_hazard import GRID,exposure,event_mass,replay

class PlanningHazardTests(unittest.TestCase):
    def fixture(self):
        n=52;w=np.arange(n,dtype=float)*86400
        X=np.column_stack([np.ones(n),np.zeros(n)])
        d=dict(wakes=w,y=25.+np.arange(n)%10,X=X,names=np.array(['clockSin1','clockCos1']))
        c=dict(knownAt=w+3600,labels=1+np.arange(n)%2,wakeClock=np.full(n,600.),X=np.zeros((n,11)))
        return d,c,np.full(n,100.)
    def fast(self):
        return HistGradientBoostingClassifier(max_iter=3,max_leaf_nodes=3,min_samples_leaf=3,early_stopping=False,random_state=42)
    def test_exposure_event_time_and_future_clock(self):
        x,y=exposure(np.array([0.,1.]),25.,2,['clockSin1','clockCos1'])
        self.assertEqual(y.tolist(),[0,0,0,0,2]);np.testing.assert_array_equal(x[:,2],np.arange(21,26))
        np.testing.assert_allclose(x[:,3],np.sin(2*np.pi*np.arange(21,26)/1440))
        with self.assertRaises(ValueError):exposure(np.array([0.,1.]),20,1,['clockSin1','clockCos1'])
    def test_survival_conservation_and_type_permutation(self):
        p=np.tile([.7,.1,.2],(len(GRID),1));mass=event_mass(p,[0,1,2])
        self.assertAlmostEqual(mass.sum(),1);np.testing.assert_allclose(mass[:3],[.3,.21,.147])
        np.testing.assert_array_equal(mass,event_mass(p[:,[2,0,1]],[2,0,1]))
        p=np.tile([1.,0.],(len(GRID),1));mass=event_mass(p,[0,1]);self.assertEqual(mass[-1],1)
    def test_real_classifier_prefix_current_and_future_outcomes(self):
        d,c,b=self.fixture();full,_=replay(d,c,b,factory=self.fast);cut=46
        prefix,_=replay({k:(v[:cut] if k!='names' else v) for k,v in d.items()},{k:v[:cut] for k,v in c.items()},b[:cut],factory=self.fast)
        d['y'][cut-1:]=400;c['labels'][cut-1:]=2
        changed,_=replay(d,c,b,factory=self.fast)
        for k in full:
            np.testing.assert_array_equal(full[k][:cut],prefix[k]);np.testing.assert_array_equal(full[k][:cut],changed[k][:cut])
    def test_unresolved_outcomes_and_night_fallback(self):
        d,c,b=self.fixture();c['knownAt'][:]=1e20
        p,_=replay(d,c,b,factory=self.fast)
        for v in p.values():np.testing.assert_array_equal(v,b)
        d,c,b=self.fixture();c['wakeClock'][-1]=120
        p,_=replay(d,c,b,factory=self.fast)
        for v in p.values():self.assertEqual(v[-1],b[-1])

if __name__=='__main__':unittest.main()
