import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_tracking import update,replay

class TrackingTests(unittest.TestCase):
    def fixture(self):
        n=36;w=np.arange(n,dtype=float)*86400
        d=dict(wakes=w,y=np.full(n,90.))
        c=dict(knownAt=w+3600,wakeClock=np.full(n,600.),labels=np.ones(n,int),X=np.zeros((n,11)))
        c['X'][:,3]=0
        return d,c,np.tile([120.,90.,60.],(n,1))
    def test_manual_update_and_off_diagonal_share(self):
        w=np.array([.5,.5]);loss=np.array([0.,60.]);q=np.exp(-1);p=np.array([1,q])/(1+q)
        np.testing.assert_allclose(update(w,loss,0),p,rtol=0,atol=1e-15)
        np.testing.assert_allclose(update(w,loss,.1),.9*p+.1*p[::-1],rtol=0,atol=1e-15)
        with self.assertRaises(ValueError):update([1],[0],.1)
    def test_current_future_outcomes_and_prefix_invariance(self):
        d,c,m=self.fixture();full,_=replay(d,c,m);cut=20
        prefix,_=replay({k:v[:cut] for k,v in d.items()},{k:v[:cut] for k,v in c.items()},m[:cut])
        d['y'][cut-1:]=999;c['labels'][cut-1:]=2;m[cut:]=400
        changed,_=replay(d,c,m)
        for k in full:
            np.testing.assert_array_equal(full[k][:cut],prefix[k]);np.testing.assert_array_equal(full[k][:cut],changed[k][:cut])
    def test_delayed_feedback_and_overnight_fallback(self):
        d,c,m=self.fixture();c['knownAt'][:]=1e20
        p,diag=replay(d,c,m)
        for k in p:np.testing.assert_array_equal(p[k],m[:,0]);self.assertEqual(diag[k]['resolvedLabels'],0)
        d,c,m=self.fixture();c['wakeClock'][-1]=120
        p,_=replay(d,c,m)
        for k in p:self.assertEqual(p[k][-1],120)
    def test_context_switch_and_completion_order(self):
        d,c,m=self.fixture();c['knownAt'][0]=d['wakes'][12]+1
        c['wakeClock'][18:]=1100;d['y'][18:]=60
        p,diag=replay(d,c,m)
        for k in p:
            self.assertTrue(np.isfinite(p[k]).all());self.assertEqual(diag[k]['resolvedLabels'],35)
        self.assertGreater(diag['contextShareAbsolute']['finalWeights'][2][1],diag['contextShareAbsolute']['finalWeights'][2][2])
        self.assertGreater(diag['contextShareAbsolute']['finalWeights'][3][2],diag['contextShareAbsolute']['finalWeights'][3][1])

if __name__=='__main__':unittest.main()
