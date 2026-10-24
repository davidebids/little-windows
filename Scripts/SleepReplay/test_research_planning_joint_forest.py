import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_joint_forest import centers,risks,decision,JointForest,replay


class JointForestTests(unittest.TestCase):
    def test_batch_risk_matches_direct_loss_at_float_boundaries(self):
        rng=np.random.default_rng(42)
        for _ in range(12):
            y=np.r_[rng.uniform(1,480,15),.1,30.1,60.1];w=rng.uniform(0,2,(4,len(y)));w[0,::2]=0
            points=centers(y)
            for penalty in [0,30]:
                actual=risks(y,w,points,penalty)
                loss=abs(points[:,None]-y[None,:]);expected=w@(loss+penalty*(loss>30)).T
                np.testing.assert_allclose(actual,expected,rtol=0,atol=2e-10)

    def test_decision_attains_dense_grid_optimum_and_median(self):
        rng=np.random.default_rng(17)
        for _ in range(20):
            y=rng.integers(1,250,8).astype(float);w=rng.uniform(0,1,len(y));p=decision(y,w,30)
            error=abs(p-y);risk=float(w@(error+30*(error>30)))
            grid=np.arange(1,481,.25);loss=abs(grid[:,None]-y)
            self.assertLessEqual(risk,float(((loss+30*(loss>30))@w).min())+1e-8)
        self.assertEqual(decision([1,2,3,4,10000],[1,1,1,1,1],0),3.)
        self.assertEqual(decision([60.1],[1.],30),60.1)

    def test_forest_neighborhood_mass_and_deterministic_fit(self):
        rng=np.random.default_rng(42);x=rng.normal(size=(35,4));x[:,3]=np.nan;x[::4,1]=np.nan;y=rng.uniform(1,300,len(x))
        a=JointForest(30,trees=3).fit(x,y);b=JointForest(30,trees=3).fit(x,y)
        np.testing.assert_array_equal(a.weights(x),b.weights(x));np.testing.assert_allclose(a.weights(x).sum(axis=1),1.,rtol=0,atol=1e-14)
        np.testing.assert_array_equal(a.predict(x,30),b.predict(x,30))
        self.assertTrue(all(len(node['members'])>=5 for tree in a.trees for node in tree if 'members' in node))

    def fixture(self,n=60):
        rng=np.random.default_rng(42);w=100000+np.arange(n)*7200.
        return dict(wakes=w,y=100+rng.integers(-50,50,n).astype(float),X=rng.normal(size=(n,4))),dict(knownAt=w+600,labels=np.ones(n,int),X=np.zeros((n,11))),np.full(n,100.)

    def test_real_forest_prefix_current_and_future_isolation(self):
        d,c,p=self.fixture();full,diag=replay(d,c,p,trees=2);cut=43
        prefix,_=replay({k:v[:cut] for k,v in d.items()},{k:v[:cut] for k,v in c.items()},p[:cut],trees=2)
        d['y'][cut-1:]=9999;c['labels'][cut-1:]=0
        changed,_=replay(d,c,p,trees=2)
        for name in full:
            np.testing.assert_array_equal(full[name][:cut],prefix[name]);np.testing.assert_array_equal(full[name][:cut],changed[name][:cut]);np.testing.assert_array_equal(full[name][:3],p[:3])
        self.assertGreater(len(diag['refits']),0)

    def test_maturity_expiry_and_sparse_fallback(self):
        d,c,p=self.fixture(15);c['knownAt'][:]=d['wakes'][-1]+86400
        out,diag=replay(d,c,p,trees=2)
        for values in out.values():np.testing.assert_array_equal(values,p)
        self.assertEqual(diag['refits'],[])
        d,c,p=self.fixture(15);d['wakes'][10:]+=61*86400;c['knownAt'][10:]+=61*86400
        out,_=replay(d,c,p,trees=2)
        for values in out.values():np.testing.assert_array_equal(values[10:13],p[10:13])


if __name__=='__main__':unittest.main()
