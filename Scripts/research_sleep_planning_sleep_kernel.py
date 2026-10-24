#!/usr/bin/env python3
"""Learn a smooth response to the profile's completed sleep-state history."""
import argparse
import hashlib
import json
from pathlib import Path
import time

import numpy as np
from scipy.optimize import minimize
from scipy.special import expit
from scipy.linalg import solve_triangular
from threadpoolctl import threadpool_limits

from research_sleep_behavior_schedule import structure
from research_sleep_ensemble import metrics
from research_sleep_marked_survival import survival_points
from research_sleep_planning import eligible, planning_mask
from research_sleep_planning_care_process import BinaryHazard, gaussian_offset, risk_blocks, static_features
from research_sleep_predictions import load_history

LAG_MINUTES = 15
LAG_BINS = 96


def completed_union(sleeps, now):
    known = sleeps[(sleeps[:, 1] <= now) & (sleeps[:, 0] <= now), :2]
    if not len(known):
        return np.empty((0, 2))
    intervals = []
    for start, end in known[np.argsort(known[:, 0], kind='stable')]:
        if intervals and start <= intervals[-1][1]:
            intervals[-1][1] = max(end, intervals[-1][1])
        else:
            intervals.append([float(start), float(end)])
    return np.array(intervals)


def integrated_sleep(intervals, times):
    times = np.asarray(times, float)
    if not len(intervals):
        return np.zeros(times.shape)
    duration = intervals[:, 1]-intervals[:, 0]
    prefix = np.r_[0., np.cumsum(duration)]
    count = np.searchsorted(intervals[:, 1], times, side='right')
    index = np.minimum(count, len(intervals)-1)
    partial = np.clip(times-intervals[index, 0], 0, duration[index])
    return prefix[count]+np.where(count < len(intervals), partial, 0)


def lag_features(sleeps, now, elapsed):
    """Shift observed history forward assuming no new sleep before the target."""
    intervals = completed_union(sleeps, now)
    if not len(intervals):
        return np.full((len(elapsed), LAG_BINS), np.nan)
    edges = now+np.asarray(elapsed)[:, None]*60-np.arange(LAG_BINS+1)[None, :]*LAG_MINUTES*60
    integral = integrated_sleep(intervals, edges)
    values = (integral[:, :-1]-integral[:, 1:])/(LAG_MINUTES*60)
    values[edges[:, 1:] < intervals[0, 0]] = np.nan
    if np.isfinite(values).any() and (np.nanmin(values) < -1e-12 or np.nanmax(values) > 1+1e-12):
        raise ValueError('Invalid sleep occupancy fraction')
    return values


def penalty(beta, scales, static_columns, bins):
    """Smooth physical lag coefficients; keep ordinary context ridge unchanged."""
    width = static_columns+bins
    grad = np.zeros_like(beta)
    ordinary = np.r_[np.arange(1, 1+static_columns), np.arange(1+width, len(beta))]
    value = .05*np.dot(beta[ordinary], beta[ordinary])
    grad[ordinary] = .1*beta[ordinary]
    lag = slice(1+static_columns, 1+width)
    physical = beta[lag]/scales[static_columns:]
    second = np.diff(physical, n=2)
    value += .0005*np.dot(physical, physical)+.5*np.dot(second, second)
    smooth_gradient = np.zeros(bins)
    smooth_gradient[:-2] += second
    smooth_gradient[1:-1] -= 2*second
    smooth_gradient[2:] += second
    grad[lag] = (.001*physical+smooth_gradient)/scales[static_columns:]
    return value, grad


class SleepKernelHazard(BinaryHazard):
    def __init__(self, static_columns, bins=LAG_BINS):
        self.static_columns, self.bins = static_columns, bins
        second = np.diff(np.eye(bins), n=2, axis=0)
        self.lag_factor = np.linalg.cholesky(.001*np.eye(bins)+second.T@second)

    def design(self, X):
        A = super().design(X)
        lag = slice(1+self.static_columns, 1+self.static_columns+self.bins)
        physical = A[:, lag]*self.scale[self.static_columns:]
        A[:, lag] = solve_triangular(self.lag_factor, physical.T, lower=True).T
        return A

    def fit(self, X, y, offset, weights):
        X, y, offset, weights = [np.asarray(v, float) for v in [X, y, offset, weights]]
        if X.ndim != 2 or X.shape[1] != self.static_columns+self.bins or y.shape != (len(X),) or offset.shape != y.shape or weights.shape != y.shape:
            raise ValueError('Invalid sleep-kernel training dimensions')
        if np.isinf(X).any() or not all(np.isfinite(v).all() for v in [y, offset, weights]) or (weights <= 0).any() or not np.isin(y, [0., 1.]).all():
            raise ValueError('Invalid sleep-kernel observations')
        finite = np.isfinite(X)
        count = (finite*weights[:, None]).sum(axis=0)
        self.center = np.divide((np.where(finite, X, 0)*weights[:, None]).sum(axis=0), count, out=np.zeros(X.shape[1]), where=count > 0)
        values = np.where(finite, X, self.center)
        self.scale = np.maximum(np.sqrt(np.average((values-self.center)**2, axis=0, weights=weights)), .1)
        self.constant = None
        A = self.design(X)
        normalizer = max(float(np.dot(weights, y)), 1.)
        ridge = np.full(A.shape[1], .1)
        ridge[0] = 0.
        ridge[1+self.static_columns:1+self.static_columns+self.bins] = 1.
        def objective(beta):
            eta = offset+A@beta
            regularization = .5*np.dot(ridge*beta, beta)
            value = np.dot(weights, np.logaddexp(0., eta)-y*eta)/normalizer+regularization
            gradient = A.T@((expit(eta)-y)*weights)/normalizer+ridge*beta
            return value, gradient
        result = minimize(objective, np.zeros(A.shape[1]), jac=True, method='L-BFGS-B', options=dict(maxiter=2000, ftol=1e-10, gtol=1e-6))
        if not result.success or not np.isfinite(result.x).all():
            raise RuntimeError('Sleep-kernel fit failed: '+str(result.message))
        self.beta, self.iterations = result.x, int(result.nit)
        return self


def replay(data, context, base, sleeps, progress=None, factory=SleepKernelHazard):
    C, blocks = risk_blocks(data, context, base, np.empty((0, 2)))
    lag = [lag_features(sleeps, now, block['elapsed']) for now, block in zip(data['wakes'], blocks)]
    out = {name: base.copy() for name in ['staticHazardMedian', 'staticHazardMean', 'sleepKernelMedian', 'sleepKernelMean']}
    fitted, fit_labels = -24, 0
    control = model = None
    refits = []
    scale = None
    with threadpool_limits(limits=2):
        for i, now in enumerate(data['wakes']):
            known = eligible(data, context, i, True)
            if len(known) < 3:
                continue
            interval = 1 if len(known) < 40 else 24
            if model is None or i-fitted >= interval or fit_labels < 40 <= len(known):
                X = np.vstack([blocks[j]['X'] for j in known])
                H = np.vstack([lag[j] for j in known])
                y = np.concatenate([blocks[j]['sleep'] for j in known])
                weights = np.concatenate([np.full(len(blocks[j]['sleep']), np.exp2(-(now-data['wakes'][j])/(14*86400))) for j in known])
                residual = data['y'][known]-base[known]
                scale = max(15., 1.4826*float(np.median(abs(residual-np.median(residual)))))
                offset = np.concatenate([gaussian_offset(base[j], scale, blocks[j]['elapsed']) for j in known])
                control = BinaryHazard().fit(X, y, offset, weights)
                model = factory(X.shape[1]).fit(np.column_stack([X, H]), y, offset, weights)
                fitted, fit_labels = i, len(known)
                row = dict(query=i, labels=len(known), riskMinutes=len(X), scale=scale, controlIterations=control.iterations, kernelIterations=model.iterations)
                refits.append(row)
                if progress:
                    progress(row)
            elapsed = np.arange(480)
            X = static_features(C[i], elapsed, context['wakeClock'][i])
            H = lag_features(sleeps, now, elapsed)
            offset = gaussian_offset(base[i], scale, elapsed)
            for prefix, fitted_model, values in [('staticHazard', control, X), ('sleepKernel', model, np.column_stack([X, H]))]:
                probability = fitted_model.predict(values, offset)
                if probability.shape != (480,) or not np.isfinite(probability).all() or ((probability < 0) | (probability > 1)).any():
                    raise ValueError('Invalid hazard; retain all cases and fail')
                points = survival_points(np.r_[1., np.cumprod(1-probability)])
                out[prefix+'Median'][i], out[prefix+'Mean'][i] = points['median'], points['mean']
    return out, dict(refits=refits, lagBins=LAG_BINS, lagMinutes=LAG_MINUTES)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    for key in ['source', 'features', 'baseline', 'control', 'output']:
        ap.add_argument('--'+key, type=Path, required=True)
    ap.add_argument('--limit', type=int)
    a = ap.parse_args()
    root = Path(__file__).resolve().parents[1]
    if a.output.resolve().is_relative_to(root):
        ap.error('Keep private history and results outside source')
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    app, previous = [json.loads(p.read_text()) for p in [a.baseline, a.control]]
    assert app['audit']['sourceSHA256'] == previous['audit']['sourceSHA256'] == sha(a.source)
    with np.load(a.features, allow_pickle=False) as f:
        d = dict(f)
    n = len(d['y'])
    if a.limit:
        d = {k: v[:a.limit] if v.ndim and len(v) == n else v for k, v in d.items()}
    rows = {e['index']: e for e in app['events']}
    np.testing.assert_array_equal([rows[int(i)]['wakeMinutes'] for i in d['indices']], d['y'])
    c = structure(a.source, d, rows, 'America/Los_Angeles')
    base = (np.array([rows[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60
    sleeps = load_history(a.source, '1970-01-01', 'America/Los_Angeles')[0]
    start = time.monotonic()
    out, diag = replay(d, c, base, sleeps, lambda x: print(json.dumps(dict(**x, seconds=time.monotonic()-start)), flush=True))
    by = {e['index']: e for e in previous['events']['processStaticContext']}
    np.testing.assert_array_equal(out['staticHazardMedian'], [by[int(i)]['prediction'] for i in d['indices']])
    mask = planning_mask(d, c)
    masks = dict(planning=mask, naps=mask & (c['labels'] == 1), bedtime=mask & (c['labels'] == 2), allTimers=np.ones(len(mask), bool))
    helpers = ['research_sleep_predictions.py', 'research_sleep_behavior_schedule.py', 'research_sleep_planning.py', 'research_sleep_ensemble.py', 'research_sleep_marked_survival.py', 'research_sleep_planning_care_process.py']
    result = dict(audit=dict(sourceSHA256=sha(a.source), scriptSHA256=sha(Path(__file__)),
        inputsSHA256={k: sha(getattr(a, k)) for k in ['features', 'baseline', 'control']}, helperSHA256={k: sha(root/'Scripts'/k) for k in helpers}, careExposure='completed',
        strategy='Learn a smooth distributed-lag sleep-history contribution to minute sleep hazards: 96 prior15minute occupancy fractions span24hours, shifted under no-new-sleep until target. Completed timers only, union of overlaps, unknown pre-history remains missing.',
        training=dict(days=60, halfLifeDays=14, minimumLabels=3, earlyRefitsBelow40=True, refitQueries=24, allClocks=True, contextRidge=.1, physicalLagRidge=.001, lagSecondDifferencePenalty=1., optimizationIterations=2000),
        causalRule='Each historical lag feature uses sleep timers completed by its OWN wake, not the refit wake. Query assumes no new sleep before the event; actual future sleep never enters its lag features. Training target/type mature at sleep end. All original cases retained.',
        diagnostics=diag, staticControlExact=True, sourceURL='https://doi.org/10.1111/biom.12645',
        limitation='Independent linear occupancy/lag hazard adaptation with fixed smoothness, not the published full nonlinear cross-basis/REML method or an infant benchmark. Minute output precision does not imply minute accuracy. Retrospective archive-selected comparison; app unchanged.'), models={}, events={})
    for name, p in dict(appV8=base, **out).items():
        result['models'][name] = {key: metrics(d['y'], p, m) for key, m in masks.items()}
        result['events'][name] = [dict(index=int(i), actual=float(y), prediction=float(v)) for i, y, v in zip(d['indices'], d['y'], p)]
        print(name, json.dumps(result['models'][name]['planning']), flush=True)
    a.output.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n')


if __name__ == '__main__':
    main()
