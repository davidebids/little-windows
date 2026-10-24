import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).parents[1]))
from research_sleep_state_features import state_features,replay


class StateFeatureTests(unittest.TestCase):
    def fixture(self,n=80):
        i=np.arange(n);w=i*10800.;y=60+10*np.sin(i);phase=i*.4
        d=dict(X=np.column_stack([np.sin(phase),np.cos(phase),60+5*np.cos(i)]),
            names=['clockSin1','clockCos1','lastDuration'],y=y,wakes=w,available=w+y*60)
        d['available'][:4]=1e20
        raw=np.sin(i[:,None,None]*.21+np.arange(70).reshape(1,14,5))
        return d,raw,np.full(n,60.)

    def test_state_layout_and_finite_guard(self):
        raw=np.arange(140,dtype=float).reshape(2,14,5);before=raw.copy()
        x=state_features(raw);self.assertEqual(x.shape,(2,70));self.assertEqual(x[1,7],raw[1,1,2]);np.testing.assert_array_equal(before,raw)
        raw[0,0,0]=np.nan
        with self.assertRaises(AssertionError):state_features(raw)

    def test_matched_heads_are_prefix_and_unavailable_label_isolated(self):
        d,raw,fallback=self.fixture();full,diag=replay(d,raw,fallback,fast_bins=False)
        prefix={k:(v if k=='names' else v[:65]) for k,v in d.items()};short,_=replay(prefix,raw[:65],fallback[:65],fast_bins=False)
        changed=dict(d,y=d['y'].copy());changed['y'][:4]=9999
        alter,_=replay(changed,raw,fallback,fast_bins=False)
        for name,p in full.items():
            np.testing.assert_array_equal(p[:65],short[name]);np.testing.assert_array_equal(p,alter[name])
            warmup=12 if name.startswith('stateFeatureCombination_') else 44
            np.testing.assert_array_equal(p[:warmup],fallback[:warmup])
        self.assertEqual(len(full),13)
        for name,v in diag.items():self.assertEqual(v['featureCount'],74 if 'augmented' in name else 4)
