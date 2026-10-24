import sys
from pathlib import Path
import unittest
import numpy as np
from scipy.stats import norm,laplace,t
sys.path.insert(0,str(Path(__file__).parents[1]))
from research_sleep_robust_filter import LocationFilter,observation_logpdf,observation_cdf,replay


class RobustFilterTests(unittest.TestCase):
    def test_observation_densities_cdfs_and_variances_match_reference(self):
        x=np.array([-10000.,-60.,0.,60.,10000.])
        references=dict(normal=norm(scale=60),laplace=laplace(scale=60/np.sqrt(2)),student3=t(df=3,scale=60/np.sqrt(3)))
        for family,reference in references.items():
            np.testing.assert_allclose(observation_logpdf(x,family),reference.logpdf(x),atol=1e-12)
            np.testing.assert_allclose(observation_cdf(x,family),reference.cdf(x),atol=1e-14)
            self.assertAlmostEqual(reference.std(),60.,places=12)

    def test_collapsed_filter_matches_exhaustive_partition_mixture(self):
        grid=np.array([-20.,0.,30.]); values=[0.,10.,-10.,80.,-50.,0.]
        for family in ['normal','laplace','student3']:
            model=LocationFilter(family,grid); prior=np.exp(model.logprior); paths=[(1.,prior)]
            for value,h in zip(values,[0,.1,.2,.3,.1,.05]):
                likelihood=np.exp(observation_logpdf(value-grid,family)); new=[]
                for mass,posterior in paths:
                    for weight,q in [(1-h,posterior),(h,prior)]:
                        evidence=float(q@likelihood)
                        new.append((mass*weight*evidence,q*likelihood/evidence))
                paths=new; model.update(value,h)
                expected=sum(m*q for m,q in paths)/sum(m for m,q in paths)
                np.testing.assert_allclose(np.exp(model.logp),expected,atol=1e-13)
            mean,median=model.locations(.15); w=.85*np.exp(model.logp)+.15*prior
            self.assertAlmostEqual(mean,float(w@grid),places=12)
            self.assertAlmostEqual(float(w@observation_cdf(median-grid,family)),.5,places=8)

    def test_no_change_matches_batch_likelihood_and_query_is_immutable(self):
        for family in ['normal','laplace','student3']:
            model=LocationFilter(family); values=[0.,10.,-10.,80.]
            for value in values: model.update(value,0.)
            logp=model.logprior+sum(observation_logpdf(value-model.grid,family) for value in values)
            logp-=np.logaddexp.reduce(logp)
            np.testing.assert_allclose(model.logp,logp,atol=1e-10)
            before=model.logp.copy(); model.locations(.7); np.testing.assert_array_equal(before,model.logp)
            self.assertEqual(model.count,4)

    def test_far_outlier_has_less_influence_and_sustained_shift_is_learned(self):
        changes={}
        for family in ['normal','laplace','student3']:
            model=LocationFilter(family)
            for _ in range(40): model.update(0.,0.)
            before=model.locations()[0]; model.update(5000.,0.)
            changes[family]=abs(model.locations()[0]-before); self.assertEqual(model.count,41)
            shifted=LocationFilter(family)
            for value in [0.]*30+[120.]*40: shifted.update(value,.03)
            self.assertGreater(shifted.locations()[0],100.)
        self.assertLess(changes['laplace'],changes['normal']/10)
        self.assertLess(changes['student3'],changes['normal']/10)

    def test_prefix_and_unavailable_labels_do_not_influence_predictions(self):
        n=90; i=np.arange(n); w=i*10800.; y=60+10*np.sin(i)
        data=dict(X=np.column_stack([np.sin(i),np.cos(i),60+np.cos(i),i%3==0,i%3]),names=['clockSin1','clockCos1','lastDuration','lastNight','napsToday'],y=y,wakes=w,available=w+y*60)
        data['available'][50]=1e20; base=np.full(n,60.)
        full,diag=replay(data,base)
        prefix={k:(v if k=='names' else v[:70]) for k,v in data.items()}; short,_=replay(prefix,base[:70])
        changed=dict(data,y=y.copy()); changed['y'][50]=99999; alternate,_=replay(changed,base)
        self.assertEqual(len(full),59)
        for name,p in full.items(): np.testing.assert_array_equal(p[:70],short[name]); np.testing.assert_array_equal(p,alternate[name])
        for item in diag.values(): self.assertEqual(item['updatedLabels'],88); self.assertLess(item['maximumNormalizationError'],1e-12)
