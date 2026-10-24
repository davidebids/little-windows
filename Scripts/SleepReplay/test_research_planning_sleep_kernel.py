import sys
from pathlib import Path
import unittest

import numpy as np
from scipy.linalg import solve_triangular

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_sleep_kernel import completed_union, integrated_sleep, lag_features, penalty, SleepKernelHazard, LAG_BINS, replay


class SleepKernelTests(unittest.TestCase):
    def test_union_and_integral_do_not_double_count_overlaps(self):
        sleeps=np.array([[-3600,-3000],[0,600],[300,900],[930,1000]],float)
        union=completed_union(sleeps,900)
        np.testing.assert_array_equal(union,[[-3600,-3000],[0,900]])
        np.testing.assert_array_equal(integrated_sleep(union,np.array([-4000,-3300,-3000,0,450,900,1200])),[0,300,600,600,1050,1500,1500])

    def test_fractional_edges_shift_one_minute_and_future_sleep_is_absent(self):
        sleeps=np.array([[-3600,-3000],[0,600],[300,900],[930,1000]],float)
        H=lag_features(sleeps,900,np.array([0,1,16]))
        np.testing.assert_allclose(H[:,0],[1.,14/15,0.],rtol=0,atol=1e-14)
        self.assertAlmostEqual(H[2,1],14/15)
        without_future=lag_features(sleeps[:-1],900,np.array([0,1,16]))
        np.testing.assert_array_equal(H,without_future)
        self.assertTrue(np.isnan(H[0,5]))
        self.assertEqual(H.shape,(3,LAG_BINS))

    def test_physical_penalty_gradient_and_preconditioned_form_agree(self):
        rng=np.random.default_rng(42);static=2;bins=6;width=static+bins
        scale=rng.uniform(.1,1,width);theta=rng.normal(size=1+2*width)
        model=SleepKernelHazard(static,bins)
        physical=theta.copy()
        physical[1+static:1+width]=solve_triangular(model.lag_factor.T,theta[1+static:1+width],lower=False)*scale[static:]
        value,gradient=penalty(physical,scale,static,bins)
        ordinary=np.r_[np.arange(1,1+static),np.arange(1+width,len(theta))]
        expected=.05*np.dot(theta[ordinary],theta[ordinary])+.5*np.dot(theta[1+static:1+width],theta[1+static:1+width])
        self.assertAlmostEqual(value,expected,places=10)
        eps=1e-6
        for j in range(len(physical)):
            plus=physical.copy();minus=physical.copy();plus[j]+=eps;minus[j]-=eps
            numerical=(penalty(plus,scale,static,bins)[0]-penalty(minus,scale,static,bins)[0])/(2*eps)
            self.assertAlmostEqual(gradient[j],numerical,places=5)

    def test_real_fit_predicts_finite_and_preconditioning_preserves_logits(self):
        rng=np.random.default_rng(42);static=2;bins=6
        X=rng.uniform(0,1,(100,static+bins));X[::9,-1]=np.nan
        y=(rng.random(100)<.2).astype(float)
        a=SleepKernelHazard(static,bins).fit(X,y,np.zeros(100),np.ones(100))
        b=SleepKernelHazard(static,bins).fit(X,y,np.zeros(100),np.ones(100))
        np.testing.assert_array_equal(a.predict(X[:3],np.zeros(3)),b.predict(X[:3],np.zeros(3)))
        fixed=np.where(np.isfinite(X),X,a.center)
        ordinary=np.column_stack([np.ones(len(X)),np.clip((fixed-a.center)/a.scale,-10,10),~np.isfinite(X)])
        beta=a.beta.copy();beta[1+static:1+static+bins]=solve_triangular(a.lag_factor.T,beta[1+static:1+static+bins],lower=False)*a.scale[static:]
        np.testing.assert_allclose(a.design(X)@a.beta,ordinary@beta,rtol=0,atol=1e-12)
        self.assertTrue(np.isfinite(a.predict(X,np.zeros(100))).all())

    def test_physical_future_sleep_truncation_preserves_every_past_query(self):
        sleeps=np.array([[-90000,-89000],[-3000,-2000],[0,600],[1500,1800],[2400,2700]],float)
        wakes=np.array([600,1800])
        for now in wakes:
            full=lag_features(sleeps,now,np.arange(480))
            prefix=lag_features(sleeps[sleeps[:,1]<=now],now,np.arange(480))
            np.testing.assert_array_equal(full,prefix)

    def test_real_replay_prefix_and_current_outcome_are_isolated(self):
        n=7;wakes=np.arange(n)*5400.
        d=dict(X=np.column_stack([np.arange(n),np.zeros(n)]),y=np.full(n,60.),wakes=wakes)
        c=dict(X=np.zeros((n,11)),knownAt=wakes+5400,labels=np.ones(n),wakeClock=np.full(n,600.))
        base=np.full(n,60.);sleeps=np.column_stack([wakes-1800,wakes])
        full,diag=replay(d,c,base,sleeps)
        self.assertEqual(diag['refits'][0]['query'],3)
        cut=5;ds={k:v[:cut] for k,v in d.items()};cs={k:v[:cut] for k,v in c.items()}
        prefix,pdiag=replay(ds,cs,base[:cut],sleeps[:cut])
        for name in full:np.testing.assert_array_equal(full[name][:cut],prefix[name])
        self.assertEqual([r for r in diag['refits'] if r['query']<cut],pdiag['refits'])
        altered={k:v.copy() for k,v in d.items()};altered['y'][cut-1:]=120
        cc={k:v.copy() for k,v in c.items()};cc['labels'][cut-1:]=2
        changed,_=replay(altered,cc,base,sleeps)
        for name in full:np.testing.assert_array_equal(full[name][:cut],changed[name][:cut])


if __name__=='__main__':unittest.main()
