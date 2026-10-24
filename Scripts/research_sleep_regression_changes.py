#!/usr/bin/env python3
"""Causal run-length mixtures of conditional sleep residual regressions."""
import argparse
import hashlib
import json
import time
from pathlib import Path
import numpy as np
from scipy.special import gammaln, logsumexp, stdtr
from scipy.optimize import brentq
from research_sleep_changepoints import calendar_hazard
from research_sleep_ensemble import combine, metrics


class RegressionRuns:
    """Normal/inverse-gamma regression, full pre-observation reset messages."""
    def __init__(self, dimension, slope_precision=2.):
        self.prior_cov = np.diag([2.] + [1/slope_precision]*(dimension-1))
        self.cov = self.prior_cov[None].copy()
        self.mu = np.zeros((1, dimension))
        self.alpha = np.array([2.]); self.beta = np.array([1/3])
        self.logp = np.array([0.]); self.count = 0

    def components(self, x):
        v = np.einsum('rij,j->ri', self.cov, x)
        q = 1 + v @ x
        if np.any(q <= 0) or not np.isfinite(q).all():
            raise ValueError('Invalid predictive leverage')
        return self.mu @ x, 2*self.alpha, self.beta/self.alpha*q, v, q

    def update(self, x, y, hazard):
        if not np.isfinite(x).all() or not np.isfinite(y) or not 0 <= hazard < 1:
            raise ValueError('Invalid observation')
        loc, df, scale2, v, q = self.components(x)
        error = y-loc
        density = gammaln((df+1)/2)-gammaln(df/2)-.5*np.log(df*np.pi*scale2)-(df+1)/2*np.log1p(error**2/(df*scale2))
        joint = self.logp+density
        reset = np.log(hazard)+density[0] if hazard else -np.inf
        messages = np.r_[-np.inf, np.logaddexp(reset,joint[0]+np.log1p(-hazard)), joint[1:]+np.log1p(-hazard)]
        self.logp = messages-logsumexp(messages)
        self.mu = np.vstack([np.zeros(self.mu.shape[1]), self.mu+v*(error/q)[:,None]])
        updated = self.cov-v[:,:,None]*v[:,None,:]/q[:,None,None]
        self.cov = np.concatenate([self.prior_cov[None], (updated+updated.transpose(0,2,1))/2])
        self.alpha = np.r_[2., self.alpha+.5]
        self.beta = np.r_[1/3, self.beta+.5*error**2/q]
        self.count += 1

    def locations(self, x, idle=0., median=True):
        if not 0 <= idle < 1: raise ValueError('Invalid idle hazard')
        loc, df, scale2, _, _ = self.components(x)
        weights = np.exp(self.logp)*(1-idle); weights[0] += idle; weights /= weights.sum()
        mean = float(weights @ loc)
        if not median: return mean, None
        active = weights > 0
        w, mu, dof, scale = weights[active], loc[active], df[active], np.sqrt(scale2[active])
        lo, hi = float(min(mu)), float(max(mu))
        if lo == hi: return mean, lo
        point = brentq(lambda y: float(w@stdtr(dof,(y-mu)/scale)-.5), lo, hi, xtol=1e-9, rtol=1e-12)
        return mean, float(point)


def design(data, kind):
    """Fixed pointwise transforms: no fitting or future-query batch statistics."""
    names = list(data['names']); raw = data['X']
    clock = ['clockSin1','clockCos1','clockSin2','clockCos2']
    values = [raw[:,names.index(k)] for k in clock]
    numeric = [('ageDays',365.)]
    if kind == 'context':
        numeric += [('lastDuration',120.),('lastNight',1.),('napsToday',4.),('wakeLag1',120.),
            ('sleepMinutes6h',360.),('sleepMinutes24h',1440.),('lastFeedMinutes',180.),
            ('FeedCount3h',4.),('homeostat120_60',1.),('homeostat240_120',1.),
            ('prior7d_clock_median',120.),('prior7d_clock_shortFraction',1.),('prior14d_kind_median',120.)]
    for name, scale in numeric:
        col = raw[:,names.index(name)]; finite = np.isfinite(col)
        values.extend([np.tanh(np.where(finite,col,0.)/scale), (~finite).astype(float)])
    block = np.column_stack(values)
    if not np.isfinite(block).all(): raise ValueError('Nonfinite fixed clock features')
    return np.column_stack([np.ones(len(raw)), block/np.sqrt(block.shape[1])])


def replay(data, base, progress=None):
    output, diagnostics = {}, {}; n = len(base)
    for kind in ['clock','context']:
        X = design(data,kind)
        for precision in [2.,16.]:
            for days in [None,7,28]:
                model = RegressionRuns(X.shape[1],precision)
                seen = set(); last = None; learned = updates = 0
                pred = {key:base.copy() for key in (['locationMean'] if days is None else ['locationMean','predictiveMedian'])}
                for i, now in enumerate(data['wakes']):
                    known = np.flatnonzero((np.arange(n)<i)&(data['available']<=now))
                    for j in sorted((int(j) for j in known if int(j) not in seen),key=lambda j:(data['available'][j],j)):
                        at = float(data['available'][j])
                        model.update(X[j],float(data['y'][j]-base[j])/60,calendar_hazard(at-last,days) if last is not None else 0.)
                        seen.add(j); last = at; updates += 1
                    mean, median = model.locations(X[i],calendar_hazard(now-last,days) if last is not None else 0.,median=days is not None)
                    if model.count: learned += 1
                    for key, point in [('locationMean',mean),('predictiveMedian',median)]:
                        if key in pred: pred[key][i] = np.clip(base[i]+60*point,1,480)
                name = f'regressionChange_{kind}_precision{precision:g}_h{days if days is not None else "none"}'
                output.update({name+'_'+key:p for key,p in pred.items()})
                diagnostics[name] = dict(updatedLabels=updates,learnedQueries=learned,priorOnlyQueries=n-learned,
                    featureCount=X.shape[1],normalizationError=abs(float(np.exp(model.logp).sum())-1),
                    maximumCovarianceAsymmetry=float(np.max(abs(model.cov-model.cov.transpose(0,2,1)))),
                    minimumFinalCovarianceEigenvalue=float(np.linalg.eigvalsh(model.cov).min()))
                if progress: progress(name,diagnostics[name])
    members = np.column_stack([base,*output.values()])
    for name,policy,cal,local in [('localCalibratedSoft','soft',True,True),('localCalibratedBest','best',True,True),
            ('localRawSoft','soft',False,True),('globalCalibratedSoft','soft',True,False),('calibratedMedian','median',True,True)]:
        output['regressionChangeCombination_'+name] = combine(data,members,policy,cal,local)
    return output, diagnostics


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','baseline','output']: ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--limit',type=int)
    args = ap.parse_args(); root = Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root): ap.error('Keep private forecasts outside source')
    sha = lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    data = dict(np.load(args.features,allow_pickle=False)); n = len(data['y'])
    if args.limit: data = {k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in data.items()}
    baseline = json.loads(args.baseline.read_text()); assert baseline['audit']['sourceSHA256']==sha(args.source)
    rows = {e['index']:e for e in baseline['events']}
    np.testing.assert_allclose([rows[int(i)]['actual'] for i in data['indices']],data['available'],rtol=0,atol=1e-6)
    np.testing.assert_allclose([rows[int(i)]['wakeMinutes'] for i in data['indices']],data['y'],rtol=0,atol=1e-6)
    base = (np.array([rows[int(i)]['prediction'] for i in data['indices']])-data['wakes'])/60
    started = time.monotonic()
    def progress(name,diag): print(json.dumps(dict(candidate=name,**diag,seconds=time.monotonic()-started)),flush=True)
    forecasts,diag = replay(data,base,progress)
    result = dict(audit=dict(sourceSHA256=sha(args.source),featureCacheSHA256=sha(args.features),baselineResultSHA256=sha(args.baseline),
        scriptSHA256=sha(Path(__file__)),helperFilesSHA256={name:sha(root/'Scripts'/name) for name in ['research_sleep_changepoints.py','research_sleep_ensemble.py']},
        careExposure='completed',history='All available earlier residual labels, unpruned full run-length hypotheses; no minimum-label threshold',
        prior=dict(interceptPrecision=.5,slopePrecision=[2,16],alpha=2,beta=1/3,residualScaleMinutes=60),
        design='Fixed clock harmonics, tanh age and missingness; context adds known completed sleep, wake, feeding, homeostat and historical timing summaries. Non-intercept block divided by square root of its dimension',
        resetTiming='Before observation with prior predictive evidence; idle calendar prior mixture; hazards none/7/28 days',
        likelihood='Conditionally normal linear residuals with normal/inverse-gamma coefficients/variance; Student-t predictive components',
        decisions='Mixture location mean and numerical predictive median; no-change symmetry counted once; bounds1..480 minutes',diagnostics=diag,
        sourceURLs=['https://arxiv.org/abs/0710.3742','https://arxiv.org/html/2112.12899v2'],
        limitation='Independent scalar conditional-regression adaptation, without cited multivariate/outlier machinery; not infant physiology or independent future validation'),models={},events={})
    for name,p in forecasts.items():
        assert np.isfinite(p).all()
        result['models'][name] = dict(all=metrics(data['y'],p,np.ones(len(p),dtype=bool)))
        result['events'][name] = [dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(data['indices'],data['y'],p)]
        print(name,json.dumps(result['models'][name]),flush=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')


if __name__ == '__main__': main()
