import datetime as dt
import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_regular_state import state_at,histories,clock_features,request,first_start,extend_forecast,replay,CONTEXT,HORIZON


class RegularStateTests(unittest.TestCase):
    def test_union_includes_start_and_excludes_end(self):
        sleeps=np.array([[0,120],[60,180],[240,300]],float)
        np.testing.assert_array_equal(state_at(sleeps,np.arange(0,361,60)),[1,1,1,0,1,0,0])
        np.testing.assert_array_equal(state_at(np.zeros((0,2)),[0,60]),[0,0])

    def test_completed_only_physical_truncation_and_observed_wake(self):
        sleeps=np.array([[0,180],[240,360],[480,600],[300,900],[1200,1260]],float);wakes=np.array([180.,360.,600.])
        full,n=histories(sleeps,wakes);short,k=histories(sleeps[sleeps[:,1]<=360],wakes[:2])
        np.testing.assert_array_equal(full[:2],short);np.testing.assert_array_equal(n[:2],k)
        np.testing.assert_array_equal(full[:,-1],[0,0,0]);np.testing.assert_array_equal(full[0,-4:],[1,1,1,0])
        self.assertTrue(np.isnan(full[0,:-4]).all())

    def test_minute_representation_preserves_one_minute_sleep_starts(self):
        for onset in [1,2,19,20,21,127,319,320,321,480]:
            sleeps=np.array([[-120,0],[onset*60,(onset+1)*60]],float)
            future=state_at(sleeps,np.arange(1,HORIZON+1)*60)
            self.assertEqual(first_start(future),onset)
        self.assertEqual(first_start(np.zeros(HORIZON)),480.)
        value=np.zeros(HORIZON);value[7]=.49999;value[8]=.5;self.assertEqual(first_start(value),9.)
        value[1]=np.nan
        with self.assertRaises(ValueError):first_start(value)

    def test_extension_appends_predicted_states_and_aligns_clock_only(self):
        original=np.arange(CONTEXT,dtype=np.float32)[None,:]/CONTEXT;future=np.tile(np.arange(CONTEXT+HORIZON,dtype=np.float32),(2,1));calls=[]
        def native(args,horizon):
            calls.append((args,horizon))
            return np.linspace(-1,2,horizon,dtype=np.float32) if len(calls)==1 else np.full(horizon,.7,np.float32)
        result=extend_forecast(dict(target=original.copy(),past_covariates=None,future_covariates=future),native)
        self.assertEqual([h for _,h in calls],[320,160]);self.assertEqual(result.shape,(480,))
        np.testing.assert_array_equal(calls[1][0]['target'][0,-320:],np.clip(result[:320],0,1))
        np.testing.assert_array_equal(calls[1][0]['target'][0,:-320],original[0,320:])
        np.testing.assert_array_equal(calls[1][0]['future_covariates'],future[:,320:])
        np.testing.assert_array_equal(original,np.arange(CONTEXT,dtype=np.float32)[None,:]/CONTEXT)
        with self.assertRaises(ValueError):extend_forecast(dict(target=original),native,0)

    def test_clock_covariates_follow_pacific_dst(self):
        t=np.array([dt.datetime(2026,3,8,9,59,tzinfo=dt.timezone.utc).timestamp(),dt.datetime(2026,3,8,10,0,tzinfo=dt.timezone.utc).timestamp()])
        phase=np.array([119.,180.])*2*np.pi/1440
        np.testing.assert_allclose(clock_features(t,'America/Los_Angeles'),np.stack([np.sin(phase),np.cos(phase)]),rtol=0,atol=1e-7)

    def test_replay_prefix_future_histories_and_context_alignment(self):
        sleeps=np.column_stack([np.arange(10)*300.,np.arange(10)*300.+120]);wakes=sleeps[:,1];history,length=histories(sleeps,wakes);base=np.full(10,100.)
        def predict(args):
            if args['future_covariates'] is not None:self.assertEqual(args['future_covariates'].shape,(2,args['target'].shape[1]+HORIZON))
            value=np.zeros(HORIZON);value[args['target'].shape[1]%100:]=1;return value
        full,_=replay(wakes,history,length,base,predict,'UTC');cut=7
        pre,_=replay(wakes[:cut],history[:cut],length[:cut],base[:cut],predict,'UTC')
        history[cut:]=999;length[cut:]=0
        changed,_=replay(wakes,history,length,base,predict,'UTC')
        for name in full:
            np.testing.assert_array_equal(full[name][:cut],pre[name]);np.testing.assert_array_equal(full[name][:cut],changed[name][:cut])
        self.assertIsNone(request(history[0],2,wakes[0],True,'UTC'))


if __name__=='__main__':unittest.main()
