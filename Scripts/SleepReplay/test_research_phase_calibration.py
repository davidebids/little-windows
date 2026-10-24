import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).parents[1]))
from research_sleep_phase_calibration import calibrate,replay


class PhaseCalibrationTests(unittest.TestCase):
    def fixture(self):
        n=110;i=np.arange(n);w=i*10800.;y=np.full(n,64.)
        X=np.column_stack([np.sin(i/3),np.cos(i/3),np.full(n,60.)]);names=['clockSin1','clockCos1','lastDuration']
        return dict(X=X,names=names,y=y,wakes=w,available=w+y*60)

    def test_constant_phase_learns_bounded_shift_and_weak_evidence_retains_original(self):
        d=self.fixture();issued=np.full(110,60.)
        p,diag=calibrate(d,issued,.5,2.5)
        np.testing.assert_array_equal(p[:40],issued[:40]);self.assertTrue(np.all(p[40:]==62.5))
        self.assertEqual(diag['maximumAbsoluteShiftMinutes'],2.5)
        global_point,_=calibrate(d,issued,None,2.5)
        np.testing.assert_array_equal(global_point,p)
        d['y']=issued.copy();q,_=calibrate(d,issued,.5,5)
        np.testing.assert_array_equal(q,issued)

    def test_issued_errors_not_current_targets_drive_prefix_and_unknown_label_behavior(self):
        d=self.fixture();d['available'][35]=1e10;issued=np.full(110,61.)
        full,diag=replay(d,issued)
        short={k:(v if k=='names' else v[:85]) for k,v in d.items()};prefix,_=replay(short,issued[:85])
        alternate=dict(d,y=d['y'].copy());alternate['y'][35]=9999;changed,_=replay(alternate,issued)
        self.assertEqual(len(full),13)
        for k,v in full.items():
            np.testing.assert_array_equal(v[:85],prefix[k]);np.testing.assert_array_equal(v,changed[k])
            self.assertEqual(len(v),110);self.assertTrue(np.isfinite(v).all())
        for name,v in diag.items():self.assertLessEqual(v['maximumAbsoluteShiftMinutes'],v['capMinutes'])
