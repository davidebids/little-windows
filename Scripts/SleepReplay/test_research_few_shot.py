import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).parents[1]))
from research_sleep_few_shot import replay


class FewShotTests(unittest.TestCase):
    def fixture(self,n=70):
        i=np.arange(n);phase=i*.3;w=i*10800.;y=40+5*np.sin(i)
        return dict(X=np.column_stack([np.sin(phase),np.cos(phase),60+np.cos(i),i%2]),names=['clockSin1','clockCos1','lastDuration','lastNight'],y=y,wakes=w,available=w+y*60)

    def test_first_resolved_label_updates_exact_prior_shrinkage(self):
        d=self.fixture(2);fallback=np.array([80.,100.]);p,_,counts=replay(d,fallback)
        w=np.exp2(-10800/(14*86400));den=2+w
        self.assertAlmostEqual(p['fewShot_offset_global_prior2'][1],100+w*(40-80)/den)
        self.assertAlmostEqual(p['fewShot_logRatio_global_prior2'][1],100*np.exp(w*np.log(40/80)/den))
        self.assertAlmostEqual(p['fewShot_directGap_global_prior2'][1],(200+w*40)/den)
        self.assertEqual(p['fewShot_offset_global_prior2'][0],80);np.testing.assert_array_equal(counts,[0,1])

    def test_handoff_uses_resolved_count_not_query_index(self):
        d=self.fixture();d['available'][5]=1e20;fallback=np.full(70,60.);p,_,counts=replay(d,fallback)
        self.assertEqual(counts[40],39);self.assertEqual(counts[41],40)
        for name,v in p.items():
            if name.endswith('_handoff40'):np.testing.assert_array_equal(v[counts>=40],fallback[counts>=40])
        self.assertEqual(len(p),29)

    def test_all_prior_variants_are_prefix_and_unavailable_label_isolated(self):
        d=self.fixture();d['available'][5]=1e20;fallback=np.full(70,60.);priors=(.25,.5,2.,8.)
        p,_,_=replay(d,fallback,priors)
        prefix={k:(v if k=='names' else v[:55]) for k,v in d.items()};short,_,_=replay(prefix,fallback[:55],priors)
        changed=dict(d,y=d['y'].copy());changed['y'][5]=99999;alter,_,_=replay(changed,fallback,priors)
        for name,v in p.items():np.testing.assert_array_equal(v[:55],short[name]);np.testing.assert_array_equal(v,alter[name])
        self.assertEqual(len(p),53)
