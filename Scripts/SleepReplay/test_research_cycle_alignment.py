import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).parents[1]))
from research_sleep_cycle_alignment import cycle_patterns,dtw_costs,replay


class CycleAlignmentTests(unittest.TestCase):
    def fixture(self):
        n=110;i=np.arange(n);phase=i*2*np.pi/16
        names=['lastDuration','clockSin1','clockCos1','lastNight','episodeSegments','ageDays']
        X=np.column_stack([60+5*np.sin(i),np.sin(phase),np.cos(phase),i%3==0,1+(i%4==0),i/8])
        y=20+(i*13)%150;wakes=i*3*3600.
        return dict(X=X,names=names,y=y.astype(float),wakes=wakes,available=wakes+y*60,indices=i)

    def test_batched_recurrence_matches_exhaustive_paths(self):
        rng=np.random.default_rng(12);q=rng.normal(size=(4,3));H=rng.normal(size=(3,4,3))
        def brute(h,band,i=0,j=0):
            if abs(i-j)>band:return np.inf
            here=np.sum((h[i]-q[j])**2)
            if i==3 and j==3:return here
            choices=[brute(h,band,a,b) for a,b in [(i+1,j),(i,j+1),(i+1,j+1)] if a<4 and b<4]
            return here+min(choices)
        for band in [0,2]:np.testing.assert_allclose(dtw_costs(q,H,band),[brute(h,band) for h in H],rtol=0,atol=1e-12)
        q=np.array([1,1,2,3.])[:,None];h=np.array([1,2,2,3.])[None,:,None]
        self.assertEqual(dtw_costs(q,h,2)[0],0)
        self.assertEqual(dtw_costs(q,h,0)[0],1)

    def test_patterns_hide_current_and_unknown_outcomes_and_reset_at_missing_links(self):
        d=self.fixture();d['available'][50]=1e10;a=dict(d,y=d['y'].copy());a['y'][50]=9999
        np.testing.assert_allclose(cycle_patterns(d,6),cycle_patterns(a,6),equal_nan=True)
        a=dict(d,y=d['y'].copy());a['y'][40]=9999
        np.testing.assert_array_equal(cycle_patterns(d,6)[40],cycle_patterns(a,6)[40])
        d=self.fixture();d['indices'][60:]+=1;P=cycle_patterns(d,6)
        self.assertTrue(np.isnan(P[60:66]).all());self.assertTrue(np.isfinite(P[66]).all())

    def test_forecasts_are_prefix_causal_and_retain_all_warmup_cases(self):
        d=self.fixture();d['available'][50]=1e10;fallback=np.full(110,60.)
        full,diag=replay(d,fallback)
        p={k:(v if k=='names' else v[:90]) for k,v in d.items()};short,_=replay(p,fallback[:90])
        a=dict(d,y=d['y'].copy());a['y'][50]=9999;changed,_=replay(a,fallback)
        self.assertEqual(len(full),8)
        for k,v in full.items():
            self.assertEqual(len(v),110);self.assertTrue(np.isfinite(v).all());self.assertTrue(((v>=1)&(v<=480)).all())
            np.testing.assert_array_equal(v[:90],short[k]);np.testing.assert_array_equal(v,changed[k])
            np.testing.assert_array_equal(v[:46],fallback[:46])
        for item in diag.values():self.assertEqual(item['issuedQueries']+item['fallbackQueries'],110)
