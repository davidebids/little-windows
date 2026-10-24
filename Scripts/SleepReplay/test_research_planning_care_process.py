import sys
from pathlib import Path
import unittest

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_care_process import BinaryHazard, care_stream, states_at, risk_blocks, replay, fit_process, forecast, gaussian_offset, split_logits
from research_sleep_care_signatures import MARKS


def fixture(n=18):
    wakes = 1700000040.+np.arange(n)*86400
    d = dict(X=np.zeros((n, 2)), names=np.array(['a', 'b']), wakes=wakes, y=np.full(n, 60.), indices=np.arange(n))
    c = dict(X=np.zeros((n, 11)), knownAt=wakes+7200, labels=np.ones(n), wakeClock=np.full(n, 600.))
    stream = np.array([(w-600, 0) for w in wakes]+[(w+1200, 1) for w in wakes], float)
    stream = stream[np.argsort(stream[:, 0])]
    return d, c, np.full(n, 60.), stream


class CareProcessTests(unittest.TestCase):
    def test_stream_groups_presence_and_excludes_sleep(self):
        events = np.array([[0, 60, MARKS.index('Sleep')], [0, 60, MARKS.index('Feed')],
                           [10, 60, MARKS.index('Feed')], [0, 120, MARKS.index('Diaper')], [0, 180, MARKS.index('Bath')]])
        np.testing.assert_array_equal(care_stream(events), [[60, 0], [120, 1], [180, 2]])

    def test_risk_path_state_matches_independent_boundary_reconstruction(self):
        d, c, base, stream = fixture(2)
        _, blocks = risk_blocks(d, c, base, stream)
        for i, block in enumerate(blocks):
            expected = states_at(stream, d['wakes'][i]+np.arange(60)*60).reshape(60, -1)
            np.testing.assert_allclose(block['Z'], np.log1p(expected), rtol=0, atol=1e-14)
            self.assertEqual(block['care'][19, 1], 1.)
            self.assertEqual(block['care'].sum(), 1.)
            self.assertEqual(block['sleep'].sum(), 1.)
            self.assertEqual(block['sleep'][-1], 1.)
        bad = dict(d, y=np.array([60.25, 60.]))
        with self.assertRaises(ValueError):
            risk_blocks(bad, c, base, stream)

    def test_logit_fit_recovers_closed_form_intercept_with_missing_inputs(self):
        X = np.column_stack([np.zeros(100), np.full(100, np.nan)])
        y = np.r_[np.ones(20), np.zeros(80)]
        model = BinaryHazard().fit(X, y, np.zeros(100), np.ones(100))
        np.testing.assert_allclose(model.predict(X[:3], np.zeros(3)), .2, rtol=0, atol=1e-6)
        for value in [0., 1.]:
            constant = BinaryHazard().fit(X, np.full(100, value), np.zeros(100), np.ones(100))
            np.testing.assert_array_equal(constant.predict(X[:3], np.zeros(3)), np.full(3, value))

    def test_gaussian_hazard_reconstructs_conditioned_survival(self):
        from scipy.stats import norm
        offsets = gaussian_offset(70., 30., np.arange(100))
        survival = np.cumprod(1-1/(1+np.exp(-offsets)))
        expected = norm.sf((np.arange(1, 101)-70)/30)/norm.sf(-70/30)
        np.testing.assert_allclose(survival, expected, rtol=0, atol=1e-12)

    def test_split_logits_match_full_head_including_missing_and_clipped_values(self):
        from scipy.special import expit
        rng=np.random.default_rng(42)
        X=rng.normal(size=(100, 7)); X[::4, 1]=np.nan
        y=(rng.random(100)<.3).astype(float)
        model=BinaryHazard().fit(X,y,np.zeros(100),np.ones(100))
        query=X[:8].copy();query[0, 3]=1e6;query[1, 6]=-1e6
        fixed,weights=split_logits(model,query[:,:4],3)
        dynamic=np.clip((query[:,4:]-model.center[4:])/model.scale[4:],-10,10)
        actual=expit(fixed+dynamic@weights)
        np.testing.assert_allclose(actual,model.predict(query,np.zeros(8)),rtol=0,atol=1e-14)

    def test_training_and_queries_isolate_current_and_future_observations(self):
        d, c, base, stream = fixture()
        def trainer(blocks, known, wakes, now, baseline, actual):
            self.assertTrue(np.all(known < np.searchsorted(wakes, now)))
            return dict(riskMinutes=sum(len(blocks[j]['sleep']) for j in known), scale=15., iterations=[],
                        seen=sum(blocks[j]['Z'].sum() for j in known)+actual[known].sum())
        def forecaster(model, origin, state, clock, point, query_index, **kwargs):
            value=1.+float(model['seen'] % 100)+float(state.sum())*.001
            return {k:value for k in ['processStaticContext', 'processNoFutureCare', 'processMarginalMedian', 'processMarginalMean']}
        full, diag = replay(d, c, base, stream, trainer=trainer, forecaster=forecaster)
        cut=12
        ds={k:v[:cut] if len(v)==len(base) else v for k,v in d.items()}
        cs={k:v[:cut] for k,v in c.items()}
        truncated_stream=stream[stream[:, 0] <= d['wakes'][cut-1]]
        prefix, pd = replay(ds, cs, base[:cut], truncated_stream, trainer=trainer, forecaster=forecaster)
        for k in full:
            np.testing.assert_array_equal(full[k][:cut], prefix[k])
        self.assertEqual([x for x in diag['refits'] if x['query']<cut], pd['refits'])
        changed={k:v.copy() for k,v in d.items()}
        changed['y'][cut-1:]=240
        cc={k:v.copy() for k,v in c.items()}
        cc['labels'][cut-1:]=2
        extra=np.vstack([stream, [d['wakes'][cut-1]+60, 2]])
        altered,_=replay(changed, cc, base, extra, trainer=trainer, forecaster=forecaster)
        for k in full:
            np.testing.assert_array_equal(full[k][:cut], altered[k][:cut])

    def test_real_learned_process_is_deterministic_and_bounded(self):
        d,c,base,stream=fixture(8)
        C,blocks=risk_blocks(d,c,base,stream)
        model=fit_process(blocks, np.arange(7), d['wakes'], d['wakes'][7], base, d['y'])
        state=states_at(stream,[d['wakes'][7]])[0]
        a=forecast(model,C[7],state,600.,60.,7,particles=32,horizon=120)
        b=forecast(model,C[7],state,600.,60.,7,particles=32,horizon=120)
        self.assertEqual(a,b)
        self.assertTrue(all(np.isfinite(v) and 1<=v<=120 for v in a.values()))


if __name__=='__main__':
    unittest.main()
