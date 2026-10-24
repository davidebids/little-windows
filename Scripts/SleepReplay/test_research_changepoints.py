import sys
from pathlib import Path
import unittest
import numpy as np
from scipy.stats import t
sys.path.insert(0,str(Path(__file__).parents[1]))
from research_sleep_changepoints import RunLengthModel,calendar_hazard,groups,replay


def batch_parameters(values,sd):
    if not len(values):return 0.,.5,2.,sd**2/3
    x=np.array(values);n=len(x);mean=x.mean()
    return n*mean/(.5+n),.5+n,2+n/2,sd**2/3+np.sum((x-mean)**2)/2+.5*n*mean**2/(2*(.5+n))


class ChangePointTests(unittest.TestCase):
    def test_sequential_parameters_and_density_match_batch_suffixes(self):
        values=[2.,-3.,8.,4.];m=RunLengthModel(2.)
        for x in values:m.update(x,.15)
        for r in range(len(values)+1):
            expected=batch_parameters(values[-r:] if r else [],2.)
            np.testing.assert_allclose([m.mu[r],m.kappa[r],m.alpha[r],m.beta[r]],expected,atol=1e-12)
        scale=np.sqrt(m.beta*(m.kappa+1)/(m.alpha*m.kappa))
        np.testing.assert_allclose(m.log_density(.5),t.logpdf(.5,df=2*m.alpha,loc=m.mu,scale=scale),atol=1e-12)

    def test_messages_match_exhaustive_partition_enumeration_and_median(self):
        values=[0.,.2,-.1,5.,5.2,4.9];hazard=.15;paths=[(1.,[])];m=RunLengthModel(2.)
        for x in values:
            updated=[]
            for mass,run in paths:
                mu,k,a,b=batch_parameters(run,2.);density=t.pdf(x,df=2*a,loc=mu,scale=np.sqrt(b*(k+1)/(a*k)))
                updated.extend([(mass*density*hazard,[]),(mass*density*(1-hazard),run+[x])])
            paths=updated;m.update(x,hazard)
        expected=np.zeros(len(values)+1)
        for mass,run in paths:expected[len(run)]+=mass
        expected/=expected.sum();np.testing.assert_allclose(np.exp(m.logp),expected,atol=1e-12)
        mean,median=m.locations(.07);weights=np.exp(m.logp)*.93;weights[0]+=.07
        scale=np.sqrt(m.beta*(m.kappa+1)/(m.alpha*m.kappa))
        self.assertAlmostEqual(float(weights@t.cdf(median,df=2*m.alpha,loc=m.mu,scale=scale)),.5,places=8)
        self.assertAlmostEqual(mean,float(weights@m.mu),places=12)

    def test_no_change_symmetry_constant_reset_mass_and_calendar_composition(self):
        m=RunLengthModel(2.);c=RunLengthModel(2.)
        for x in [1.,2.,3.]:
            m.update(x,0.);c.update(x,.2);self.assertAlmostEqual(np.exp(c.logp[0]),.2,places=12)
        self.assertEqual(m.locations()[0],m.locations()[1]);self.assertEqual(np.exp(m.logp[-1]),1.)
        before=m.logp.copy();m.locations(.1);np.testing.assert_array_equal(before,m.logp)
        a=calendar_hazard(3600,7);b=calendar_hazard(7200,7)
        self.assertAlmostEqual(1-(1-a)*(1-b),calendar_hazard(10800,7),places=14)
        self.assertEqual(calendar_hazard(86400,None),0.)
        changed=RunLengthModel(2.);fixed=RunLengthModel(2.)
        for value in [0.]*30+[10.]*15:changed.update(value,.05);fixed.update(value,0.)
        self.assertGreater(changed.locations()[0],8.5);self.assertLess(fixed.locations()[0],4.)

    def test_roles_use_known_context_and_exact_minute_boundaries(self):
        minute=np.array([0,359,360,1259,1260]);phase=minute*2*np.pi/1440
        d=dict(names=['clockSin1','clockCos1','lastNight','napsToday'],X=np.column_stack([np.sin(phase),np.cos(phase),[0,0,1,0,0],[0,0,1,3,3]]))
        np.testing.assert_array_equal(groups(d,'roles'),[0,0,1,3,0])

    def test_pre_observation_reset_matches_partitions_and_conditions_on_surprise(self):
        values=[0.,.2,-.1,5.,5.2,4.9];hazard=.15;paths=[(1.,[])];m=RunLengthModel(2.,reset_before=True)
        mu,k,a,b=batch_parameters([],2.);prior_scale=np.sqrt(b*(k+1)/(a*k))
        for x in values:
            updated=[]
            for mass,run in paths:
                mu,k,a,b=batch_parameters(run,2.);density=t.pdf(x,df=2*a,loc=mu,scale=np.sqrt(b*(k+1)/(a*k)))
                reset_density=t.pdf(x,df=4,loc=0,scale=prior_scale)
                updated.extend([(mass*reset_density*hazard,[x]),(mass*density*(1-hazard),run+[x])])
            paths=updated;m.update(x,hazard)
        expected=np.zeros(len(values)+1)
        for mass,run in paths:expected[len(run)]+=mass
        expected/=expected.sum();np.testing.assert_allclose(np.exp(m.logp),expected,atol=1e-12)
        changed=RunLengthModel(2.,reset_before=True)
        for _ in range(30):changed.update(0.,.01)
        changed.update(10.,.01);self.assertGreater(np.exp(changed.logp[1]),.9)

    def test_all_forecasts_are_prefix_and_unavailable_label_isolated(self):
        n=100;i=np.arange(n);w=i*10800.;phase=i*.3;y=60+10*np.sin(i)
        d=dict(X=np.column_stack([np.sin(phase),np.cos(phase),60+np.cos(i),i%3==0,i%3]),names=['clockSin1','clockCos1','lastDuration','lastNight','napsToday'],y=y,wakes=w,available=w+y*60)
        d['available'][50]=1e20;base=np.full(n,60.)
        for before in [False,True]:
            full,diag=replay(d,base,reset_before=before)
            prefix={k:(v if k=='names' else v[:80]) for k,v in d.items()};short,_=replay(prefix,base[:80],reset_before=before)
            changed=dict(d,y=d['y'].copy());changed['y'][50]=99999;alter,_=replay(changed,base,reset_before=before)
            for name,p in full.items():np.testing.assert_array_equal(p[:80],short[name]);np.testing.assert_array_equal(p,alter[name]);self.assertTrue(np.isfinite(p).all())
            self.assertEqual(len(full),35)
            for item in diag.values():self.assertEqual(item['updatedLabels'],98);self.assertLess(item['maximumNormalizationError'],1e-12)
