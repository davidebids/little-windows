import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import numpy as np
from research_sleep_planning import eligible, planning_mask, replay


class PlanningReplayTests(unittest.TestCase):
    def fixture(self,n=75):
        wakes=1_000_000+np.arange(n)*86400.
        x=np.column_stack([np.arange(n),np.sin(np.arange(n)),np.cos(np.arange(n)),np.zeros(n),np.full(n,60),np.full(n,70),np.ones(n),np.zeros(n),np.full(n,120),np.full(n,90),np.full(n,600)])
        y=100+np.arange(n)%30
        d=dict(X=x.copy(),y=y.astype(float),wakes=wakes,available=wakes+y*60)
        c=dict(X=x,knownAt=d['available']+3600,labels=np.where(np.arange(n)%4==0,2,1),wakeClock=np.full(n,900.),targetClock=900+y,ordinal=np.zeros(n))
        return d,c,np.full(n,120.)

    def test_cohort_boundary_and_disjoint_secondary_cases(self):
        d,c,_=self.fixture(5); d['y']=np.array([19.,20.,21.,100.,120.]); c['labels']=np.array([0,0,1,2,0])
        np.testing.assert_array_equal(planning_mask(d,c),[False,False,True,True,False])

    def test_resolved_labels_only(self):
        d,c,_=self.fixture(); c['knownAt'][30]=d['wakes'][50]+1; c['labels'][31]=0
        indices=eligible(d,c,50,True)
        self.assertNotIn(30,indices); self.assertNotIn(31,indices); self.assertNotIn(50,indices)
        self.assertIn(31,eligible(d,c,50,False))
        c['knownAt'][30]=d['wakes'][50]
        self.assertIn(30,eligible(d,c,50,True))

    def test_prefix_and_current_future_outcomes_do_not_change_issued_predictions(self):
        d,c,base=self.fixture(); full,_=replay(d,c,base)
        length=66
        prefix,_=replay({k:v[:length] for k,v in d.items()},{k:v[:length] for k,v in c.items()},base[:length])
        altered_d={k:v.copy() for k,v in d.items()}; altered_c={k:v.copy() for k,v in c.items()}
        altered_d['y'][65:]=5; altered_c['labels'][65:]=0; altered_c['targetClock'][65:]=0
        changed,_=replay(altered_d,altered_c,base)
        for name in full:
            np.testing.assert_array_equal(full[name][:length],prefix[name])
            np.testing.assert_array_equal(full[name][:length],changed[name][:length])
            self.assertTrue(np.isfinite(full[name]).all())

if __name__=='__main__': unittest.main()
