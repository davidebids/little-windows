import sys
from pathlib import Path
import unittest
import numpy as np
from scipy.stats import t
sys.path.insert(0,str(Path(__file__).parents[1]))
from research_sleep_regression_changes import RegressionRuns,design,replay
from research_sleep_changepoints import RunLengthModel


def batch(X,y,precision=2.):
    p=X.shape[1]; prior=np.diag([.5]+[precision]*(p-1))
    covariance=np.linalg.inv(prior+X.T@X)
    mean=covariance@X.T@y
    return mean,covariance,2+len(y)/2,1/3+.5*(y@y-mean@np.linalg.solve(covariance,mean))


class RegressionChangeTests(unittest.TestCase):
    def test_every_sequential_suffix_matches_independent_batch(self):
        rng=np.random.default_rng(42); X=np.column_stack([np.ones(12),rng.normal(size=(12,3))]); y=rng.normal(size=12)
        model=RegressionRuns(4,16.)
        for i,(x,value) in enumerate(zip(X,y)):
            model.update(x,value,.1)
            for run in range(i+2):
                xx=X[i+1-run:i+1]; yy=y[i+1-run:i+1]
                mean,cov,a,b=batch(xx,yy,16.)
                np.testing.assert_allclose(model.mu[run],mean,atol=1e-12)
                np.testing.assert_allclose(model.cov[run],cov,atol=1e-12)
                self.assertAlmostEqual(model.alpha[run],a,places=12); self.assertAlmostEqual(model.beta[run],b,places=12)
        self.assertGreater(np.linalg.eigvalsh(model.cov).min(),0.)

    def test_run_messages_match_partition_enumeration_and_median_cdf(self):
        X=np.array([[1,0],[1,1],[1,-1],[1,.5],[1,-.5]],dtype=float); y=np.array([.1,.5,-.5,4.,-4.]); h=.15
        paths=[(1.,[])]; model=RegressionRuns(2)
        for i,(x,value) in enumerate(zip(X,y)):
            new=[]
            for mass,run in paths:
                mean,cov,a,b=batch(X[run],y[run]); loc=x@mean; scale=np.sqrt(b/a*(1+x@cov@x))
                likelihood=t.pdf(value,df=2*a,loc=loc,scale=scale)
                mean,cov,a,b=batch(X[:0],y[:0]); reset=t.pdf(value,df=2*a,loc=x@mean,scale=np.sqrt(b/a*(1+x@cov@x)))
                new.extend([(mass*h*reset,[i]),(mass*(1-h)*likelihood,run+[i])])
            paths=new; model.update(x,value,h)
        expected=np.zeros(len(y)+1)
        for mass,run in paths: expected[len(run)]+=mass
        expected/=expected.sum(); np.testing.assert_allclose(np.exp(model.logp),expected,atol=1e-12)
        x=np.array([1,.3]); mean,median=model.locations(x,.07); loc,df,s2,_,_=model.components(x)
        w=np.exp(model.logp)*.93; w[0]+=.07
        self.assertAlmostEqual(float(w@t.cdf(median,df=df,loc=loc,scale=np.sqrt(s2))),.5,places=8)
        self.assertAlmostEqual(mean,float(w@loc),places=12)

    def test_intercept_only_matches_scalar_model_and_immutable_prediction(self):
        scalar=RunLengthModel(1.,reset_before=True); regression=RegressionRuns(1)
        for value,h in zip([.1,-.4,.7,2.,3.],[0,.05,.2,.1,.03]):
            scalar.update(value,h); regression.update(np.ones(1),value,h)
            np.testing.assert_allclose(regression.mu[:,0],scalar.mu,atol=1e-12)
            np.testing.assert_allclose(regression.logp,scalar.logp,atol=1e-12)
            np.testing.assert_allclose(regression.locations(np.ones(1),.1),scalar.locations(.1),atol=1e-9)
        before=[v.copy() for v in [regression.mu,regression.cov,regression.logp]]
        regression.locations(np.ones(1),.7)
        for a,b in zip(before,[regression.mu,regression.cov,regression.logp]): np.testing.assert_array_equal(a,b)

    def test_conditional_slope_shift_adapts(self):
        model=RegressionRuns(2); fixed=RegressionRuns(2)
        for i in range(100):
            x=np.array([1.,(-1.)**i]); value=x[1]*(1. if i<60 else -3.)
            model.update(x,value,.03); fixed.update(x,value,0.)
        self.assertLess(model.locations(np.array([1.,1.]))[0],-2.8)
        self.assertGreater(fixed.locations(np.array([1.,1.]))[0],-1.)

    def test_fixed_features_and_replay_are_prefix_and_unavailable_label_isolated(self):
        names=['clockSin1','clockCos1','clockSin2','clockCos2','ageDays','lastDuration','lastNight','napsToday','wakeLag1',
            'sleepMinutes6h','sleepMinutes24h','lastFeedMinutes','FeedCount3h','homeostat120_60','homeostat240_120',
            'prior7d_clock_median','prior7d_clock_shortFraction','prior14d_kind_median']
        n=90; rng=np.random.default_rng(42); X=rng.normal(size=(n,len(names))); X[4,5]=np.nan
        y=60+10*np.sin(np.arange(n)); wakes=np.arange(n)*10800.; data=dict(X=X,names=names,y=y,wakes=wakes,available=wakes+y*60)
        data['available'][50]=1e20; base=np.full(n,60.)
        prefix={k:(v if k=='names' else v[:70]) for k,v in data.items()}
        for kind in ['clock','context']: np.testing.assert_array_equal(design(data,kind)[:70],design(prefix,kind))
        full,diag=replay(data,base); short,_=replay(prefix,base[:70]); changed=dict(data,y=y.copy()); changed['y'][50]=99999
        alternate,_=replay(changed,base)
        self.assertEqual(len(full),25)
        for name,p in full.items(): np.testing.assert_array_equal(p[:70],short[name]); np.testing.assert_array_equal(p,alternate[name])
        for item in diag.values():
            self.assertEqual(item['updatedLabels'],88); self.assertLess(item['normalizationError'],1e-12)
            self.assertEqual(item['maximumCovarianceAsymmetry'],0.); self.assertGreater(item['minimumFinalCovarianceEigenvalue'],0.)
