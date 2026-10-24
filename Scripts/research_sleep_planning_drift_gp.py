#!/usr/bin/env python3
"""Matched stationary versus trend-capable personal planning processes."""
import argparse
import hashlib
import json
from pathlib import Path
import time
import warnings

import numpy as np
from scipy.optimize import minimize
import sklearn
from sklearn.exceptions import ConvergenceWarning
from sklearn.gaussian_process import GaussianProcessRegressor
from sklearn.gaussian_process.kernels import ConstantKernel, DotProduct, Matern, WhiteKernel
from sklearn.impute import SimpleImputer
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from threadpoolctl import threadpool_limits

from research_sleep_behavior_schedule import structure
from research_sleep_ensemble import metrics
from research_sleep_planning import eligible, planning_mask


class PlanningProcess:
    def __init__(self, linear, optimize=True):
        self.linear, self.optimize = linear, optimize

    def fit(self, X, y):
        self.inputs = make_pipeline(SimpleImputer(keep_empty_features=True), StandardScaler())
        X = self.inputs.fit_transform(X)
        kernel = ConstantKernel(1., (.1, 10))*Matern(np.ones(X.shape[1]), (.1, 100), nu=1.5)+WhiteKernel(.3, (.01, 10))
        if self.linear:
            kernel += ConstantKernel(1., (.01, 10))*DotProduct(sigma_0=0., sigma_0_bounds='fixed')
        self.optimization = []
        def optimizer(objective, initial, bounds):
            result = minimize(objective, initial, jac=True, bounds=bounds, method='L-BFGS-B', options=dict(maxiter=500))
            if not np.isfinite(result.fun) or not np.isfinite(result.x).all():
                raise ValueError('Nonfinite covariance fit')
            self.optimization.append(dict(converged=bool(result.success), iterations=int(result.nit), status=int(result.status), objective=float(result.fun)))
            return result.x, result.fun
        self.model = GaussianProcessRegressor(kernel=kernel, normalize_y=True, alpha=1e-6,
            optimizer=optimizer if self.optimize else None, n_restarts_optimizer=0, random_state=42)
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter('always', ConvergenceWarning)
            self.model.fit(X, y)
        unexpected = [w for w in caught if not issubclass(w.category, ConvergenceWarning)]
        if unexpected:
            raise RuntimeError('Unexpected covariance warning: '+str(unexpected[0].message))
        self.boundWarnings = sum(issubclass(w.category, ConvergenceWarning) for w in caught)
        return self

    def predict(self, X):
        return self.model.predict(self.inputs.transform(X))


def replay(data, context, base, progress=None, factory=PlanningProcess):
    X = np.column_stack([data['X'], context['X'][:, 5:8]])
    names = dict(stationaryPlanningProcess=False, trendPlanningProcess=True)
    out = {name: base.copy() for name in names}
    models = {}
    fitted, fit_labels = -24, 0
    fits = []
    with threadpool_limits(limits=2):
        for i in range(len(base)):
            known = eligible(data, context, i, True)
            if len(known) < 3:
                continue
            interval = 1 if len(known) < 40 else 24
            if not models or i-fitted >= interval or fit_labels < 40 <= len(known):
                residual = data['y'][known]-base[known]
                models = {name: factory(linear).fit(X[known], residual) for name, linear in names.items()}
                fitted, fit_labels = i, len(known)
                row = dict(query=i, labels=len(known), optimization={name: model.optimization for name, model in models.items()}, boundWarnings={name: model.boundWarnings for name, model in models.items()})
                fits.append(row)
                if progress:
                    progress(row)
            for name, model in models.items():
                values = np.asarray(model.predict(X[i:i+1]))
                if values.shape != (1,) or not np.isfinite(values).all():
                    raise ValueError('Invalid forecast; retain all cases and fail')
                out[name][i] = np.clip(base[i]+float(values[0]), 1, 480)
    return out, dict(refits=fits)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    for name in ['source', 'features', 'baseline', 'output']:
        ap.add_argument('--'+name, type=Path, required=True)
    ap.add_argument('--limit', type=int)
    a = ap.parse_args()
    root = Path(__file__).resolve().parents[1]
    if a.output.resolve().is_relative_to(root):
        ap.error('Keep private predictions outside source')
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
    start = time.monotonic()
    out, diag = replay(d, c, base, lambda x: print(json.dumps(dict(**x, seconds=time.monotonic()-start)), flush=True))
    m = planning_mask(d, c)
    masks = dict(planning=m, naps=m & (c['labels'] == 1), bedtime=m & (c['labels'] == 2), allTimers=np.ones(len(m), bool))
    helpers = ['research_sleep_behavior_schedule.py', 'research_sleep_planning.py', 'research_sleep_ensemble.py']
    result = dict(audit=dict(sourceSHA256=sha(a.source), scriptSHA256=sha(Path(__file__)),
        inputsSHA256={k: sha(getattr(a, k)) for k in ['features', 'baseline']}, helperSHA256={k: sha(root/'Scripts'/k) for k in helpers}, careExposure='completed',
        strategy='Residual Gaussian processes around originally issued app points. Both use the same learned Matérn covariance and observation noise; the candidate adds a learned linear covariance component capable of extrapolating beyond nearby observations.',
        training=dict(days=60, minimumLabels=3, earlyRefitsBelow40=True, refitQueries=24, allClocks=True, features=28, optimizationIterations=500, optimizerRestarts=0, randomState=42),
        causalRule='Only earlier target-end-resolved distinct-planning labels and their originally issued baseline errors fit scalers or covariances. Current/future outcome type never routes. All original cases retained.',
        sklearnVersion=sklearn.__version__, diagnostics=diag,
        sourceURLs=['https://scikit-learn.org/stable/modules/gaussian_process.html', 'https://scikit-learn.org/stable/modules/generated/sklearn.gaussian_process.kernels.DotProduct.html'],
        limitation='Empirical general-purpose covariance model, not a published infant-specific benchmark. Bounded optimization may end at its iteration limit; all optimizer statuses are disclosed. Retrospective archive-selected comparison, not prospective validation. App unchanged.'), models={}, events={})
    for name, p in dict(appV8=base, **out).items():
        result['models'][name] = {key: metrics(d['y'], p, mask) for key, mask in masks.items()}
        result['events'][name] = [dict(index=int(i), actual=float(y), prediction=float(v)) for i, y, v in zip(d['indices'], d['y'], p)]
        print(name, json.dumps(result['models'][name]['planning']), flush=True)
    a.output.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n')


if __name__ == '__main__':
    main()
