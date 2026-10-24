import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0, str(Path(__file__).parents[1]))
from research_sleep_categorical_changes import CategoricalRuns, decisions, replay


class CategoricalChangeTests(unittest.TestCase):
    def test_messages_and_predictive_match_exhaustive_partitions(self):
        prior = np.array([.4, 1.2, .4]); paths = [(1., [])]; m = CategoricalRuns(prior)
        for x, h in zip([1,1,0,2,2,2], [0,.1,.2,.1,.3,.1]):
            new = []
            for mass, run in paths:
                counts = np.bincount(run, minlength=3)
                likelihood = (prior[x]+counts[x])/(prior.sum()+len(run))
                new.extend([(mass*h*prior[x]/prior.sum(), [x]), (mass*(1-h)*likelihood, run+[x])])
            paths = new; m.update(x,h)
            expected = np.zeros(m.count+1); predictive = np.zeros(3)
            for mass, run in paths:
                expected[len(run)] += mass
                predictive += mass*(prior+np.bincount(run,minlength=3))/(prior.sum()+len(run))
            predictive /= expected.sum(); expected /= expected.sum()
            np.testing.assert_allclose(np.exp(m.logp),expected,atol=1e-13)
            np.testing.assert_allclose(m.predictive(),predictive,atol=1e-13)
            np.testing.assert_allclose(m.predictive(.2),.8*predictive+.2*prior/prior.sum(),atol=1e-13)

    def test_no_change_is_exact_dirichlet_and_prediction_does_not_mutate(self):
        m = CategoricalRuns([1,2,1]); values = [0,1,2,2]
        for x in values: m.update(x,0.)
        np.testing.assert_allclose(m.predictive(),(np.array([1,2,1])+np.bincount(values,minlength=3))/8)
        old = m.logp.copy(); counts = m.counts.copy(); m.predictive(.7)
        np.testing.assert_array_equal(old,m.logp); np.testing.assert_array_equal(counts,m.counts)

    def test_piecewise_uniform_decisions_against_dense_integration(self):
        edges=np.arange(-100.,101.,5.); rng=np.random.default_rng(42)
        for _ in range(8):
            mass=rng.dirichlet(np.ones(40)); median, point=decisions(mass,edges,-83.,94.)
            cdf=np.r_[0,np.cumsum(mass)]
            self.assertAlmostEqual(float(np.interp(median,edges,cdf)),.5,places=12)
            candidates=np.linspace(-83,94,50001)
            coverage=np.interp(candidates+30,edges,cdf)-np.interp(candidates-30,edges,cdf)
            actual=np.interp(point+30,edges,cdf)-np.interp(point-30,edges,cdf)
            self.assertGreaterEqual(actual+1e-12,float(coverage.max()))
        np.testing.assert_allclose(decisions(np.ones(40)/40,edges,-10,10),(0.,0.),atol=1e-12)

    def test_mean_shift_is_adapted_without_future_observations(self):
        changed=CategoricalRuns([1,1,1]); fixed=CategoricalRuns([1,1,1])
        for value in [0]*40+[2]*20: changed.update(value,.03); fixed.update(value,0.)
        self.assertGreater(changed.predictive()[2],.85); self.assertLess(fixed.predictive()[2],.4)

    def test_prefix_and_unavailable_labels_are_isolated(self):
        n=90; i=np.arange(n); wakes=i*10800.; y=60+10*np.sin(i)
        data=dict(X=np.column_stack([np.sin(i),np.cos(i),60+np.cos(i),i%3==0,i%3]),
            names=['clockSin1','clockCos1','lastDuration','lastNight','napsToday'],y=y,wakes=wakes,available=wakes+y*60)
        data['available'][50]=1e20; base=np.full(n,60.)
        full,diag=replay(data,base)
        prefix={k:(v if k=='names' else v[:70]) for k,v in data.items()}; short,_=replay(prefix,base[:70])
        changed=dict(data,y=y.copy()); changed['y'][50]=99999; alternate,_=replay(changed,base)
        self.assertEqual(len(full),41)
        for name,p in full.items():
            np.testing.assert_array_equal(p[:70],short[name]); np.testing.assert_array_equal(p,alternate[name])
            self.assertTrue(np.all((p>=1)&(p<=480)))
        for item in diag.values(): self.assertEqual(item['updatedLabels'],88)
