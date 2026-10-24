import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).parents[1]))
from research_sleep_sequence_prior import CONTEXT_NAMES,query_at
from research_sleep_sequence_finetune import training_query,replay


class SequenceFinetuneTests(unittest.TestCase):
    def fixture(self):
        n=130
        return dict(y=np.arange(n,dtype=float)+10,wakes=np.arange(n)*3600.,available=np.arange(n)*3600.+600,
            X=np.repeat(np.arange(n,dtype=float)[:,None],len(CONTEXT_NAMES),axis=1),names=CONTEXT_NAMES)

    def test_training_copy_has_no_unresolved_label_or_current_values(self):
        d=self.fixture();d['available'][55]=1e10
        q=query_at(d,60,128,True);train=training_query(q)
        self.assertNotIn(65,train['target']);self.assertNotIn(70,train['target'])
        self.assertTrue(all(v is None for v in train['future_covariates'].values()))
        self.assertEqual(train['past_covariates']['ageDays'][-1],59)
        train['target'][0]=99999;self.assertNotEqual(train['target'][0],q['target'][0])

    def test_refits_predictions_prefix_and_unavailable_labels(self):
        d=self.fixture();d['available'][0]=1e10;calls=[]
        def fit(q,steps):calls.append(steps);return float(np.median(q['target']))
        def predict(m,q):return np.array([m,m+5,m+10])
        conf=[('test',3)];levels=[.1,.5,.9];fallback=np.full(130,60.)
        full,diag=replay(d,fallback,fit,predict,levels,conf)
        self.assertEqual(calls,[3,3]);self.assertEqual(diag['test']['issuedQueries'],89)
        p={k:v[:90] if k!='names' else v for k,v in d.items()}
        short,_=replay(p,fallback[:90],fit,predict,levels,conf)
        a=dict(d,y=d['y'].copy());a['y'][0]=99999
        changed,_=replay(a,fallback,fit,predict,levels,conf)
        for k in full:
            np.testing.assert_array_equal(full[k][:90],short[k]);np.testing.assert_array_equal(full[k],changed[k])
            np.testing.assert_array_equal(full[k][:41],fallback[:41])
