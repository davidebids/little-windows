import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).parents[1]))
from research_sleep_neural_dynamics import template_forecasts,select
from build_sleep_neural_bank import convergence,parameter_grid


class NeuralDynamicsTests(unittest.TestCase):
    def fixture(self,n=90):
        i=np.arange(n);angle=i*np.pi/8;w=i*10800.;y=np.full(n,60.)
        return dict(X=np.column_stack([np.sin(angle),np.cos(angle),np.full(n,60.)]),names=['clockSin1','clockCos1','lastDuration'],y=y,wakes=w,available=w+y*60)

    def test_templates_use_current_clock_and_future_model_events_not_recorded_labels(self):
        d=self.fixture(3);d['X'][:,0]=np.sin(np.array([7,9,17])*np.pi/12);d['X'][:,1]=np.cos(np.array([7,9,17])*np.pi/12)
        model=dict(initialWake=True,onsetsHours=[8+24*i for i in range(15)],wakesHours=[16+24*i for i in range(15)])
        bank=dict(models=[model]);P=template_forecasts(d,bank)
        # Middle column is the zero phase offset.
        self.assertAlmostEqual(P['nextOnset'][0,1],60)
        self.assertEqual(P['sleepOpportunity'][1,1],1)
        self.assertEqual(P['awakeConditional'][1,1],480)
        alternate=dict(d,y=d['y']+999)
        Q=template_forecasts(alternate,bank)
        for k,v in P.items():np.testing.assert_array_equal(v,Q[k]);self.assertTrue(np.isfinite(v).all())

    def test_selection_is_prefix_and_unavailable_label_isolated(self):
        d=self.fixture();d['available'][0]=1e10;P=np.tile([30.,120.],(90,1));fallback=np.full(90,60.)
        for local in [False,True]:
            for penalty in [0,30]:
                full,diag=select(d,P,fallback,local,penalty)
                p={k:(v if k=='names' else v[:70]) for k,v in d.items()}
                short,_=select(p,P[:70],fallback[:70],local,penalty)
                a=dict(d,y=d['y'].copy());a['y'][0]=99999;changed,_=select(a,P,fallback,local,penalty)
                np.testing.assert_array_equal(full[:70],short);np.testing.assert_array_equal(full,changed)
                np.testing.assert_array_equal(full[:41],fallback[:41]);self.assertEqual(diag['learnedQueries'],49)

    def test_neutral_convergence_filter_is_independent_of_private_outcomes(self):
        self.assertEqual(len(parameter_grid()),56)
        def model(onsets):return dict(parameters=[5,6,-2,.9],initialWake=True,onsetsHours=onsets,wakesHours=[2,4])
        one=[model([1,3]),model([1,3]),model([1,3])];half=[model([1.001,3.001]),model([1,3,5]),model([1.1,3])]
        accepted,diag=convergence(one,half)
        self.assertEqual(len(accepted),1);self.assertTrue(diag[0]['accepted']);self.assertFalse(diag[1]['accepted']);self.assertFalse(diag[2]['accepted'])
