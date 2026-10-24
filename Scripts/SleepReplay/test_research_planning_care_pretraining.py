import sys
from pathlib import Path
import unittest
import numpy as np
import torch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_care_pretraining import auxiliary_examples,auxiliary_known,train_encoders,encode,replay
from research_sleep_care_alignment import care_patterns

class CarePretrainingTests(unittest.TestCase):
    def events(self,n=100):
        ends=np.arange(n,dtype=float)*1800+100000
        return np.column_stack([ends-300,ends,np.arange(n)%8])
    def fixture(self,n=60):
        events=self.events(n+20);aux=auxiliary_examples(events);w=events[20:20+n,1]
        d=dict(wakes=w,y=100+2*np.sin(np.arange(n)),X=np.column_stack([np.arange(n),np.ones(n)]))
        c=dict(knownAt=w+600,labels=np.ones(n,int),wakeClock=np.full(n,600.),X=np.zeros((n,11)))
        return d,c,np.full(n,100.),care_patterns(events,w,16),aux
    def test_auxiliary_group_targets_and_physical_future_truncation(self):
        events=self.events();events=np.vstack([events,[events[20,0],events[20,1],5]])
        aux=auxiliary_examples(events);now=events[60,1];known=auxiliary_known(aux,now)
        short=auxiliary_examples(events[events[:,1]<=now]);ks=auxiliary_known(short,now)
        for field in ['P','origins','available','marks','gap']:np.testing.assert_array_equal(aux[field][known],short[field][ks])
        np.testing.assert_array_equal(aux['marks'][19],[0,0,0,.0,.5,.5,0,0])
        self.assertAlmostEqual(aux['gap'][19],np.log1p(30)/4)
        self.assertTrue((aux['available'][known]<=now).all())
    def test_encoders_deterministic_and_invalid_query_mask(self):
        torch.set_num_threads(2);torch.use_deterministic_algorithms(True)
        aux=auxiliary_examples(self.events());now=aux['available'][-1];known=auxiliary_known(aux,now)
        first,diag=train_encoders(aux,known,now,epochs=2,batch_size=16)
        second,_=train_encoders(aux,known,now,epochs=2,batch_size=16)
        for mode in first:
            a=encode(first[mode],aux['P'][:25]);b=encode(second[mode],aux['P'][:25]);np.testing.assert_array_equal(a,b)
            self.assertTrue(np.isnan(a[:15]).all());self.assertTrue(np.isfinite(a[15:]).all())
        self.assertGreater(diag['predictive']['updates'],0)
        self.assertFalse(np.array_equal(encode(first['random'],aux['P'][20:25]),encode(first['predictive'],aux['P'][20:25])))
    def test_real_encoder_forest_prefix_current_and_future_outcomes(self):
        d,c,b,P,aux=self.fixture(70);full,_=replay(d,c,b,P,aux,epochs=1);cut=55
        prefix,_=replay({k:v[:cut] for k,v in d.items()},{k:v[:cut] for k,v in c.items()},b[:cut],P[:cut],aux,epochs=1)
        d['y'][cut-1:]=9999;c['labels'][cut-1:]=0;P[cut:]=999
        changed,_=replay(d,c,b,P,aux,epochs=1)
        for name in full:
            np.testing.assert_array_equal(full[name][:cut],prefix[name]);np.testing.assert_array_equal(full[name][:cut],changed[name][:cut])
    def test_unavailable_auxiliary_labels_cannot_change_forecast(self):
        d,c,b,P,aux=self.fixture();now=d['wakes'][45];known=auxiliary_known(aux,now)
        before,_=train_encoders(aux,known,now,epochs=1)
        altered={k:v.copy() for k,v in aux.items()};future=altered['available']>now;altered['marks'][future]=999;altered['gap'][future]=999;altered['P'][future]=999
        after,_=train_encoders(altered,auxiliary_known(altered,now),now,epochs=1)
        for mode in before:np.testing.assert_array_equal(encode(before[mode],P[:46]),encode(after[mode],P[:46]))
    def test_expanded_policy_learns_early_and_does_not_freeze_night_queries(self):
        d,c,b,P,aux=self.fixture(12);c['wakeClock'][-1]=120
        out,diag=replay(d,c,b,P,aux,epochs=1,minimum_labels=3,daytime_only=False,early_refits=True)
        self.assertEqual(diag['refits'],9)
        for values in out.values():np.testing.assert_array_equal(values[:3],b[:3])
        self.assertNotEqual(out['planningForestControl'][3],b[3])
        self.assertNotEqual(out['planningForestControl'][-1],b[-1])
        changed=dict(d,y=d['y'].copy());changed['y'][-1]=9999
        same,_=replay(changed,c,b,P,aux,epochs=1,minimum_labels=3,daytime_only=False,early_refits=True)
        for name in out:np.testing.assert_array_equal(out[name],same[name])

    def test_sparse_and_night_fallback(self):
        d,c,b,P,aux=self.fixture(20);out,diag=replay(d,c,b,P,aux,epochs=1);self.assertEqual(diag['refits'],0)
        for p in out.values():np.testing.assert_array_equal(p,b)
        d,c,b,P,aux=self.fixture();c['wakeClock'][-1]=120
        out,_=replay(d,c,b,P,aux,epochs=1)
        for p in out.values():self.assertEqual(p[-1],100)

if __name__=='__main__':unittest.main()
