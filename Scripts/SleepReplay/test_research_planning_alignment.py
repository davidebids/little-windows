import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).parents[1]))
from research_sleep_planning_alignment import suffix_patterns,sequence_costs,replay
from test_research_cycle_alignment import CycleAlignmentTests


class PlanningAlignmentTests(unittest.TestCase):
    def fixture(self):
        d=CycleAlignmentTests().fixture();n=len(d['y'])
        c=dict(knownAt=d['available']+3600,labels=np.ones(n,int))
        return d,c,np.full(n,60.)

    def test_partial_suffixes_preserve_known_cycles_and_reset(self):
        d,c,b=self.fixture();p=suffix_patterns(d)
        self.assertEqual([len(v) for v in p[:7]],[0,1,2,3,4,5,6])
        changed=dict(d,y=d['y'].copy());changed['y'][50:]=9999
        q=suffix_patterns(changed)
        for i in range(51):np.testing.assert_array_equal(p[i],q[i])
        d['indices'][60:]+=1;p=suffix_patterns(d)
        self.assertEqual(len(p[60]),0);self.assertEqual(len(p[61]),1)
        d,c,b=self.fixture();d['available'][50]=1e10;p=suffix_patterns(d)
        self.assertEqual(len(p[51]),0);self.assertEqual(len(p[52]),1)

    def test_common_suffix_and_warping_cost(self):
        q=np.array([1,1,2,3.])[:,None];h=np.array([1,2,2,3.])[:,None]
        self.assertEqual(sequence_costs(q,[h],0)[0],.25)
        self.assertEqual(sequence_costs(q,[h],2)[0],0)
        np.testing.assert_array_equal(sequence_costs(q,[np.empty((0,1)),np.array([[3.]])],2),[0,0])
        np.testing.assert_array_equal(sequence_costs(np.empty((0,1)),[h],2),[0])

    def test_real_predictions_prefix_and_future_outcome_isolation(self):
        d,c,b=self.fixture();p=suffix_patterns(d);out,counts=replay(d,c,b,p)
        cut=80;short={k:v if k=='names' else v[:cut] for k,v in d.items()}
        a,ac=replay(short,{k:v[:cut] for k,v in c.items()},b[:cut],suffix_patterns(short))
        changed=dict(d,y=d['y'].copy());changed['y'][55:]=9999
        cc={k:v.copy() for k,v in c.items()};cc['labels'][55:]=0
        future,fc=replay(changed,cc,b,suffix_patterns(changed))
        np.testing.assert_array_equal(counts[:cut],ac)
        for name,v in out.items():
            np.testing.assert_array_equal(v[:cut],a[name]);np.testing.assert_array_equal(v[:56],future[name][:56])
            np.testing.assert_array_equal(v[counts<3],b[counts<3])
            self.assertTrue(np.isfinite(v).all());self.assertEqual(len(v),len(b))

    def test_unmature_and_expired_labels_do_not_train_and_invalid_input_fails(self):
        d,c,b=self.fixture();c['knownAt'][50]=1e10
        c['labels'][10]=0
        _,counts=replay(d,c,b,suffix_patterns(d))
        i=80;expected=sum((np.arange(len(b))<i)&(c['knownAt']<=d['wakes'][i])&(d['wakes']>=d['wakes'][i]-60*86400)&(d['y']>20)&(c['labels']!=0))
        self.assertEqual(counts[i],expected)
        d['X'][80,1]=np.nan
        with self.assertRaises(ValueError):replay(d,c,b,suffix_patterns(d))

if __name__=='__main__':unittest.main()
