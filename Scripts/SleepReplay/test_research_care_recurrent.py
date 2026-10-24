import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).parents[1]))
from research_sleep_care_recurrent import sequence_view,fit_scale,normalized,fit_model,predict_model,replay
from research_sleep_care_alignment import care_patterns


class CareRecurrentTests(unittest.TestCase):
    def test_sequence_controls_remove_order_without_changing_shape(self):
        x=np.arange(2*16*11,dtype=float).reshape(2,16,11)
        np.testing.assert_array_equal(sequence_view(x,'context'),np.zeros_like(x))
        pooled=sequence_view(x,'pooled');self.assertEqual(pooled.shape,x.shape)
        np.testing.assert_array_equal(pooled,sequence_view(x[:,::-1],'pooled'))
        np.testing.assert_array_equal(sequence_view(x,'ordered'),x)
        self.assertFalse(np.array_equal(sequence_view(x,'ordered'),sequence_view(x[:,::-1],'ordered')))

    def test_weighted_scaling_handles_training_missingness_and_query_clipping(self):
        x=np.array([[1.,np.nan],[3.,10.]]);s=fit_scale(x,np.array([1.,3.]))
        np.testing.assert_allclose(s[0],[2.5,10]);np.testing.assert_allclose(s[1],[np.sqrt(.75),.05])
        result=normalized(np.array([[1e9,np.nan]]),s)
        np.testing.assert_array_equal(result,[[10,0]])

    def test_cold_fit_is_deterministic_and_finite(self):
        import torch
        torch.set_num_threads(2);torch.use_deterministic_algorithms(True)
        rng=np.random.default_rng(7);p=rng.normal(size=(24,16,11));c=rng.normal(size=(24,3));y=60+10*c[:,0];weights=np.linspace(.5,1,24)
        first=fit_model(p,c,y,weights,8);second=fit_model(p,c,y,weights,8)
        a=predict_model(first,p[:2],c[:2]);b=predict_model(second,p[:2],c[:2]);np.testing.assert_array_equal(a,b);self.assertTrue(np.isfinite(a).all())
        self.assertEqual(first[-1],second[-1])

    def test_replay_prefix_and_unavailable_labels_do_not_change_forecasts(self):
        n=120;i=np.arange(n);w=i*10800.;phase=i*.3;y=60+10*np.sin(i)
        d=dict(X=np.column_stack([np.sin(phase),np.cos(phase),60+np.cos(i)]),names=['clockSin1','clockCos1','lastDuration'],y=y,wakes=w,available=w+y*60)
        d['available'][50]=1e20;events=np.column_stack([w-600,w,i%7]);p=care_patterns(events,w,16);fallback=np.full(n,60.)
        full,diag=replay(d,p,fallback,epochs=2,minimum_labels=30,refit_every=24)
        prefix={k:(v if k=='names' else v[:90]) for k,v in d.items()};short,_=replay(prefix,p[:90],fallback[:90],epochs=2,minimum_labels=30,refit_every=24)
        changed=dict(d,y=d['y'].copy());changed['y'][50]=99999;alter,_=replay(changed,p,fallback,epochs=2,minimum_labels=30,refit_every=24)
        for name,v in full.items():np.testing.assert_array_equal(v[:90],short[name]);np.testing.assert_array_equal(v,alter[name])
        self.assertEqual(len(full),11)
        for item in diag.values():self.assertGreater(item['learnedQueries'],0)
