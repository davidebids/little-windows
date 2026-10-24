import sys
from pathlib import Path
import unittest
import numpy as np
from sklearn.linear_model import QuantileRegressor
sys.path.insert(0,str(Path(__file__).parents[1]))
from research_sleep_timing_curves import basis,curve_design,fit_median,wake_groups,replay


class TimingCurveTests(unittest.TestCase):
    def test_absolute_loss_penalty_matches_independent_quantile_regressor(self):
        rng=np.random.default_rng(42); raw=rng.normal(size=(45,3)); X=np.column_stack([np.ones(45),raw]); y=10+raw@np.array([3.,-1.,2.])+rng.normal(size=45); weights=rng.uniform(.2,1.,45)
        D=np.column_stack([np.zeros(3),np.eye(3)])
        coefficients,error=fit_median(X,y,weights,D,.1)
        reference=QuantileRegressor(quantile=.5,alpha=.05,solver='highs-ds').fit(raw,y,sample_weight=weights)
        a=X@coefficients; b=reference.predict(raw)
        objective=lambda p,c:np.average(abs(p-y),weights=weights)+.1*np.sum(abs(c))
        self.assertAlmostEqual(objective(a,coefficients[1:]),objective(b,reference.coef_),places=8)
        self.assertLess(error,1e-8)
        constant,err=fit_median(np.ones((3,1)),np.array([2.,8.,20.]),np.array([1.,5.,1.]),np.zeros((0,1)),.1)
        self.assertAlmostEqual(constant[0],8.,places=10)

    def test_basis_is_fixed_periodic_and_context_boundaries_use_wake_information(self):
        minute=np.array([0.,359.,360.,719.,720.,959.,960.,1259.,1260.,1440.]); X=np.zeros((len(minute),11)); X[:,0]=100; X[:,3]=1; X[:,4]=X[:,5]=40; X[:,6]=1
        context=dict(X=X,wakeClock=minute,ordinal=np.ones(len(minute)))
        design,D=basis(context); np.testing.assert_allclose(design[0],design[-1],atol=1e-12)
        short,_=basis({k:v[:7] for k,v in context.items()}); np.testing.assert_array_equal(design[:7],short)
        np.testing.assert_array_equal(wake_groups(context,True),[0,0,1,1,2,2,3,3,0,0])
        self.assertEqual(D.shape[1],design.shape[1]); self.assertTrue(np.isfinite(D).all())

    def test_shared_curves_embed_pooled_predictions_and_penalize_only_active_deviations(self):
        X=np.zeros((4,11)); X[:,0]=100; X[:,4]=X[:,5]=40; X[:,6]=1; X[:,3]=[1,1,0,0]
        context=dict(X=X,wakeClock=np.array([0.,600.,900.,1100.]),ordinal=np.ones(4))
        pooled,D=basis(context); shared,P,groups=curve_design(context,'shared'); p=pooled.shape[1]
        coef=np.arange(p,dtype=float)/p; full=np.r_[coef,np.zeros(4*p)]
        np.testing.assert_allclose(shared@full,pooled@coef,atol=1e-12)
        self.assertAlmostEqual(float(abs(P@full).sum()),float(abs(D@coef).sum()),places=12)
        full[p]=2.
        np.testing.assert_allclose(shared@full-pooled@coef,[2.,0.,0.,0.],atol=1e-12)
        self.assertGreater(float(abs(P@full).sum()),float(abs(D@coef).sum()))
        np.testing.assert_array_equal(groups,np.zeros(4))

    def test_prefix_and_unavailable_outcome_isolation(self):
        n=90; i=np.arange(n); wakes=i*21600.; y=60+10*np.sin(i); rng=np.random.default_rng(42)
        X=rng.uniform(size=(n,11)); X[:,0]=i; X[:,4]=X[:,5]=30+30*X[:,5]; X[:,3]=i%2
        context=dict(X=X,wakeClock=(i*137.)%1440,ordinal=i%4); data=dict(wakes=wakes,available=wakes+y*60,y=y); base=np.full(n,60.)
        data['available'][50]=1e20; full,diag=replay(data,context,base)
        short,_=replay({k:v[:70] for k,v in data.items()},{k:v[:70] for k,v in context.items()},base[:70])
        altered=dict(data,y=y.copy()); altered['y'][50]=99999; changed,_=replay(altered,context,base)
        self.assertEqual(len(full),12)
        for name,p in full.items():
            np.testing.assert_array_equal(p[:70],short[name]); np.testing.assert_array_equal(p,changed[name])
            self.assertTrue(np.all((p>=1)&(p<=480)))
        for item in diag.values(): self.assertEqual(item['learnedQueries']+item['fallbackQueries'],n); self.assertLess(item['maximumEqualityResidual'],1e-6)
