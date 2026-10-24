#!/usr/bin/env python3
"""Learn minute hazards and marginalize predicted intermediate care events."""
import argparse
import hashlib
import json
from pathlib import Path
import time

import numpy as np
from scipy.optimize import minimize
from scipy.special import expit
from scipy.stats import norm
from threadpoolctl import threadpool_limits

from research_sleep_behavior_schedule import structure
from research_sleep_care_signatures import read_marks, MARKS
from research_sleep_ensemble import metrics
from research_sleep_marked_survival import marginal_survival, survival_points
from research_sleep_planning import eligible, planning_mask

DECAYS = np.array([30., 120., 480.])


def care_stream(events):
    """Presence of feed, diaper, or other care at each completion minute."""
    keep = events[events[:, 2] != MARKS.index('Sleep')]
    groups = set()
    for _, end, mark in keep:
        kind = 0 if mark == MARKS.index('Feed') else 1 if mark == MARKS.index('Diaper') else 2
        groups.add((float(end), kind))
    return np.array(sorted(groups), float).reshape(-1, 2)


def states_at(stream, timestamps):
    result = np.zeros((len(timestamps), 3, len(DECAYS)))
    for j, now in enumerate(timestamps):
        known = stream[stream[:, 0] <= now]
        for kind in range(3):
            age = (now - known[known[:, 1] == kind, 0])/60
            result[j, kind] = np.exp(-age[:, None]/DECAYS).sum(axis=0)
    return result


def static_features(origin, elapsed, wake_clock):
    elapsed = np.asarray(elapsed, float)
    phase = 2*np.pi*(wake_clock+elapsed)/1440
    t = elapsed/120
    return np.column_stack([np.repeat(origin[None, :], len(elapsed), axis=0), t, t*t/(1+t),
                            np.sin(phase), np.cos(phase), np.sin(2*phase), np.cos(2*phase)])


def gaussian_offset(point, scale, elapsed):
    """Logit of discrete conditional sleep hazard of a Gaussian planning prior."""
    elapsed = np.asarray(elapsed, float)
    log_ratio = norm.logsf((elapsed+1-point)/scale)-norm.logsf((elapsed-point)/scale)
    log_ratio = np.minimum(log_ratio, -1e-12)
    return np.log(-np.expm1(log_ratio))-log_ratio


def risk_blocks(data, context, base, stream):
    C = np.column_stack([data['X'], context['X'][:, 5:8], base/120])
    blocks = []
    for i, wake in enumerate(data['wakes']):
        gap = int(round(data['y'][i]))
        if gap < 1 or abs(gap-data['y'][i]) > 1e-6:
            raise ValueError('Minute representation must retain every actual target exactly')
        elapsed = np.arange(gap, dtype=float)
        care = np.zeros((gap, 3))
        during = stream[(stream[:, 0] > wake) & (stream[:, 0] <= wake+gap*60)]
        for stamp, kind in during:
            minute = (stamp-wake)/60
            if abs(minute-round(minute)) > 1e-6:
                raise ValueError('Completion times must align with minute boundaries')
            care[int(round(minute))-1, int(kind)] = 1
        state = np.zeros((gap, 3, len(DECAYS)))
        state[0] = states_at(stream, [wake])[0]
        for minute in range(1, gap):
            state[minute] = state[minute-1]*np.exp(-1/DECAYS)+care[minute-1, :, None]
        X = static_features(C[i], elapsed, context['wakeClock'][i])
        y = np.zeros(gap)
        y[-1] = 1
        blocks.append(dict(X=X, Z=np.log1p(state.reshape(gap, -1)), care=care, sleep=y, elapsed=elapsed))
    return C, blocks


class BinaryHazard:
    """Regularized logit hazard; fixed per-event loss normalization."""
    def fit(self, X, y, offset, weights):
        X, y, offset, weights = [np.asarray(v, float) for v in [X, y, offset, weights]]
        if X.ndim != 2 or y.shape != (len(X),) or offset.shape != y.shape or weights.shape != y.shape:
            raise ValueError('Invalid hazard training dimensions')
        if not np.isfinite(y).all() or not np.isfinite(offset).all() or not np.isfinite(weights).all() or (weights <= 0).any() or not np.isin(y, [0., 1.]).all():
            raise ValueError('Invalid hazard observations')
        if np.isinf(X).any():
            raise ValueError('Infinite input')
        finite = np.isfinite(X)
        count = (finite*weights[:, None]).sum(axis=0)
        self.center = np.divide((np.where(finite, X, 0)*weights[:, None]).sum(axis=0), count, out=np.zeros(X.shape[1]), where=count > 0)
        values = np.where(finite, X, self.center)
        self.scale = np.maximum(np.sqrt(np.average((values-self.center)**2, axis=0, weights=weights)), .1)
        self.constant = float(y[0]) if np.all(y == y[0]) else None
        self.iterations = 0
        if self.constant is not None:
            return self
        A = self.design(X)
        normalizer = max(float(np.dot(weights, y)), 1.)
        initial = np.zeros(A.shape[1])
        def objective(beta):
            eta = offset+A@beta
            penalty = .05*np.dot(beta[1:], beta[1:])
            value = np.dot(weights, np.logaddexp(0., eta)-y*eta)/normalizer+penalty
            gradient = A.T@((expit(eta)-y)*weights)/normalizer
            gradient[1:] += .1*beta[1:]
            return value, gradient
        result = minimize(objective, initial, jac=True, method='L-BFGS-B', options=dict(maxiter=500, ftol=1e-10, gtol=1e-6))
        if not result.success or not np.isfinite(result.x).all():
            raise RuntimeError('Hazard fit failed: '+str(result.message))
        self.beta = result.x
        self.iterations = int(result.nit)
        return self

    def design(self, X):
        finite = np.isfinite(X)
        values = np.where(finite, X, self.center)
        normalized = np.clip((values-self.center)/self.scale, -10, 10)
        return np.column_stack([np.ones(len(X)), normalized, ~finite])

    def predict(self, X, offset):
        X, offset = np.asarray(X, float), np.asarray(offset, float)
        if X.ndim != 2 or X.shape[1] != len(self.center) or offset.shape != (len(X),) or not np.isfinite(offset).all() or np.isinf(X).any():
            raise ValueError('Invalid hazard query')
        return np.full(len(X), self.constant) if self.constant is not None else expit(offset+self.design(X)@self.beta)


def fit_process(blocks, known, wakes, now, base, actual):
    X = np.vstack([blocks[j]['X'] for j in known])
    Z = np.vstack([blocks[j]['Z'] for j in known])
    full = np.column_stack([X, Z])
    sleep = np.concatenate([blocks[j]['sleep'] for j in known])
    care = np.vstack([blocks[j]['care'] for j in known])
    weights = np.concatenate([np.full(len(blocks[j]['sleep']), np.exp2(-(now-wakes[j])/(14*86400))) for j in known])
    residual = actual[known]-base[known]
    scale = max(15., 1.4826*float(np.median(abs(residual-np.median(residual)))))
    offset = np.concatenate([gaussian_offset(base[j], scale, blocks[j]['elapsed']) for j in known])
    static = BinaryHazard().fit(X, sleep, offset, weights)
    dynamic = BinaryHazard().fit(full, sleep, offset, weights)
    intermediate = [BinaryHazard().fit(full, care[:, j], np.zeros(len(X)), weights) for j in range(3)]
    return dict(static=static, dynamic=dynamic, care=intermediate, scale=scale,
                riskMinutes=len(X), iterations=[m.iterations for m in [static, dynamic, *intermediate]])


def split_logits(model, fixed, dynamic_dims):
    """Separate fixed clock/context terms from the changing care-state terms."""
    width = len(model.center)
    count = width-dynamic_dims
    if fixed.shape[1] != count:
        raise ValueError('Inconsistent dynamic feature split')
    if model.constant is not None:
        return np.zeros(len(fixed)), np.zeros(dynamic_dims)
    finite = np.isfinite(fixed)
    values = np.where(finite, fixed, model.center[:count])
    normalized = np.clip((values-model.center[:count])/model.scale[:count], -10, 10)
    fixed_part = model.beta[0]+normalized@model.beta[1:1+count]+(~finite)@model.beta[1+width:1+width+count]
    return fixed_part, model.beta[1+count:1+width]


def forecast(model, origin, state, wake_clock, point, query_index, *, particles=512, horizon=480):
    offsets = gaussian_offset(point, model['scale'], np.arange(horizon))
    fixed = static_features(origin, np.arange(horizon), wake_clock)
    heads = [model['dynamic'], *model['care']]
    for head in heads[1:]:
        np.testing.assert_array_equal(head.center, heads[0].center)
        np.testing.assert_array_equal(head.scale, heads[0].scale)
    parts = [split_logits(head, fixed, 9) for head in heads]
    fixed_logits = np.column_stack([part[0] for part in parts])
    dynamic_weights = np.column_stack([part[1] for part in parts])
    def evolve(states, marks):
        return states*np.tile(np.exp(-1/DECAYS), 3)+np.repeat(marks, len(DECAYS), axis=1)
    def dynamic_predict(step, states, simulate):
        z = np.clip((np.log1p(states)-heads[0].center[-9:])/heads[0].scale[-9:], -10, 10)
        logits = fixed_logits[step]+z@dynamic_weights
        logits[:, 0] += offsets[step]
        probability = expit(logits)
        for j, head in enumerate(heads):
            if head.constant is not None:
                probability[:, j] = head.constant
        return probability[:, 0], probability[:, 1:] if simulate else np.zeros((len(states), 3))
    static_p = model['static'].predict(fixed, offsets)
    static_s = np.r_[1., np.cumprod(1-static_p)]
    frozen_s = marginal_survival(state.ravel(), lambda step, states: dynamic_predict(step, states, False), evolve, horizon=horizon, particles=1)
    seed = np.random.SeedSequence([42, int(query_index)])
    joint_s = marginal_survival(state.ravel(), lambda step, states: dynamic_predict(step, states, True), evolve, horizon=horizon, particles=particles, seed=seed)
    return dict(processStaticContext=survival_points(static_s)['median'],
                processNoFutureCare=survival_points(frozen_s)['median'],
                processMarginalMedian=survival_points(joint_s)['median'],
                processMarginalMean=survival_points(joint_s)['mean'])


def replay(data, context, base, stream, progress=None, *, particles=512, trainer=fit_process, forecaster=forecast):
    C, blocks = risk_blocks(data, context, base, stream)
    out = {k: base.copy() for k in ['processStaticContext', 'processNoFutureCare', 'processMarginalMedian', 'processMarginalMean']}
    model = None
    fitted = -24
    fit_labels = 0
    fits = []
    with threadpool_limits(limits=2):
        for i, now in enumerate(data['wakes']):
            known = eligible(data, context, i, True)
            if len(known) < 3:
                continue
            interval = 1 if len(known) < 40 else 24
            if model is None or i-fitted >= interval or fit_labels < 40 <= len(known):
                model = trainer(blocks, known, data['wakes'], now, base, data['y'])
                fitted, fit_labels = i, len(known)
                row = dict(query=i, labels=len(known), riskMinutes=model['riskMinutes'], scale=model['scale'], iterations=model['iterations'])
                fits.append(row)
                if progress:
                    progress(row)
            # The forecaster receives origin values and past state only, never
            # the current risk block, its actual sleep time, or its future care.
            state = states_at(stream, [now])[0]
            points = forecaster(model, C[i], state, context['wakeClock'][i], base[i], int(data['indices'][i]), particles=particles)
            if set(points) != set(out):
                raise ValueError('Incomplete forecast; retain every case and fail')
            for name, value in points.items():
                if not np.isfinite(value) or not 1 <= value <= 480:
                    raise ValueError('Invalid forecast')
                out[name][i] = value
    return out, dict(refits=fits, particles=particles)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    for key in ['source', 'features', 'baseline', 'output']:
        ap.add_argument('--'+key, type=Path, required=True)
    ap.add_argument('--limit', type=int)
    ap.add_argument('--particles', type=int, default=512)
    a = ap.parse_args()
    root = Path(__file__).resolve().parents[1]
    if a.output.resolve().is_relative_to(root):
        ap.error('Keep private risk paths and predictions outside source')
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    app = json.loads(a.baseline.read_text())
    assert app['audit']['sourceSHA256'] == sha(a.source)
    with np.load(a.features, allow_pickle=False) as f:
        d = dict(f)
    n = len(d['y'])
    if a.limit:
        d = {k: v[:a.limit] if v.ndim and len(v) == n else v for k, v in d.items()}
    rows = {e['index']: e for e in app['events']}
    np.testing.assert_array_equal([rows[int(i)]['wakeMinutes'] for i in d['indices']], d['y'])
    c = structure(a.source, d, rows, 'America/Los_Angeles')
    base = (np.array([rows[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60
    events, skipped = read_marks(a.source, 'America/Los_Angeles')
    stream = care_stream(events)
    start = time.monotonic()
    out, diag = replay(d, c, base, stream, lambda x: print(json.dumps(dict(**x, seconds=time.monotonic()-start)), flush=True), particles=a.particles)
    mask = planning_mask(d, c)
    masks = dict(planning=mask, naps=mask & (c['labels'] == 1), bedtime=mask & (c['labels'] == 2), allTimers=np.ones(len(mask), bool))
    helpers = ['research_sleep_behavior_schedule.py', 'research_sleep_care_signatures.py', 'research_sleep_planning.py', 'research_sleep_marked_survival.py', 'research_sleep_ensemble.py']
    result = dict(audit=dict(sourceSHA256=sha(a.source), scriptSHA256=sha(Path(__file__)),
        inputsSHA256={k: sha(getattr(a, k)) for k in ['features', 'baseline']}, helperSHA256={k: sha(root/'Scripts'/k) for k in helpers}, careExposure='completed',
        strategy='Minute-step independent Bernoulli hazards for sleep and three intermediate care marks. Regularized logit models use compact wake context, elapsed time, future known clock, and exponential care histories. Simulate only future care and average no-sleep probability over 512 fixed-seed paths.',
        training=dict(days=60, halfLifeDays=14, minimumLabels=3, earlyRefitsBelow40=True, refitQueries=24, allClocks=True, ridgePerEvent=.1, decayMinutes=DECAYS.tolist(), hazardPrior='Gaussian around originally issued app point; MAD scale from mature training residuals, minimum15minutes'),
        causalRule='Risk paths with observed intermediate care train models only after the full historical target sleep ends. Query forecaster receives only wake-known origin features and completed-care state; future care is generated, never read from the current actual risk path. All original cases retained.',
        diagnostics=diag, skippedRecords=skipped,
        sourceURLs=['https://proceedings.mlr.press/v216/boyd23a.html', 'https://papers.nips.cc/paper/2017/file/6463c88460bd63bbe256e495c63aa40b-Paper.pdf'],
        limitation='Independent discrete Bernoulli adaptation, not reproduction of continuous-time neural Hawkes or its benchmarks. Presence collapses duplicate same-type completions at a minute; latent draws are Monte Carlo estimates. Retrospective archive-selected research, not prospective validation. App unchanged.'), models={}, events={})
    for name, p in dict(appV8=base, **out).items():
        result['models'][name] = {key: metrics(d['y'], p, m) for key, m in masks.items()}
        result['events'][name] = [dict(index=int(i), actual=float(y), prediction=float(v)) for i, y, v in zip(d['indices'], d['y'], p)]
        print(name, json.dumps(result['models'][name]['planning']), flush=True)
    a.output.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n')


if __name__ == '__main__':
    main()
