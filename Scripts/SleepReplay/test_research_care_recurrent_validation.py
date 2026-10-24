import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).parents[1]))
from research_sleep_care_recurrent_validation import choose_epochs
from research_sleep_care_recurrent import fit_model,replay
from research_sleep_care_alignment import care_patterns


class RecurrentValidationTests(unittest.TestCase):
    def test_inner_split_is_chronological_and_selects_validation_loss(self):
        i=np.arange(80);p=np.broadcast_to(i[:,None,None],(80,16,11));context=i[:,None];target=np.full(80,64.);calls=[]
        def fit(s,c,y,w,epochs):
            np.testing.assert_array_equal(c[:,0],np.arange(64));self.assertEqual(len(y),64);calls.append(epochs);return epochs
        def predict(epochs,s,c):
            np.testing.assert_array_equal(c[:,0],np.arange(64,80));return np.full(len(c),epochs)
        chosen,diag=choose_epochs(p,context,target,np.arange(1,81),fit=fit,predict=predict)
        self.assertEqual(chosen,64);self.assertEqual(calls,[16,64,128]);self.assertEqual(diag['validationRows'],16)
        chosen,_=choose_epochs(p,context,target,np.ones(80),candidates=(16,8),fit=lambda *a:0,predict=lambda e,s,c:np.full(len(c),64.))
        self.assertEqual(chosen,8)

    def test_nested_fits_and_refits_are_prefix_and_unavailable_label_isolated(self):
        n=145;i=np.arange(n);w=i*10800.;phase=i*.3;y=60+10*np.sin(i)
        d=dict(X=np.column_stack([np.sin(phase),np.cos(phase),60+np.cos(i)]),names=['clockSin1','clockCos1','lastDuration'],y=y,wakes=w,available=w+y*60)
        d['available'][100]=1e20;events=np.column_stack([w-600,w,i%7]);p=care_patterns(events,w,16);fallback=np.full(n,60.)
        def adaptive(s,c,y,w,unused):
            e,_=choose_epochs(s,c,y,w,candidates=(2,4));return fit_model(s,c,y,w,e)
        full,diag=replay(d,p,fallback,fit_function=adaptive)
        prefix={k:(v if k=='names' else v[:130]) for k,v in d.items()};short,_=replay(prefix,p[:130],fallback[:130],fit_function=adaptive)
        changed=dict(d,y=d['y'].copy());changed['y'][100]=99999;alter,_=replay(changed,p,fallback,fit_function=adaptive)
        for name,v in full.items():np.testing.assert_array_equal(v[:130],short[name]);np.testing.assert_array_equal(v,alter[name])
        for item in diag.values():self.assertGreater(item['learnedQueries'],0)
