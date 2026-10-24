import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_history import summaries,replay


class PlanningHistoryTests(unittest.TestCase):
    def fixture(self,n=75):
        i=np.arange(n);wakes=1e6+i*86400.;y=100.+i%30
        X=np.zeros((n,11));X[:,0]=i;X[:,4:6]=60;X[:,6]=1
        d=dict(X=X.copy(),y=y,wakes=wakes,available=wakes+y*60)
        c=dict(X=X,labels=np.where(i%4==0,2,1),knownAt=wakes+y*60+3600,wakeClock=np.full(n,600.),targetClock=600+y,ordinal=i%3)
        return d,c,np.full(n,120.)

    def test_manual_values_and_unresolved_membership(self):
        d,c,_=self.fixture(3);d['y'][:]=[100,200,150];c['targetClock'][:]=[700,800,750];c['labels'][:]=[1,2,1];c['knownAt'][0]=1e20
        out=summaries(d,c)
        np.testing.assert_array_equal(out[0,[0,5,10,15]],[0,0,0,0])
        np.testing.assert_array_equal(out[2,:5],[1,200,200,200,200])
        np.testing.assert_array_equal(out[2,15:],[1,200,200,200,200])
        self.assertEqual(out[2,5],0)
        d['y'][0]=1;c['labels'][0]=0;c['targetClock'][0]=0
        np.testing.assert_array_equal(out,summaries(d,c))

    def test_prefix_and_future_outcome_isolation(self):
        d,c,base=self.fixture();full,_=replay(d,c,base,d['X'])
        small,_=replay({k:v[:65] for k,v in d.items()},{k:v[:65] for k,v in c.items()},base[:65],d['X'][:65])
        d2={k:v.copy() for k,v in d.items()};c2={k:v.copy() for k,v in c.items()}
        d2['y'][64:]=1;c2['labels'][64:]=0;c2['targetClock'][64:]=0
        altered,_=replay(d2,c2,base,d2['X'])
        for name in full:
            np.testing.assert_array_equal(full[name][:65],small[name]);np.testing.assert_array_equal(full[name][:65],altered[name][:65])

    def test_history_window_excludes_stale_labels(self):
        d,c,_=self.fixture(20);out=summaries(d,c)
        self.assertEqual(out[-1,0],14)
        d2={k:v.copy() for k,v in d.items()};d2['y'][:5]=9999
        np.testing.assert_array_equal(out[-1],summaries(d2,c)[-1])

if __name__=='__main__':unittest.main()
