import csv
import datetime as dt
import sys
import tempfile
import unittest
from pathlib import Path
from zoneinfo import ZoneInfo
import numpy as np
sys.path.insert(0,str(Path(__file__).parents[1]))
from research_sleep_return_cycles import cycle_features,compare


class ReturnCycleTests(unittest.TestCase):
    def test_prior_cycles_exclude_future_and_reset_ambiguous_links(self):
        pairs=[('08:00','09:00'),('10:00','11:00'),('12:00','13:00'),('14:00','15:00'),('16:00','17:00')]
        zone=ZoneInfo('America/Los_Angeles'); stamp=lambda t:dt.datetime.strptime('2001-01-01 '+t,'%Y-%m-%d %H:%M').replace(tzinfo=zone).timestamp()
        data=dict(indices=np.array([2,3]),wakes=np.array([stamp('13:00'),stamp('15:00')]))
        with tempfile.TemporaryDirectory() as folder:
            p=Path(folder)/'sleep.csv'
            def write(values):
                with p.open('w') as f:
                    writer=csv.DictWriter(f,fieldnames=['Type','Start','End']); writer.writeheader()
                    for start,end in values: writer.writerow(dict(Type='Sleep',Start='2001-01-01 '+start,End='2001-01-01 '+end))
            write(pairs); full,names=cycle_features(p,data,'America/Los_Angeles')
            self.assertEqual(full.shape,(2,18)); self.assertEqual(len(names),18)
            np.testing.assert_array_equal(full[1,[0,1,6,7,12,13]],[60.]*6)
            np.testing.assert_array_equal(full[1,[5,11,17]],[0.]*3)
            self.assertEqual(full[0,17],1.)
            write(pairs[:-1]+[('16:00','23:00')]); changed,_=cycle_features(p,data,'America/Los_Angeles')
            np.testing.assert_array_equal(full,changed)
            write(pairs[:2]+[('12:00','14:30')]+pairs[3:])
            broken,_=cycle_features(p,{k:v[1:] for k,v in data.items()},'America/Los_Angeles')
            np.testing.assert_array_equal(broken[0,[5,11,17]],[1.]*3)

    def test_added_cycle_information_learns_a_neutral_decision_and_preserves_prefixes(self):
        n=150; i=np.arange(n); y=np.where(i%2==0,8.,120.); wakes=i*21600.
        data=dict(wakes=wakes,available=wakes+y*60,y=y); X=np.zeros((n,11)); X[:,0]=i/4; X[:,4]=X[:,5]=30; X[:,7]=1
        context=dict(X=X,wakeClock=np.full(n,600.),ordinal=np.ones(n)); base=np.full(n,120.)
        cycles=np.zeros((n,18)); cycles[:,0]=np.where(i%2==0,15.,60.)
        data['available'][50]=1e20
        full,diag,controls,control_diag,eligible,q=compare(data,context,base,cycles)
        short,_,_,_,_,_=compare({k:v[:100] for k,v in data.items()},{k:v[:100] for k,v in context.items()},base[:100],cycles[:100])
        altered=dict(data,y=y.copy()); altered['y'][50]=99999
        changed,_,_,_,_,_=compare(altered,context,base,cycles)
        self.assertEqual(len(full),8)
        for name,p in full.items():
            np.testing.assert_array_equal(p[:100],short[name]); np.testing.assert_array_equal(p,changed[name])
        key='returnCycles_core_tree_risk0'
        self.assertLess(np.mean(abs(full[key][60:]-y[60:])),1e-10)
        self.assertGreater(np.mean(abs(controls['returnDecision_core_tree_risk0'][60:]-y[60:])),1.)
        self.assertEqual(diag[key]['eligibleQueries'],control_diag['returnDecision_core_tree_risk0']['eligibleQueries'])
