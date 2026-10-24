#!/usr/bin/env python3
"""Isolate known weekly context in the distinct-sleep planning forest."""
import argparse
import hashlib
import json
from pathlib import Path
import time

import numpy as np
from threadpoolctl import threadpool_limits

from research_sleep_predictions import WakeAnalogs
from research_sleep_behavior_schedule import structure
from research_sleep_planning import eligible, planning_mask
from research_sleep_weekly import weekly_features
from research_sleep_ensemble import metrics


def replay(data, context, base, progress=None, factory=None):
    if factory is None:
        factory = lambda: WakeAnalogs('forest', 5)
    compact = np.column_stack([data['X'], context['X'][:, 5:8]])
    names = np.array(list(data['names']) + ['completedEpisodeSleepMinutes', 'completedEpisodeSegments', 'completedNapEpisodesToday'])
    matrices = {'planningForestControl': compact}
    for name, encoding in [('calendarWeekday', 'weekday'), ('calendarWeeklyClock', 'weeklyClock')]:
        matrices[name] = weekly_features(dict(data, X=compact, names=names), 'America/Los_Angeles', encoding)['X']
    out = {name: base.copy() for name in matrices}
    fitted = -24
    fit_labels = 0
    models = {}
    refits = []
    with threadpool_limits(limits=2):
        for i in range(len(base)):
            known = eligible(data, context, i, True)
            if len(known) < 3:
                continue
            interval = 1 if len(known) < 40 else 24
            if not models or i - fitted >= interval or fit_labels < 40 <= len(known):
                models = {name: factory().fit(X[known], data['y'][known]) for name, X in matrices.items()}
                fitted = i
                fit_labels = len(known)
                refits.append(dict(query=i, labels=len(known)))
                if progress:
                    progress(refits[-1])
            for name, model in models.items():
                values = np.asarray(model.predict(matrices[name][i:i+1]))
                if values.shape != (1,) or not np.isfinite(values).all():
                    raise ValueError('Invalid point; retain all cases and fail the experiment')
                out[name][i] = np.clip(float(values[0]), 1, 480)
    return out, dict(refits=refits, featureCounts={k: v.shape[1] for k, v in matrices.items()})


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    for key in ['source', 'features', 'baseline', 'control', 'output']:
        ap.add_argument('--' + key, type=Path, required=True)
    ap.add_argument('--limit', type=int)
    a = ap.parse_args()
    root = Path(__file__).resolve().parents[1]
    if a.output.resolve().is_relative_to(root):
        ap.error('Keep private predictions outside source')
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    app = json.loads(a.baseline.read_text())
    control = json.loads(a.control.read_text())
    assert app['audit']['sourceSHA256'] == control['audit']['sourceSHA256'] == sha(a.source)
    with np.load(a.features, allow_pickle=False) as f:
        d = dict(f)
    n = len(d['y'])
    if a.limit:
        d = {k: v[:a.limit] if v.ndim and len(v) == n else v for k, v in d.items()}
    rows = {e['index']: e for e in app['events']}
    np.testing.assert_array_equal([rows[int(i)]['wakeMinutes'] for i in d['indices']], d['y'])
    context = structure(a.source, d, rows, 'America/Los_Angeles')
    base = (np.array([rows[int(i)]['prediction'] for i in d['indices']]) - d['wakes']) / 60
    start = time.monotonic()
    out, diag = replay(d, context, base, lambda x: print(json.dumps(dict(**x, seconds=time.monotonic()-start)), flush=True))
    by = {e['index']: e for e in control['events']['planningForestControl']}
    np.testing.assert_array_equal([by[int(i)]['actual'] for i in d['indices']], d['y'])
    np.testing.assert_array_equal(out['planningForestControl'], [by[int(i)]['prediction'] for i in d['indices']])
    mask = planning_mask(d, context)
    masks = dict(planning=mask, naps=mask & (context['labels'] == 1), bedtime=mask & (context['labels'] == 2), allTimers=np.ones(len(mask), bool))
    helpers = ['research_sleep_predictions.py', 'research_sleep_behavior_schedule.py', 'research_sleep_planning.py', 'research_sleep_weekly.py', 'research_sleep_ensemble.py']
    r = dict(audit=dict(sourceSHA256=sha(a.source), scriptSHA256=sha(Path(__file__)),
        inputsSHA256={k: sha(getattr(a, k)) for k in ['features', 'baseline', 'control']},
        helperSHA256={k: sha(root/'Scripts'/k) for k in helpers}, careExposure='completed',
        strategy='Matched compact planning forest with either seven fixed weekday indicators or four fixed weekly-clock harmonics. Calendar is computed from known wake time in Pacific time.',
        training=dict(days=60, minimumLabels=3, earlyRefitsBelow40=True, refitQueries=24, trees=80, minimumLeaf=5, seed=42, allClocks=True),
        causalRule='Only earlier target-end-resolved distinct-planning labels enter training. Current/future gap and type never route or fit a calendar encoder. All original cases retained.',
        controlExact=True, diagnostics=diag,
        limitation='Retrospective archive-selected comparison, not prospective validation. Earlier wide-input and all-transition weekly experiments do not isolate this planning-only calendar augmentation. App unchanged.'), models={}, events={})
    for name, p in dict(appV8=base, **out).items():
        r['models'][name] = {key: metrics(d['y'], p, m) for key, m in masks.items()}
        r['events'][name] = [dict(index=int(i), actual=float(y), prediction=float(v)) for i, y, v in zip(d['indices'], d['y'], p)]
        print(name, json.dumps(r['models'][name]['planning']), flush=True)
    a.output.write_text(json.dumps(r, indent=2, allow_nan=False)+'\n')


if __name__ == '__main__':
    main()
