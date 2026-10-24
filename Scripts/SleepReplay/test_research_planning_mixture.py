import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_mixture import distribution,mixture_point,replay
from research_sleep_predictions import WakeAnalogs
from research_sleep_behavior_schedule import weighted_median


class PlanningMixtureTests(unittest.TestCase):
    def test_leaf_distribution_matches_existing_forest_median(self):
        rng=np.random.default_rng(42);X=rng.normal(size=(70,4));X[::5,1]=np.nan;y=100+30*X[:,0]
        forest=WakeAnalogs('forest',5).fit(X,y)
        for row in X[:4]:
            values,mass=distribution(forest,row[None,:]);self.assertAlmostEqual(float(mass.sum()),1.)
            self.assertTrue((mass>0).all());self.assertAlmostEqual(weighted_median(values,mass),forest.predict(row[None,:])[0])

    def test_mixture_median_differs_from_selecting_most_likely_type(self):
        parts=[(np.array([40.,100.]),np.array([.6,.4]),.6),(np.array([120.]),np.array([1.]),.4)]
        self.assertEqual(mixture_point(parts),100.)
        self.assertEqual(mixture_point([(*parts[0][:2],1.),(*parts[1][:2],0.)]),40.)
        with self.assertRaises(ValueError):mixture_point([])

    def test_miss_penalty_optimum_matches_exhaustive_minute_grid(self):
        values=np.array([30.,70.,90.,130.,200.]);mass=np.array([.1,.25,.2,.35,.1])
        for penalty in [30.,90.]:
            p=mixture_point([(values,mass,1.)],penalty)
            risk=lambda point:float(np.sum(mass*(abs(values-point)+penalty*(abs(values-point)>30))))
            self.assertAlmostEqual(risk(p),min(risk(v) for v in range(1,481)),places=10)
        self.assertEqual(mixture_point([(np.array([30.,90.]),np.array([.5,.5]),1.)],90.),60.)
        with self.assertRaises(ValueError):mixture_point([(values,mass,1.)],-1.)

    def test_prefix_and_unavailable_current_future_outcome_isolation(self):
        n=90;i=np.arange(n);wakes=1e6+i*86400.;y=80.+i%40
        X=np.zeros((n,11));X[:,0]=i;X[:,4:6]=60;X[:,6]=1;X[:,3]=i%2
        d=dict(X=X.copy(),y=y,wakes=wakes);c=dict(X=X,labels=1+i%2,knownAt=wakes+y*60+3600,wakeClock=np.full(n,600.),targetClock=600+y)
        c['knownAt'][30]=1e20;base=np.full(n,110.)
        full,_=replay(d,c,base);prefix,_=replay({k:v[:75] for k,v in d.items()},{k:v[:75] for k,v in c.items()},base[:75])
        d2={k:v.copy() for k,v in d.items()};c2={k:v.copy() for k,v in c.items()};d2['y'][30]=9999;c2['labels'][30]=0;c2['targetClock'][30]=0
        altered,_=replay(d2,c2,base)
        for name in full:
            np.testing.assert_array_equal(full[name][:75],prefix[name]);np.testing.assert_array_equal(full[name],altered[name])
        d2['y'][74:]=1;c2['labels'][74:]=0;c2['targetClock'][74:]=0
        changed,_=replay(d2,c2,base)
        for name in full:np.testing.assert_array_equal(full[name][:75],changed[name][:75])

if __name__=='__main__':unittest.main()
