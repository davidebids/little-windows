import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_split_loss import SplitForest,replay
from research_sleep_predictions import WakeAnalogs


class SplitLossTests(unittest.TestCase):
    def fixture(self,n=60):
        w=100000+np.arange(n)*7200.;rng=np.random.default_rng(42)
        return dict(wakes=w,y=100+rng.integers(-50,50,n).astype(float),X=rng.normal(size=(n,4))),dict(knownAt=w+600,labels=np.ones(n,int),X=np.zeros((n,11))),np.full(n,100.)

    def test_squared_control_and_leaf_median_with_missing_columns(self):
        rng=np.random.default_rng(42);x=rng.normal(size=(40,4));x[::3,1]=np.nan;x[:,3]=np.nan;y=rng.uniform(1,300,40)
        old=WakeAnalogs('forest',5).fit(x,y);new=SplitForest('squared_error').fit(x,y)
        np.testing.assert_array_equal(old.predict(x),new.predict(x))
        x=np.full((5,2),np.nan);y=np.array([1.,2.,3.,4.,10000.])
        for criterion in ['squared_error','absolute_error']:
            model=SplitForest(criterion).fit(x,y);np.testing.assert_array_equal(model.predict(x),np.full(5,3.))

    def test_real_forests_prefix_and_current_future_label_isolation(self):
        d,c,b=self.fixture();full,diag=replay(d,c,b);cut=42
        pre,_=replay({k:v[:cut] for k,v in d.items()},{k:v[:cut] for k,v in c.items()},b[:cut])
        d['y'][cut-1:]=9999;c['labels'][cut-1:]=0
        changed,_=replay(d,c,b)
        for name in full:
            np.testing.assert_array_equal(full[name][:cut],pre[name]);np.testing.assert_array_equal(full[name][:cut],changed[name][:cut])
            np.testing.assert_array_equal(full[name][:3],b[:3])
        self.assertGreater(len(diag['refits']),0)

    def test_unresolved_sparse_and_expired_labels(self):
        d,c,b=self.fixture(15);c['knownAt'][:]=d['wakes'][-1]+86400
        out,diag=replay(d,c,b)
        for values in out.values():np.testing.assert_array_equal(values,b)
        self.assertEqual(diag['refits'],[])
        d,c,b=self.fixture(15);d['wakes'][10:]+=61*86400;c['knownAt'][10:]+=61*86400
        out,_=replay(d,c,b)
        for values in out.values():np.testing.assert_array_equal(values[10:13],b[10:13])


if __name__=='__main__':unittest.main()
