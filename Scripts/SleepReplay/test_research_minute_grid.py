import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).parents[1]))
from research_sleep_minute_grid import snap,replay


class MinuteGridTests(unittest.TestCase):
    def test_rounding_never_precedes_planning_minimum_and_is_boundary_stable(self):
        w=np.array([120.,120.,0.,0.]);p=np.array([1.,4.,2.5,5.])
        for rule in ['nearest','floor','ceil']:
            v=snap(p,w,rule);self.assertTrue(((v>=1)&(v<=480)).all())
        self.assertEqual(snap(p,w,'nearest')[2],5)
        for rule in ['nearest','floor','ceil']:
            self.assertEqual(snap(np.array([5.-1e-10]),np.array([0.]),rule)[0],5)
        with self.assertRaises(ValueError):snap(p,w,'unknown')

    def test_adaptive_policies_are_prefix_and_unknown_label_isolated(self):
        n=100;i=np.arange(n);w=i*10800.;y=10+(i*7)%120
        names=['clockSin1','clockCos1','lastDuration'];X=np.column_stack([np.sin(i/3),np.cos(i/3),np.full(n,60.)])
        d=dict(X=X,names=names,y=y.astype(float),wakes=w,available=w+y*60)
        d['available'][30]=1e10;app=np.full(n,61.);parent=np.full(n,59.)
        full=replay(d,app,parent)
        short={k:(v if k=='names' else v[:75]) for k,v in d.items()};prefix=replay(short,app[:75],parent[:75])
        a=dict(d,y=d['y'].copy());a['y'][30]=9999;changed=replay(a,app,parent)
        self.assertEqual(len(full),16)
        for k,v in full.items():
            np.testing.assert_array_equal(v[:75],prefix[k]);np.testing.assert_array_equal(v,changed[k])
            self.assertTrue(np.isfinite(v).all());self.assertEqual(len(v),n)
