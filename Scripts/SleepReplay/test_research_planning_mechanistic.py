from pathlib import Path
import sys
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_mechanistic import select_planning,two_process_bank,blend_planning


class PlanningMechanisticTests(unittest.TestCase):
    def test_convex_blend_learns_exact_interval_weight_without_future_labels(self):
        data,c,bank,base=self.fixture();base[:]=60;alternative=np.full(90,180.)
        for local in (False,True):
            p,_=blend_planning(data,c,alternative,base,local)
            np.testing.assert_array_equal(p[:40],60);np.testing.assert_array_equal(p[40:],120)
            changed=dict(data,y=data['y'].copy());changed['y'][69:]=9999
            q,_=blend_planning(changed,c,alternative,base,local);np.testing.assert_array_equal(p[:70],q[:70])
            short={k:(v[:70] if k!='names' else v) for k,v in data.items()}
            prefix,_=blend_planning(short,{k:v[:70] for k,v in c.items()},alternative[:70],base[:70],local)
            np.testing.assert_array_equal(p[:70],prefix)

    def test_constant_threshold_matches_analytic_pressure_crossing(self):
        data=dict(names=['wakeMinute','homeostat120_60'],X=np.array([[600.,.2],[720.,.5]]),y=np.array([100.,150.]))
        bank=two_process_bank(data)
        for i,state in enumerate((.2,.5)):
            expected=[np.clip(np.ceil(-120*np.log((1-threshold)/(1-state))),1,480) for threshold in np.linspace(.1,.9,17)]
            np.testing.assert_allclose(bank[i,:17],expected,rtol=0,atol=1)
        changed=dict(names=data['names'],X=data['X'],y=np.array([999.,999.]))
        np.testing.assert_array_equal(bank,two_process_bank(changed))

    def fixture(self):
        n=90;i=np.arange(n);wakes=1e7+i*86400.
        data=dict(X=np.full((n,1),60.),names=['lastDuration'],y=np.full(n,120.),wakes=wakes)
        context=dict(labels=np.ones(n,int),knownAt=wakes+20000,wakeClock=np.full(n,600.))
        return data,context,np.tile([15.,120.,240.],(n,1)),np.full(n,99.)

    def test_distinct_training_ignores_brief_returns_and_unresolved_labels(self):
        data,c,bank,base=self.fixture();data['y'][:20]=15;c['labels'][:20]=0;c['knownAt'][20]=1e20
        for local in (False,True):
            p,diag=select_planning(data,c,bank,base,local)
            np.testing.assert_array_equal(p[:61],base[:61]);np.testing.assert_array_equal(p[61:],120.)
            self.assertEqual(diag['learnedQueries'],29)
            changed={k:(v.copy() if isinstance(v,np.ndarray) else v) for k,v in data.items()};changed['y'][20]=999
            q,_=select_planning(changed,c,bank,base,local);np.testing.assert_array_equal(p,q)

    def test_prefix_and_current_type_isolation_preserve_overnight_points(self):
        data,c,bank,base=self.fixture();c['wakeClock'][::13]=120
        for local in (False,True):
            p,_=select_planning(data,c,bank,base,local)
            d={k:(v[:70] if k!='names' else v) for k,v in data.items()};cc={k:v[:70] for k,v in c.items()}
            q,_=select_planning(d,cc,bank[:70],base[:70],local);np.testing.assert_array_equal(p[:70],q)
            data['y'][69:]=1;c['labels'][69:]=0
            altered,_=select_planning(data,c,bank,base,local);np.testing.assert_array_equal(p[:70],altered[:70])
            np.testing.assert_array_equal(p[::13],base[::13])
            data['y'][69:]=120;c['labels'][69:]=1


if __name__=='__main__':unittest.main()
