import sys
from pathlib import Path
import datetime as dt
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_morning_budget import morning_features,replay

class MorningBudgetTests(unittest.TestCase):
    def test_manual_anchor_union_and_unresolved_history(self):
        epoch=dt.datetime(2025,1,2,tzinfo=dt.timezone.utc).timestamp()
        rows=np.array([[epoch-6*3600,epoch+6*3600,1],[epoch+8*3600,epoch+9*3600,0],[epoch+8.5*3600,epoch+9.5*3600,0],[epoch+10*3600,epoch+11*3600,0]])
        f=morning_features(rows,np.array([epoch+10*3600]),'UTC')
        np.testing.assert_array_equal(f,[[360,240,90,150]])
        np.testing.assert_array_equal(f,morning_features(rows[:-1],np.array([epoch+10*3600]),'UTC'))
    def test_missing_anchor_and_dst_elapsed_time(self):
        f=morning_features(np.array([[0.,3600.,0.]]),np.array([7200.]),'UTC');self.assertTrue(np.isnan(f).all())
        from zoneinfo import ZoneInfo
        z=ZoneInfo('America/Los_Angeles');stamp=lambda h:dt.datetime(2025,3,9,h,tzinfo=z).timestamp()
        f=morning_features(np.array([[stamp(0),stamp(1),1.]]),np.array([stamp(4)]),'America/Los_Angeles')
        np.testing.assert_array_equal(f,[[60,120,0,120]])
    def fixture(self):
        n=65;w=np.arange(n,dtype=float)*86400
        d=dict(wakes=w,y=np.full(n,100.),X=np.zeros((n,2)))
        c=dict(knownAt=w+3600,labels=np.ones(n,int),wakeClock=np.full(n,600.),X=np.zeros((n,11)))
        m=np.column_stack([np.full(n,360.),np.arange(n)+100.,np.full(n,20.),np.arange(n)+80.])
        return d,c,np.full(n,120.),m
    def test_prefix_current_and_future_outcome_isolation(self):
        d,c,b,m=self.fixture();full,_=replay(d,c,b,m);cut=55
        pre,_=replay({k:v[:cut] for k,v in d.items()},{k:v[:cut] for k,v in c.items()},b[:cut],m[:cut])
        d['y'][cut-1:]=999;c['labels'][cut-1:]=0;m[cut:]=0
        changed,_=replay(d,c,b,m)
        for k in full:
            np.testing.assert_array_equal(full[k][:cut],pre[k]);np.testing.assert_array_equal(full[k][:cut],changed[k][:cut])
    def test_target_shift_and_overnight_fallback(self):
        class Mean:
            def fit(self,X,y):self.y=float(np.mean(y));return self
            def predict(self,X):return [self.y]*len(X)
        d,c,b,m=self.fixture();c['wakeClock'][-1]=120
        p,_=replay(d,c,b,m,Mean)
        self.assertEqual(p['morningIntervalControl'][40],100)
        self.assertEqual(p['morningElapsedTarget'][40],79.5)
        self.assertEqual(p['morningAwakeTarget'][40],79.5)
        for k in p:self.assertEqual(p[k][-1],120)

if __name__=='__main__':unittest.main()
