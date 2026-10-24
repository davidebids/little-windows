import sys
from pathlib import Path
import unittest
import math
import numpy as np
sys.path.insert(0,str(Path(__file__).parents[1]))
from research_sleep_care_reservoir import reservoir_weights,encode_patterns,fit_lad,predict_lad,replay
from research_sleep_care_alignment import care_patterns


class CareReservoirTests(unittest.TestCase):
    def test_frozen_weights_are_contractive_and_encoder_is_prefix_local(self):
        W,U,b=reservoir_weights();np.testing.assert_allclose(W.T@W,.81*np.eye(64),atol=1e-12)
        rng=np.random.default_rng(1);P=rng.normal(size=(10,16,11));full=encode_patterns(P);short=encode_patterns(P[:6])
        for name,Z in full.items():np.testing.assert_array_equal(Z[:6],short[name])
        for key in ['reservoir_l0.3','reservoir_l1']:self.assertTrue((np.abs(full[key])<=1).all())
        altered=encode_patterns(P[:,::-1])
        self.assertFalse(np.array_equal(full['reservoir_l1'],altered['reservoir_l1']))

    def test_recurrence_matches_independent_scalar_evaluation(self):
        P=np.arange(2*3*11,dtype=float).reshape(2,3,11)/100
        W=.9*np.eye(3);U=np.full((3,11),.1);b=np.array([-.1,0,.1]);Z=encode_patterns(P,(W,U,b))
        for leak in [.3,1.]:
            expected=[]
            for rows in P:
                state=[0.,0.,0.]
                for raw in rows:
                    value=[v/np.sqrt(2) if k<8 else v/4 for k,v in enumerate(raw)]
                    state=[(1-leak)*state[j]+leak*math.tanh(.9*state[j]+sum(.1*v for v in value)+b[j]) for j in range(3)]
                expected.append(state)
            np.testing.assert_allclose(Z[f'reservoir_l{leak:g}'],expected,atol=1e-14)

    def test_lad_constant_readout_is_weighted_median_and_translation_equivariant(self):
        latent=np.zeros((5,1));context=np.zeros((5,1));y=np.array([0.,1,2,3,100]);target=np.column_stack([y,y+4]);w=np.array([1.,1,1,1,.01])
        fit=fit_lad(latent,context,target,w,.01);value=predict_lad(fit,latent[0],context[0]);np.testing.assert_allclose(value,[2,6],atol=1e-7)
        shifted=fit_lad(latent,context,target+17,w,.01);np.testing.assert_allclose(predict_lad(shifted,latent[0],context[0]),value+17,atol=1e-7)
        self.assertLess(fit[-1],1e-8)

    def test_lad_recovers_a_linear_signal_and_extrapolates_without_query_labels(self):
        x=np.arange(-2,3,dtype=float)[:,None];y=60+3*x[:,0];fit=fit_lad(np.zeros((5,1)),x,y[:,None],np.ones(5),.001)
        self.assertAlmostEqual(predict_lad(fit,np.zeros(1),np.array([3.]))[0],69,places=6)

    def test_forecasts_are_prefix_and_unavailable_label_isolated(self):
        n=90;i=np.arange(n);w=i*10800.;phase=i*.3;y=60+10*np.sin(i)
        d=dict(X=np.column_stack([np.sin(phase),np.cos(phase),60+np.cos(i)]),names=['clockSin1','clockCos1','lastDuration'],y=y,wakes=w,available=w+y*60)
        d['available'][50]=1e20;events=np.column_stack([w-600,w,i%7]);P=care_patterns(events,w,16);Z=encode_patterns(P);fallback=np.full(n,60.)
        full,diag=replay(d,Z,fallback)
        prefix={k:(v if k=='names' else v[:75]) for k,v in d.items()};short,_=replay(prefix,{k:v[:75] for k,v in Z.items()},fallback[:75])
        changed=dict(d,y=d['y'].copy());changed['y'][50]=99999;alter,_=replay(changed,Z,fallback)
        for name,p in full.items():np.testing.assert_array_equal(p[:75],short[name]);np.testing.assert_array_equal(p,alter[name])
        self.assertEqual(len(full),29)
        for item in diag.values():self.assertGreater(item['learnedQueries'],0)
