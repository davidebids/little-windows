import csv
import sys
from pathlib import Path
import tempfile
import unittest

import numpy as np

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_care_values import completed_records,value_inputs,replay


class Probe:
    def __init__(self,records):self.records=records
    def fit(self,X,y):self.records.append((X.copy(),y.copy()));self.value=float(np.mean(y));return self
    def predict(self,X):
        assert len(X)==1
        return np.array([self.value])


class PlanningCareValueTests(unittest.TestCase):
    def test_unfinished_feeds_are_not_treated_as_completed_events(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'neutral.csv';fields=['Type','Start','End','Start Condition','End Condition','Start Location']
            rows=[dict(Type='Feed',Start='2020-01-01 12:00',End='',**{'Start Condition':'00:10L'}),
                  dict(Type='Feed',Start='2020-01-01 12:00',End='2020-01-01 12:00',**{'Start Condition':'00:10R'}),
                  dict(Type='Feed',Start='2020-01-01 12:00',End='2020-01-01 12:10',**{'Start Condition':'00:10L'}),
                  dict(Type='Diaper',Start='2020-01-01 12:00',End='',**{'End Condition':'wet'})]
            with p.open('w') as f:
                writer=csv.DictWriter(f,fieldnames=fields);writer.writeheader();writer.writerows(rows)
            records=completed_records(p,'America/Los_Angeles')
            self.assertEqual(len(records),2)
            end=max(r['endEpoch'] for r in records)
            features=value_inputs(records,np.array([end]))
            self.assertEqual(features.shape,(1,13))
            self.assertEqual(features[0,0],10.)
            self.assertEqual(features[0,1],1.)

    def test_values_ignore_future_completions(self):
        records=[dict(Type='Feed',startEpoch=0.,endEpoch=60.,**{'Start Condition':'00:05L','End Condition':''}),
                 dict(Type='Feed',startEpoch=0.,endEpoch=600.,**{'Start Condition':'00:20R','End Condition':''})]
        full=value_inputs(records,np.array([120.]))
        truncated=value_inputs(records[:1],np.array([120.]))
        np.testing.assert_array_equal(full,truncated)

    def test_real_maturity_prefix_and_zero_width_control(self):
        n=60;wakes=1700000040.+np.arange(n)*86400
        d=dict(X=np.zeros((n,2)),y=30.+np.arange(n),wakes=wakes)
        c=dict(X=np.zeros((n,11)),knownAt=wakes+3600,labels=np.ones(n));base=np.full(n,60.);H=np.full((n,13),.25)
        c['knownAt'][1]=wakes[12];c['labels'][2]=0;d['y'][3]=20
        records=[];full,diag=replay(d,c,base,H,factory=lambda:Probe(records))
        self.assertEqual(diag['refits'][0],dict(query=6,labels=3))
        np.testing.assert_array_equal(records[0][1],d['y'][[0,4,5]])
        np.testing.assert_array_equal(records[1][0][:,-13:],0.)
        np.testing.assert_array_equal(records[2][0][:,-13:],.25)
        cut=37;ds={k:v[:cut] for k,v in d.items()};cs={k:v[:cut] for k,v in c.items()}
        short,sd=replay(ds,cs,base[:cut],H[:cut],factory=lambda:Probe([]))
        for name in full:np.testing.assert_array_equal(full[name][:cut],short[name])
        self.assertEqual([r for r in diag['refits'] if r['query']<cut],sd['refits'])
        altered={k:v.copy() for k,v in d.items()};altered['y'][cut-1:]=400
        changed,_=replay(altered,c,base,H,factory=lambda:Probe([]))
        for name in full:np.testing.assert_array_equal(full[name][:cut],changed[name][:cut])

    def test_invalid_inputs_and_forecasts_fail_without_dropping_rows(self):
        d=dict(X=np.zeros((6,2)),y=np.full(6,60.),wakes=np.arange(6)*86400.)
        c=dict(X=np.zeros((6,11)),knownAt=d['wakes']+3600,labels=np.ones(6));base=np.full(6,60.)
        with self.assertRaises(ValueError):replay(d,c,base,np.zeros((6,12)))
        class Bad(Probe):
            def predict(self,X):return np.array([np.nan])
        with self.assertRaises(ValueError):replay(d,c,base,np.zeros((6,13)),factory=lambda:Bad([]))


if __name__=='__main__':unittest.main()
