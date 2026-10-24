#!/usr/bin/env python3
"""Past-only Dirichlet-categorical residual run-length research, outside the app."""
import argparse
import hashlib
import json
import time
from pathlib import Path
import numpy as np
from scipy.special import logsumexp
from scipy.stats import laplace
from research_sleep_changepoints import calendar_hazard, groups
from research_sleep_ensemble import combine, metrics


class CategoricalRuns:
    """Full run-length posterior with reset before each available observation."""
    def __init__(self, prior):
        self.prior = np.asarray(prior, dtype=float)
        if not np.isfinite(self.prior).all() or np.any(self.prior <= 0):
            raise ValueError('Positive finite prior required')
        self.counts = np.zeros((1, len(prior)))
        self.logp = np.array([0.])
        self.count = 0

    def update(self, category, hazard):
        if not 0 <= category < len(self.prior) or not 0 <= hazard < 1:
            raise ValueError('Invalid category or hazard')
        totals = self.prior.sum() + self.counts.sum(axis=1)
        joint = self.logp + np.log((self.prior[category] + self.counts[:, category]) / totals)
        reset = np.log(hazard * self.prior[category] / self.prior.sum()) if hazard else -np.inf
        first = np.logaddexp(reset, joint[0] + np.log1p(-hazard))
        messages = np.r_[-np.inf, first, joint[1:] + np.log1p(-hazard)]
        self.logp = messages - logsumexp(messages)
        updated = self.counts.copy()
        updated[:, category] += 1
        self.counts = np.vstack([np.zeros(len(self.prior)), updated])
        self.count += 1

    def predictive(self, idle=0.):
        if not 0 <= idle < 1:
            raise ValueError('Invalid idle hazard')
        weights = np.exp(self.logp) * (1-idle)
        weights[0] += idle
        scaled = weights / (self.prior.sum() + self.counts.sum(axis=1))
        mass = scaled @ self.counts + self.prior * scaled.sum()
        return mass / mass.sum()


def decisions(mass, edges, lower, upper):
    """Uniform within cells: exact median and maximum ±30-minute mass."""
    cdf = np.r_[0., np.cumsum(mass)]
    cdf[-1] = 1.
    cell = min(len(mass)-1, int(np.searchsorted(cdf, .5, side='right')-1))
    median = edges[cell] + (edges[cell+1]-edges[cell]) * (.5-cdf[cell]) / mass[cell]
    median = float(np.clip(median, lower, upper))
    candidates = np.unique(np.clip(np.r_[edges-30, edges+30, median, lower, upper], lower, upper))
    covered = np.interp(candidates+30, edges, cdf) - np.interp(candidates-30, edges, cdf)
    tied = candidates[covered >= covered.max()-1e-12]
    modal = float(tied[np.argmin(abs(tied-median))])
    return median, modal


def replay(data, base, progress=None):
    edges = np.arange(-480., 481., 5.)
    prior_mass = np.diff(laplace.cdf(edges, scale=60.))
    prior_mass /= prior_mass.sum()
    n = len(base)
    output, diagnostics = {}, {}
    for kind in ['global', 'night', 'roles']:
        group = groups(data, kind)
        for strength in [2., 8.]:
            for days in [None, 7, 28]:
                states, last, seen = {}, {}, set()
                pred = {key: base.copy() for key in ['median', 'window30']}
                learned = updates = 0
                for i, now in enumerate(data['wakes']):
                    known = np.flatnonzero((np.arange(n) < i) & (data['available'] <= now))
                    for j in sorted((int(j) for j in known if int(j) not in seen), key=lambda j: (data['available'][j], j)):
                        g = int(group[j]); at = float(data['available'][j])
                        state = states.setdefault(g, CategoricalRuns(strength*prior_mass))
                        residual = float(data['y'][j]-base[j])
                        if not edges[0] <= residual <= edges[-1]:
                            raise ValueError('Residual outside declared support')
                        category = min(len(prior_mass)-1, int(np.searchsorted(edges, residual, side='right')-1))
                        state.update(category, calendar_hazard(at-last[g], days) if g in last else 0.)
                        last[g] = at; seen.add(j); updates += 1
                    g = int(group[i]); state = states.setdefault(g, CategoricalRuns(strength*prior_mass))
                    idle = calendar_hazard(now-last[g], days) if g in last else 0.
                    mass = state.predictive(idle)
                    points = decisions(mass, edges, 1-base[i], 480-base[i])
                    if state.count: learned += 1
                    for key, value in zip(pred, points): pred[key][i] = base[i]+value
                name = f'categoricalChange_{kind}_prior{strength:g}_h{days if days is not None else "none"}'
                output.update({name+'_'+key: value for key, value in pred.items()})
                diagnostics[name] = dict(updatedLabels=updates, learnedQueries=learned, priorOnlyQueries=n-learned, streams=len(states),
                    maximumNormalizationError=max(abs(float(np.exp(v.logp).sum())-1) for v in states.values()))
                if progress: progress(name, diagnostics[name])
    members = np.column_stack([base, *output.values()])
    for name, policy, cal, local in [('localCalibratedSoft','soft',True,True), ('localCalibratedBest','best',True,True),
            ('localRawSoft','soft',False,True), ('globalCalibratedSoft','soft',True,False), ('calibratedMedian','median',True,True)]:
        output['categoricalCombination_'+name] = combine(data, members, policy, cal, local)
    return output, diagnostics


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','baseline','output']: ap.add_argument('--'+name, type=Path, required=True)
    ap.add_argument('--limit', type=int)
    args = ap.parse_args(); root = Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root): ap.error('Keep private forecasts outside source')
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    d = dict(np.load(args.features, allow_pickle=False)); n = len(d['y'])
    if args.limit: d = {k: (v[:args.limit] if v.ndim and len(v)==n else v) for k,v in d.items()}
    baseline = json.loads(args.baseline.read_text()); assert baseline['audit']['sourceSHA256'] == sha(args.source)
    rows = {r['index']:r for r in baseline['events']}
    np.testing.assert_allclose([rows[int(i)]['actual'] for i in d['indices']], d['available'], rtol=0, atol=1e-6)
    np.testing.assert_allclose([rows[int(i)]['wakeMinutes'] for i in d['indices']], d['y'], rtol=0, atol=1e-6)
    base = (np.array([rows[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60
    start = time.monotonic()
    def progress(name, diag): print(json.dumps(dict(candidate=name, **diag, seconds=time.monotonic()-start)), flush=True)
    forecasts, diag = replay(d, base, progress)
    result = dict(audit=dict(sourceSHA256=sha(args.source), featureCacheSHA256=sha(args.features), baselineResultSHA256=sha(args.baseline),
        scriptSHA256=sha(Path(__file__)), helperFilesSHA256={name:sha(root/'Scripts'/name) for name in ['research_sleep_changepoints.py','research_sleep_ensemble.py']},
        careExposure='completed', prior='Truncated symmetric Laplace scale60 minutes, total pseudocount2 or8',
        likelihood='Categorical residual cell, Dirichlet conjugate prior; uniform within 5-minute cells for decisions',
        residualEdges=[-480,480], cellWidthMinutes=5, hazardDays=[None,7,28], resetTiming='Before observation; reset branch uses prior predictive',
        history='All available earlier labels; full run-length posterior, no pruning or minimum sample threshold', diagnostics=diag,
        decisions='Uniform-cell predictive median; maximum probability within30 with median-nearest tie break, restricted to planning bounds1..480',
        limitation='Independent general-method adaptation, not a published infant sleep result or independent future validation',
        sourceURLs=['https://arxiv.org/abs/0710.3742','https://www.cs.ubc.ca/~fwood/teaching/C19_hilary_2016_2017/c19.pdf']), models={}, events={})
    for name, p in forecasts.items():
        assert np.isfinite(p).all()
        result['models'][name] = dict(all=metrics(d['y'], p, np.ones(len(p), dtype=bool)))
        result['events'][name] = [dict(index=int(i), actual=float(y), prediction=float(v)) for i,y,v in zip(d['indices'],d['y'],p)]
        print(name, json.dumps(result['models'][name]), flush=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n')


if __name__ == '__main__': main()
