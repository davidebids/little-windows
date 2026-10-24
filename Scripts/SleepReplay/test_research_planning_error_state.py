import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_error_state import fit_state,correction,replay


class ErrorStateTests(unittest.TestCase):
    def fixture(self,n=70):
        w=100000+np.arange(n)*7200.
        return dict(wakes=w,y=100+30*np.sin(np.arange(n)/5)),dict(knownAt=w+600,labels=np.ones(n,int)),np.full(n,100.)

    def test_closed_form_observation_and_decay(self):
        params=np.array([5.,100.,0.,25.])
        self.assertAlmostEqual(correction(params,[0.],[25.],0.),21.)
        self.assertAlmostEqual(correction(params,[0.],[25.],6*3600.),5+16/np.e)
        self.assertAlmostEqual(correction([5,0,0,25],[0],[80],100),5.)

    def test_null_and_learned_state_are_finite_and_deterministic(self):
        t=np.arange(60)*7200.
        p,info=fit_state(t,np.zeros(60));np.testing.assert_array_equal(p,[0,0,0,25]);self.assertTrue(info['nullSelected'])
        residual=30*np.sin(np.arange(60)/5)
        p,info=fit_state(t,residual);q,_=fit_state(t,residual)
        np.testing.assert_array_equal(p,q);self.assertGreater(p[1]+p[2],0.)
        self.assertTrue(np.isfinite(correction(p,t,residual,t[-1]+7200)))
        with self.assertRaises(ValueError):fit_state(t[:11],residual[:11])

    def test_real_fit_prefix_and_unresolved_outcome_isolation(self):
        d,c,p=self.fixture();full,diag=replay(d,c,p);cut=53
        pre,_=replay({k:v[:cut] for k,v in d.items()},{k:v[:cut] for k,v in c.items()},p[:cut])
        d['y'][cut-1:]=9999;c['labels'][cut-1:]=0
        changed,_=replay(d,c,p)
        for name in full:
            np.testing.assert_array_equal(full[name][:cut],pre[name]);np.testing.assert_array_equal(full[name][:cut],changed[name][:cut])
        self.assertGreater(diag['adjustedQueries'],0)
        self.assertTrue(np.any(full['transientErrorState']!=p))

    def test_maturity_expiry_and_sparse_fallback(self):
        d,c,p=self.fixture(30);c['knownAt'][:20]=d['wakes'][-1]+86400
        out,diag=replay(d,c,p)
        for values in out.values():np.testing.assert_array_equal(values,p)
        self.assertEqual(diag['adjustedQueries'],0)
        d,c,p=self.fixture(60);d['wakes'][40:]+=61*86400;c['knownAt'][40:]+=61*86400
        out,_=replay(d,c,p)
        for values in out.values():np.testing.assert_array_equal(values[40:52],p[40:52])


if __name__=='__main__':unittest.main()
