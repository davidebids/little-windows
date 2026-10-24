from pathlib import Path
import datetime as dt
import sys
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_day_roles import model_at,replay


class PlanningDayRoleTests(unittest.TestCase):
    def fixture(self,counts=(3,3,2,2)):
        epoch=dt.datetime(2025,1,1,tzinfo=dt.timezone.utc).timestamp();wakes=[];y=[];days=[];labels=[];orders=[];known=[];clocks=[];targetClocks=[]
        def append(day,q,clock,gap,label,available):
            wakes.append(epoch+day*86400+clock*60);y.append(gap);days.append((dt.date(2025,1,1)+dt.timedelta(days=day)).isoformat())
            labels.append(label);orders.append(q);known.append(epoch+day*86400+available*3600);clocks.append(clock);targetClocks.append(clock+gap)
        for day,n in enumerate(counts):
            for q in range(n):
                clock=360 if q==0 else (720 if q==n-1 else 600)
                gap=60 if q==0 else (150 if q==n-1 else 90)
                end=15 if q==n-1 else (12 if q+1==n-1 else 10)
                append(day,q,clock,gap,1,end)
            append(day,n,900,240,2,30)
        append(len(counts),1,840,120,1,20)
        data=dict(wakes=np.asarray(wakes,float),y=np.asarray(y,float))
        context=dict(day=np.asarray(days),targetDay=np.asarray(days),labels=np.asarray(labels),ordinal=np.asarray(orders),knownAt=np.asarray(known),wakeClock=np.asarray(clocks,float),targetClock=np.asarray(targetClocks,float))
        return data,context,np.full(len(y),110.)

    def test_manual_last_nap_roles_count_ties_mixture_and_bedtime_anchor(self):
        d,c,base=self.fixture();i=len(base)-1;m=model_at(d,c,i)
        self.assertEqual(m['mode'],2);self.assertEqual(m['counts'],{3:2,2:2});self.assertEqual(m['penultimate'],[150]*4)
        p,_=replay(d,c,base)
        self.assertEqual(p['ordinalMode'][-1],120);self.assertEqual(p['endRelativeMode'][-1],150)
        self.assertEqual(p['endRelativeCountMixture'][-1],90)
        c['ordinal'][-1]=2;p,_=replay(d,c,base)
        self.assertEqual(p['endRelativeMode'][-1],240);self.assertEqual(p['endRelativeClockAnchor'][-1],300)

    def test_current_and_unresolved_historical_day_outcomes_do_not_train(self):
        d,c,base=self.fixture();i=len(base)-1
        bed=np.flatnonzero(c['labels']==2)[-1];c['knownAt'][bed]=d['wakes'][i]+1
        before,_=replay(d,c,base);d['y'][bed]=9999;c['labels'][bed]=0;c['targetClock'][bed]=0
        after,_=replay(d,c,base)
        for name in before:np.testing.assert_array_equal(before[name],after[name])
        d['y'][-1]=9999;c['labels'][-1]=2;c['targetClock'][-1]=0;c['targetDay'][-1]='2099-01-01'
        changed,_=replay(d,c,base)
        for name in before:np.testing.assert_array_equal(before[name],changed[name])

    def test_prefix_and_later_outcomes_preserve_issued_forecasts(self):
        d,c,base=self.fixture((3,3,2,2,3,2,3,2,2,3));full,_=replay(d,c,base);cut=24
        prefix,_=replay({k:v[:cut] for k,v in d.items()},{k:v[:cut] for k,v in c.items()},base[:cut])
        d['y'][cut-1:]=9999;c['labels'][cut-1:]=0;c['targetClock'][cut-1:]=0;c['targetDay'][cut-1:]='2099-01-01';c['ordinal'][cut:]=99
        changed,_=replay(d,c,base)
        for name in full:
            np.testing.assert_array_equal(full[name][:cut],prefix[name]);np.testing.assert_array_equal(full[name][:cut],changed[name][:cut])

    def test_minimum_days_expiry_and_overnight_fallback(self):
        d,c,base=self.fixture((3,2));self.assertIsNone(model_at(d,c,len(base)-1))
        d,c,base=self.fixture();i=len(base)-1;c['wakeClock'][i]=120
        p,_=replay(d,c,base)
        for values in p.values():self.assertEqual(values[-1],base[-1])
        d['wakes'][i]+=20*86400;c['day'][i]='2025-01-25';c['wakeClock'][i]=840
        self.assertIsNone(model_at(d,c,i))
        p,_=replay(d,c,base)
        for values in p.values():self.assertEqual(values[-1],base[-1])


if __name__=='__main__':unittest.main()
