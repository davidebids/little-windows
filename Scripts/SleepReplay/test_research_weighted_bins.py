import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).parents[1]))
from sklearn.utils.stats import _weighted_percentile
from sklearn.ensemble._hist_gradient_boosting import binning
from sklearn.ensemble import HistGradientBoostingRegressor
from threadpoolctl import threadpool_limits
from sleep_weighted_bins import RANKS,grid_values,fast_weighted_bins


class WeightedBinsTests(unittest.TestCase):
    def test_grid_matches_native_scalar_percentiles_with_ties_and_weights(self):
        rng=np.random.default_rng(12)
        for kind in range(5):
            x=rng.normal(size=310);w=np.exp2(rng.uniform(-15,0,310))
            if kind==1:x=np.round(x,1)
            if kind==2:w[:]=1
            if kind==3:w[:]=1e-200
            if kind==4:w[:]=np.arange(310)+1
            expected=np.array([_weighted_percentile(x,w,r,average=True) for r in RANKS])
            np.testing.assert_array_equal(grid_values(x,w),expected)

    def test_native_bins_trees_and_predictions_are_identical(self):
        rng=np.random.default_rng(23);X=rng.normal(size=(410,8));X[::9,0]=np.nan
        y=X[:,1]*10+np.sin(X[:,2])*20;w=np.exp2(rng.uniform(-6,0,410));w[::15]=0
        query=rng.normal(size=(40,8));models=[]
        with threadpool_limits(limits=2):
            for enabled in [False,True]:
                with fast_weighted_bins(enabled):
                    model=HistGradientBoostingRegressor(loss='absolute_error',max_iter=20,
                        max_leaf_nodes=7,min_samples_leaf=15,early_stopping=False,random_state=42)
                    models.append(model.fit(X,y,sample_weight=w))
        for a,b in zip(models[0]._bin_mapper.bin_thresholds_,models[1]._bin_mapper.bin_thresholds_):
            np.testing.assert_array_equal(a,b)
        for aa,bb in zip(models[0]._predictors,models[1]._predictors):
            for a,b in zip(aa,bb):np.testing.assert_array_equal(a.nodes,b.nodes)
        np.testing.assert_array_equal(models[0].predict(query),models[1].predict(query))

    def test_fallback_and_exception_restore_dependency_binding(self):
        original=binning._weighted_percentile
        x=np.arange(300,dtype=np.float32);w=np.ones(300,dtype=np.float32)
        expected=original(x,w,RANKS[0],average=True)
        with self.assertRaises(RuntimeError):
            with fast_weighted_bins():
                self.assertEqual(binning._weighted_percentile(x,w,RANKS[0],average=True),expected)
                self.assertTrue(np.isnan(binning._weighted_percentile(x,w*0,50,average=True)))
                raise RuntimeError('neutral cleanup check')
        self.assertIs(binning._weighted_percentile,original)
