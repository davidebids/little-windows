from pathlib import Path
import datetime as dt
import sys
import unittest
from zoneinfo import ZoneInfo
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_phase_clock import occupancy_moment,offset_table,phase_features,replay,designs


class PlanningPhaseClockTests(unittest.TestCase):
    def test_exact_moment_matches_independent_midpoint_integration(self):
        now=2*86400.;a=22*3600.;b=30*3600.;rate=np.log(2)/(3*86400)
        moment,mass,days=occupancy_moment([(a,b)],now,[(0,0)])
        seconds=np.arange(a+.5,b,1.);weights=np.exp(-rate*(now-seconds))
        expected=np.sum(weights*np.exp(2j*np.pi*seconds/86400))
        self.assertAlmostEqual(abs(moment-expected),0,delta=1e-4)
        self.assertAlmostEqual(mass,weights.sum(),delta=1e-4);self.assertEqual(days,2)

    def test_offset_change_matches_elapsed_sleep_and_local_clock_integral(self):
        tz=ZoneInfo('America/Los_Angeles')
        a=dt.datetime(2026,3,7,20,tzinfo=tz).timestamp();b=dt.datetime(2026,3,8,7,tzinfo=tz).timestamp();now=b
        offsets=offset_table(a-86400,b+86400,str(tz));moment,mass,days=occupancy_moment([(a,b)],now,offsets)
        seconds=np.arange(a+.5,b,1.);rate=np.log(2)/(3*86400)
        clocks=np.array([t+dt.datetime.fromtimestamp(t,tz).utcoffset().total_seconds() for t in seconds])
        expected=np.sum(np.exp(-rate*(now-seconds))*np.exp(2j*np.pi*clocks/86400))
        self.assertAlmostEqual((b-a)/3600,10);self.assertEqual(days,2)
        self.assertAlmostEqual(abs(moment-expected),0,delta=.001)
        self.assertAlmostEqual(mass,np.exp(-rate*(now-seconds)).sum(),delta=.001)

    def test_phase_frozen_at_wake_excludes_future_and_running_records(self):
        sleeps=np.array([[day*86400+20*3600,(day+1)*86400+6*3600,1.] for day in range(9)])
        wakes=sleeps[:7,1];full=phase_features(sleeps,wakes,'UTC')
        short=phase_features(sleeps[:5],wakes[:5],'UTC');np.testing.assert_array_equal(full[:5],short)
        altered=sleeps.copy();altered[7:,1]+=12*3600
        np.testing.assert_array_equal(full,phase_features(altered,wakes,'UTC'))
        self.assertEqual(full[0,3],0);self.assertEqual(full[-1,3],1)
        self.assertGreater(full[-1,1],.6);self.assertLess(abs(full[-1,0]),np.pi/4)
        # The next record may have started, but no eventual end is exposed.
        altered=sleeps.copy();altered[7,0]=wakes[-1]-3600;altered[7,1]=wakes[-1]+3600
        np.testing.assert_array_equal(full,phase_features(altered,wakes,'UTC'))

    def test_design_and_forecast_prefix_isolate_current_targets_and_preserve_nights(self):
        n=90;i=np.arange(n);wakes=1e7+i*86400.
        names=['ageDays','clockSin1','clockCos1','clockSin2','clockCos2','lastDuration']
        X=np.column_stack([i,np.zeros(n),np.ones(n),np.zeros(n),np.ones(n),np.full(n,60.)])
        data=dict(X=X,names=names,y=90.+i%40,wakes=wakes)
        C=np.zeros((n,11));C[:,5]=60;C[:,6]=1;C[:,7]=i%3
        c=dict(X=C,labels=np.ones(n,int),knownAt=wakes+18000,wakeClock=np.full(n,600.));c['knownAt'][20]=1e20;c['wakeClock'][::13]=120
        phase=np.column_stack([np.zeros(n),np.full(n,.8),np.full(n,7),np.ones(n),np.full(n,10),c['wakeClock']])
        base=np.full(n,110.);full,_=replay(data,c,base,phase)
        short={k:(v if k=='names' else v[:70]) for k,v in data.items()}
        prefix,_=replay(short,{k:v[:70] for k,v in c.items()},base[:70],phase[:70])
        changed=dict(data,y=data['y'].copy());changed['y'][20]=9999;changed['y'][69:]=9999
        cc={k:v.copy() for k,v in c.items()};cc['labels'][20]=0;cc['labels'][69:]=0
        original=designs(data,c,phase);mutated=designs(changed,cc,phase)
        for name in original:
            for a,b in zip(original[name],mutated[name]):np.testing.assert_array_equal(a,b)
        altered,_=replay(changed,cc,base,phase)
        for name,p in full.items():
            np.testing.assert_array_equal(p[:70],prefix[name]);np.testing.assert_array_equal(p[:70],altered[name][:70]);np.testing.assert_array_equal(p[::13],base[::13])


if __name__=='__main__':unittest.main()
