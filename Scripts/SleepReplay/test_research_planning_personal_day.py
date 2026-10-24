import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_personal_day import midpoint_night,adaptive_design,replay
from research_sleep_planning_phase_clock import phase_features


class PersonalDayTests(unittest.TestCase):
    def fixture(self,days=7):
        origin=1704067200.;sleeps=[]
        for day in range(days):
            for hour,duration in [(10,1),(14,1),(20,12)]:
                start=origin+day*86400+hour*3600;sleeps.append([start,start+duration*3600,float(hour==20)])
        s=np.array(sleeps);w=s[:-1,1].copy();n=len(w)
        d=dict(wakes=w,available=s[1:,0],y=(s[1:,0]-w)/60,indices=np.arange(n),
            names=np.array(['lastNight','napsToday','prior14d_kind_median','ageDays']),X=np.column_stack([s[:-1,2],np.ones(n),np.full(n,120.),np.arange(n)]))
        labels=np.where((s[:-1,2]>0)&(s[1:,2]>0),0,np.where(s[1:,2]>0,2,1))
        c=dict(knownAt=s[1:,1].copy(),labels=labels,X=np.zeros((n,11)))
        phase=phase_features(s,w,'UTC')
        return s,d,c,phase

    def test_midpoints_and_circular_night_boundary(self):
        origin=1704067200.;s=np.array([[origin+20*3600,origin+32*3600],[origin+10*3600,origin+11*3600],[origin+3*3600,origin+4*3600]])
        np.testing.assert_array_equal(midpoint_night(s,120,'UTC'),[True,False,True])

    def test_phase_physical_future_truncation_and_sparse_design(self):
        s,d,c,p=self.fixture();cut=14;now=d['wakes'][cut-1]
        truncated=phase_features(s[s[:,1]<=now],d['wakes'][:cut],'UTC')
        np.testing.assert_array_equal(p[:cut],truncated)
        C,A,labels=adaptive_design(s,d,c,np.zeros_like(p),'UTC')
        np.testing.assert_array_equal(C,A);np.testing.assert_array_equal(labels,c['labels'])

    def test_current_target_end_never_enters_query_features(self):
        s,d,c,p=self.fixture();C,A,labels=adaptive_design(s,d,c,p,'UTC');k=14
        changed=s.copy();changed[k+1,1]+=12*3600
        _,other,_=adaptive_design(changed,d,c,p,'UTC')
        np.testing.assert_array_equal(A[:k+1],other[:k+1])
        self.assertTrue((p[:,3]>0).any())

    def test_real_forests_prefix_current_future_and_maturity(self):
        s,d,c,p=self.fixture();C,A,labels=adaptive_design(s,d,c,p,'UTC');base=np.full(len(d['y']),100.)
        full,diag=replay(d,c,base,C,A,labels);cut=14
        dd={k:v[:cut] if k!='names' else v for k,v in d.items()};cc={k:v[:cut] for k,v in c.items()}
        _,AA,ll=adaptive_design(s,dd,cc,p[:cut],'UTC')
        pre,_=replay(dd,cc,base[:cut],C[:cut],AA,ll)
        d['y'][cut-1:]=9999;c['labels'][cut-1:]=0;labels[cut-1:]=0
        changed,_=replay(d,c,base,C,A,labels)
        for name in full:
            np.testing.assert_array_equal(full[name][:cut],pre[name]);np.testing.assert_array_equal(full[name][:cut],changed[name][:cut])
        self.assertTrue(diag['personalDayPlanning']['refits'])
        c['knownAt'][:]=d['wakes'][-1]+86400
        sparse,_=replay(d,c,base,C,A,labels)
        for values in sparse.values():np.testing.assert_array_equal(values,base)

    def test_expired_training_history_retains_fallback(self):
        s,d,c,p=self.fixture();C,A,labels=adaptive_design(s,d,c,p,'UTC');base=np.full(len(d['y']),100.)
        d['wakes'][15:]+=61*86400;c['knownAt'][15:]+=61*86400
        out,_=replay(d,c,base,C,A,labels)
        for values in out.values():np.testing.assert_array_equal(values[15:18],base[15:18])


if __name__=='__main__':unittest.main()
