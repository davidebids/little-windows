from pathlib import Path
import sys
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_late_errors import replay


class PlanningLateErrorTests(unittest.TestCase):
    def fixture(self,n=110):
        i=np.arange(n);wakes=1e7+i*21600.
        data=dict(X=np.zeros((n,6)),wakes=wakes,y=np.where(i%4==0,170.,80.))
        C=np.zeros((n,11));C[:,5]=60;C[:,6]=1
        c=dict(X=C,labels=np.ones(n,int),knownAt=wakes+15000,wakeClock=np.full(n,600.))
        return data,c,np.full(n,110.)

    def test_class_balancing_changes_scores_without_inventing_probability_calibration(self):
        data,c,base=self.fixture();output,scores,diag=replay(data,c,base)
        self.assertAlmostEqual(scores[0,90],.25)
        self.assertAlmostEqual(scores[1,90],.5)
        self.assertEqual(output['lateHard'][90],80)
        self.assertEqual(output['residualControl'][90],80)
        self.assertGreater(diag['twoExpertQueries'],0)

    def test_current_known_inputs_can_select_a_later_than_baseline_point(self):
        data,c,base=self.fixture();data['X'][:,0]=(np.arange(len(base))%4==0).astype(float)
        output,scores,_=replay(data,c,base)
        self.assertGreater(scores[0,92],.99)
        self.assertEqual(output['lateHard'][92],170)
        self.assertEqual(output['lateBalancedHard'][92],170)
        self.assertGreater(output['lateHard'][92],base[92]+30)
        for p in output.values():np.testing.assert_array_equal(p[:40],base[:40])

    def test_prefix_current_future_unknown_labels_and_overnight_are_isolated(self):
        data,c,base=self.fixture();c['knownAt'][20]=1e20;c['wakeClock'][::13]=120
        components=np.full((2,len(base)),np.nan);full,scores,_=replay(data,c,base,components=components)
        short={k:v[:95] for k,v in data.items()};shortC={k:v[:95] for k,v in c.items()}
        prefixComponents=np.full((2,95),np.nan);prefix,prefixScores,_=replay(short,shortC,base[:95],components=prefixComponents)
        changed={k:v.copy() for k,v in data.items()};changed['y'][20]=9999;changed['y'][94:]=9999
        cc={k:v.copy() for k,v in c.items()};cc['labels'][20]=0;cc['labels'][94:]=0
        alteredComponents=np.full((2,len(base)),np.nan);altered,alteredScores,_=replay(changed,cc,base,components=alteredComponents)
        np.testing.assert_array_equal(scores[:,:95],prefixScores);np.testing.assert_array_equal(scores[:,:95],alteredScores[:,:95])
        np.testing.assert_array_equal(components[:,:95],prefixComponents);np.testing.assert_array_equal(components[:,:95],alteredComponents[:,:95])
        for name,p in full.items():
            np.testing.assert_array_equal(p[:95],prefix[name]);np.testing.assert_array_equal(p[:95],altered[name][:95]);np.testing.assert_array_equal(p[::13],base[::13])
            self.assertTrue(np.isfinite(p).all());self.assertTrue(((p>=1)&(p<=480)).all())


if __name__=='__main__':unittest.main()
