import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).parents[1]))
from research_sleep_sequence_prior import CONTEXT_NAMES
from research_sleep_conditioned_head import features,learned_heads


class ConditionedHeadTests(unittest.TestCase):
    def fixture(self):
        n=110
        return dict(y=np.arange(n,dtype=float)+10,wakes=np.arange(n)*3600.,available=np.arange(n)*3600.+600,
            X=np.repeat(np.arange(n,dtype=float)[:,None],len(CONTEXT_NAMES),axis=1),names=CONTEXT_NAMES)

    def capture(self,q):
        mean=np.mean(q['target']);scale=max(1.,np.std(q['target']))
        current=q['future_covariates']['ageDays'][0]
        return np.full(768,mean+current*.01),np.array([mean,scale]),np.linspace(mean-10,mean+10,21),0.

    def test_features_hide_unresolved_targets_and_include_current_context(self):
        d=self.fixture();d['available'][50]=1e10
        Z,S,Q,diag=features(d,self.capture)
        a=dict(d,y=d['y'].copy());a['y'][50]=9999
        ZZ,SS,QQ,_=features(a,self.capture)
        for x,y in [(Z,ZZ),(S,SS),(Q,QQ)]:np.testing.assert_allclose(x,y,equal_nan=True)
        self.assertEqual(diag['issuedQueries'],70)
        np.testing.assert_array_equal(np.isnan(Z[:40]),True)
        self.assertTrue(np.isfinite(Z[40:]).all())

    def test_heads_prefix_unavailable_label_and_warmup_remain_causal(self):
        d=self.fixture();d['available'][85]=1e10;Z,S,_,_=features(d,self.capture)
        diagnostics={}
        full,counts=learned_heads(d,Z,S,np.full(110,60.),diagnostics=diagnostics)
        pools=diagnostics['nativeThreadPools']
        self.assertTrue(any(p['user_api']=='openmp' for p in pools))
        self.assertTrue(all(p['num_threads'] is None or p['num_threads']<=2 for p in pools))
        p={k:v[:100] if k!='names' else v for k,v in d.items()}
        short,_=learned_heads(p,Z[:100],S[:100],np.full(100,60.))
        a=dict(d,y=d['y'].copy());a['y'][85]=9999
        changed,_=learned_heads(a,Z,S,np.full(110,60.))
        self.assertEqual(len(full),8)
        for k,v in full.items():
            self.assertTrue(np.isfinite(v).all());self.assertTrue(((v>=1)&(v<=480)).all())
            np.testing.assert_allclose(v[:100],short[k],rtol=0,atol=1e-9)
            np.testing.assert_allclose(v,changed[k],rtol=0,atol=1e-9)
            np.testing.assert_array_equal(v[:80],60.)
            self.assertEqual(counts[k],2)
