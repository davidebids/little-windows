import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_feed_path import feed_targets,distribution,marginal,replay
from research_sleep_predictions import WakeAnalogs
from research_sleep_behavior_schedule import weighted_median


class FeedPathTests(unittest.TestCase):
    def test_feed_targets_decompose_and_ignore_later_completions(self):
        events=np.array([[0,1500,1],[3000,4000,1],[4000,6000,1]],float)
        d=dict(wakes=np.array([1000.,3500.,7000.]),available=np.array([2000.,5000.,9000.]),y=np.array([1000.,1500.,2000.])/60)
        t=feed_targets(events,d);np.testing.assert_array_equal(t['hasFeed'],[True,True,False])
        np.testing.assert_allclose(t['delay'][:2],[500/60,500/60]);np.testing.assert_allclose(t['post'][:2],[500/60,1000/60])
        earlier=feed_targets(events[events[:,1]<=5000],d)
        for key in t:np.testing.assert_array_equal(t[key][:2],earlier[key][:2])

    def test_forest_distribution_matches_existing_median(self):
        rng=np.random.default_rng(42);x=rng.normal(size=(40,4));x[:,3]=np.nan;x[::4,1]=np.nan;y=rng.uniform(1,300,len(x))
        model=WakeAnalogs('forest',5).fit(x,y);mass=distribution(model,x[:8])
        np.testing.assert_allclose(mass.sum(axis=1),1.,rtol=0,atol=1e-14)
        np.testing.assert_array_equal([weighted_median(y,w) for w in mass],model.predict(x[:8]))

    def test_exact_conditioned_marginal_preserves_dependence(self):
        first=np.array([10.,20.]);mass=np.array([.25,.75]);post=np.array([40.,50.]);conditional=np.array([[0.,1.],[1.,0.]])
        values,w=marginal(first,mass,post,conditional,True)
        self.assertAlmostEqual(w.sum(),1.);self.assertEqual(weighted_median(values,w),60.)
        direct,weights=marginal(first,mass,np.array([60.,70.]),conditional,False)
        self.assertEqual(weighted_median(direct,weights),60.)
        with self.assertRaises(ValueError):marginal(first,mass,post,np.ones((3,2)),True)

    def fixture(self,n=24):
        rng=np.random.default_rng(42);w=100000+np.arange(n)*10800.;y=100+rng.integers(-40,40,n).astype(float)
        d=dict(wakes=w,y=y,available=w+y*60,X=rng.normal(size=(n,3)))
        c=dict(knownAt=d['available']+1800,labels=np.ones(n,int),X=np.zeros((n,11)))
        has=np.arange(n)%2==0;t=dict(hasFeed=has,delay=np.where(has,y*.4,np.nan),post=np.where(has,y*.6,np.nan))
        return d,c,np.full(n,100.),t

    def test_real_paths_prefix_and_current_future_target_isolation(self):
        d,c,b,t=self.fixture();full,diag=replay(d,c,b,t);cut=21
        pre,_=replay({k:v[:cut] for k,v in d.items()},{k:v[:cut] for k,v in c.items()},b[:cut],{k:v[:cut] for k,v in t.items()})
        d['y'][cut-1:]=9999;c['labels'][cut-1:]=0;t['hasFeed'][cut-1:]=~t['hasFeed'][cut-1:];t['delay'][cut-1:]=99999;t['post'][cut-1:]=99999
        changed,_=replay(d,c,b,t)
        for name in full:
            np.testing.assert_array_equal(full[name][:cut],pre[name]);np.testing.assert_array_equal(full[name][:cut],changed[name][:cut])
        self.assertGreater(diag['mediatedQueries'],0)
        self.assertTrue(np.any(full['predictedFeedDecomposed']!=full['planningForestControl']))

    def test_unresolved_and_expired_history_keep_fallback(self):
        d,c,b,t=self.fixture();c['knownAt'][:]=d['wakes'][-1]+86400
        out,_=replay(d,c,b,t)
        for values in out.values():np.testing.assert_array_equal(values,b)
        d,c,b,t=self.fixture();d['wakes'][18:]+=61*86400;c['knownAt'][18:]+=61*86400
        out,_=replay(d,c,b,t)
        for values in out.values():np.testing.assert_array_equal(values[18:21],b[18:21])

    def test_single_observed_feeding_class_can_learn_early(self):
        d,c,b,t=self.fixture(9);t=dict(hasFeed=np.ones(9,bool),delay=d['y']*.4,post=d['y']*.6)
        out,diag=replay(d,c,b,t)
        self.assertTrue(diag['refits'][0]['pathEnabled'])
        self.assertEqual(diag['refits'][0]['feedingLabels'],3)
        self.assertEqual(diag['refits'][0]['noFeedLabels'],0)
        self.assertGreater(diag['mediatedQueries'],0)
        self.assertTrue(np.isfinite(out['predictedFeedDecomposed']).all())


if __name__=='__main__':unittest.main()
