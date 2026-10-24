import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).parents[1]))
from research_sleep_return_decision import benefit,snapshots,replay


def example(n=150):
    i=np.arange(n); y=np.where(i%2==0,8.,120.); wakes=i*21600.
    data=dict(wakes=wakes,available=wakes+y*60,y=y)
    X=np.zeros((n,11)); X[:,0]=i/4; X[:,4]=X[:,5]=np.where(i%2==0,15.,60.); X[:,7]=1
    context=dict(X=X,wakeClock=np.full(n,600.),ordinal=np.ones(n))
    return data,context,np.full(n,120.)


class ReturnDecisionTests(unittest.TestCase):
    def test_benefit_matches_action_losses_and_thirty_minute_risk(self):
        y=np.array([8.,120.,45.]); base=np.full(3,120.); q=np.full(3,8.)
        np.testing.assert_array_equal(benefit(y,base,q),[112.,-112.,38.])
        np.testing.assert_array_equal(benefit(y,base,q,30.),[142.,-142.,38.])

    def test_frozen_history_features_and_forecasts_ignore_unavailable_labels(self):
        data,context,base=example(); data['available'][50]=1e20
        eligible,q,core,history=snapshots(data,context,base)
        short_data={k:v[:100] for k,v in data.items()}; short_context={k:v[:100] for k,v in context.items()}
        short=snapshots(short_data,short_context,base[:100])
        for full,part in zip((eligible,q,core,history),short): np.testing.assert_array_equal(full[:100],part)
        altered=dict(data,y=data['y'].copy()); altered['y'][50]=99999
        alternate=snapshots(altered,context,base)
        for full,other in zip((eligible,q,core,history),alternate): np.testing.assert_array_equal(full,other)
        full,_,_,_=replay(data,context,base); prefix,_,_,_=replay(short_data,short_context,base[:100]); changed,_,_,_=replay(altered,context,base)
        for name,p in full.items(): np.testing.assert_array_equal(p[:100],prefix[name]); np.testing.assert_array_equal(p,changed[name])

    def test_learnable_return_decisions_reduce_loss_and_ineligible_queries_stay_app(self):
        data,context,base=example(); full,diag,eligible,q=replay(data,context,base)
        self.assertEqual(len(full),8)
        key='returnDecision_core_tree_risk0'
        self.assertLess(np.mean(abs(full[key][60:]-data['y'][60:])),1e-10)
        self.assertGreater(diag[key]['absoluteErrorMinutesSaved'],0.)
        self.assertEqual(diag[key]['longerWakeSwitches'],0)
        self.assertTrue(np.all((q>=1)&(q<=20)))
        night=dict(context,X=context['X'].copy()); night['X'][:,3]=1
        unchanged,_,eligible,_=replay(data,night,base)
        self.assertFalse(eligible.any())
        for p in unchanged.values(): np.testing.assert_array_equal(p,base)
