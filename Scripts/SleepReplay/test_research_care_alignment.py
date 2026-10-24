import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).parents[1]))
from research_sleep_care_alignment import care_patterns,replay


class CareAlignmentTests(unittest.TestCase):
    def test_patterns_use_grouped_completed_history_and_relative_time(self):
        events=np.array([[0,10,1],[5,10,2],[20,30,0],[25,100,1]],dtype=float);w=np.array([30.])
        a=care_patterns(events,w,2);b=care_patterns(events[::-1],w,2)
        np.testing.assert_array_equal(a,b)
        self.assertAlmostEqual(a[0,0,1],np.sqrt(2)/2);self.assertAlmostEqual(a[0,0,2],np.sqrt(2)/2)
        self.assertAlmostEqual(a[0,1,0],np.sqrt(2));self.assertEqual(a[0,1,8],0.)
        self.assertAlmostEqual(a[0,0,9],np.log1p(7.5/60)/2)
        np.testing.assert_array_equal(a,care_patterns(events[:3],w,2))
        shifted=events.copy();shifted[:,:2]+=123456
        np.testing.assert_array_equal(a,care_patterns(shifted,w+123456,2))

    def test_insufficient_or_stale_groups_remain_unavailable(self):
        events=np.array([[0,10,0],[20,30,1]],dtype=float)
        self.assertTrue(np.isnan(care_patterns(events,np.array([30.]),3)).all())
        self.assertTrue(np.isnan(care_patterns(events,np.array([200000.]),2)).all())

    def test_forecasts_are_prefix_causal_with_unavailable_outcomes_hidden(self):
        n=100;i=np.arange(n);w=i*10800.;phase=i*.3;y=20+(i*13)%150
        names=['clockSin1','clockCos1','lastDuration','lastNight','episodeSegments','ageDays']
        d=dict(X=np.column_stack([np.sin(phase),np.cos(phase),60+np.sin(i),i%3==0,np.ones(n),i/8]),names=names,y=y.astype(float),wakes=w,available=w+y*60)
        d['available'][10]=1e20;events=np.column_stack([w-600,w,i%7]);patterns={k:care_patterns(events,w,k) for k in [8,16]};fallback=np.full(n,60.)
        parent=np.full(n,55.);full,diag=replay(d,patterns,fallback,parent=parent)
        prefix={k:(v if k=='names' else v[:80]) for k,v in d.items()};short,_=replay(prefix,{k:v[:80] for k,v in patterns.items()},fallback[:80],parent=parent[:80])
        changed=dict(d,y=d['y'].copy());changed['y'][10]=99999;alter,_=replay(changed,patterns,fallback,parent=parent)
        for name,p in full.items():np.testing.assert_array_equal(p[:80],short[name]);np.testing.assert_array_equal(p,alter[name])
        self.assertEqual(len(full),18)
        for item in diag.values():self.assertEqual(item['issuedQueries']+item['fallbackQueries'],n)
