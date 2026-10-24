import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0, str(Path(__file__).parents[1]))
from research_sleep_sequence_prior import CONTEXT_NAMES
from research_sleep_sequence_head import embedding_query, representations, fit_ridge, predict_ridge, heads


class SequenceHeadTests(unittest.TestCase):
    def fixture(self):
        n=100
        return dict(y=np.arange(n, dtype=float)+10, wakes=np.arange(n)*3600.,
            available=np.arange(n)*3600.+600,
            X=np.repeat(np.arange(n, dtype=float)[:,None], len(CONTEXT_NAMES), axis=1), names=CONTEXT_NAMES)

    def test_encoder_query_is_resolved_past_only(self):
        d=self.fixture();d['available'][55]=1e10
        q=embedding_query(d,60,True)
        self.assertNotIn(65,q[0]);self.assertNotIn(70,q[0])
        self.assertEqual(q.shape[0],8)
        self.assertEqual(q[1,-1],59)
        a=dict(d,y=d['y'].copy());a['y'][[55,60]]=9999
        np.testing.assert_array_equal(q,embedding_query(a,60,True))

    def test_weighted_ridge_constant_and_predict_query_does_not_mutate_fit(self):
        z=np.ones((50,768));x=np.ones((50,7));target=np.column_stack([np.full(50,75.),np.full(50,15.)])
        fit=fit_ridge(z,x,target,np.ones(50),.1)
        np.testing.assert_allclose(predict_ridge(fit,z[0],x[0]),[75,15],rtol=0,atol=1e-10)
        before=[v.copy() for v in fit[0][0]]
        predict_ridge(fit,z[0]*100,x[0]*100)
        for a,b in zip(before,fit[0][0]):np.testing.assert_array_equal(a,b)

    def test_missing_training_and_query_context_uses_only_training_means(self):
        rng=np.random.default_rng(4);z=rng.normal(size=(50,768));x=rng.normal(size=(50,7))
        x[:20,0]=np.nan;x[:,1]=np.nan
        target=np.column_stack([np.arange(50),np.full(50,10.)])
        fit=fit_ridge(z,x,target,np.ones(50),.1)
        self.assertEqual(fit[0][1][0][1],0.)
        self.assertAlmostEqual(fit[0][1][0][0],np.mean(x[20:,0]))
        query=x[-1].copy();query[[0,1]]=np.nan
        prediction=predict_ridge(fit,z[-1],query)
        self.assertTrue(np.isfinite(prediction).all())
        self.assertAlmostEqual(prediction[1],10.)

    def test_encoder_and_supervised_prefix_and_unknown_label_isolation(self):
        d=self.fixture();d['available'][1]=1e10
        encode=lambda q: np.full(768,float(np.mean(q)))
        Z=representations(d,encode);fallback=np.full(100,60.)
        full,counts=heads(d,Z,fallback)
        p={k:v[:75] if k!='names' else v for k,v in d.items()}
        short,_=heads(p,{k:v[:75] for k,v in Z.items()},fallback[:75])
        a=dict(d,y=d['y'].copy());a['y'][1]=9999
        changed,_=heads(a,representations(a,encode),fallback)
        for name,v in full.items():
            np.testing.assert_allclose(v[:75],short[name],rtol=0,atol=1e-10)
            np.testing.assert_allclose(v,changed[name],rtol=0,atol=1e-10)
            self.assertEqual(counts[name],3)
            np.testing.assert_array_equal(v[:49],fallback[:49])
