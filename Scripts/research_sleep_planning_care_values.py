#!/usr/bin/env python3
"""Test completed numeric care details in the distinct-planning forest."""
import argparse
import hashlib
import json
from pathlib import Path
import time
from zoneinfo import ZoneInfo

import numpy as np
from threadpoolctl import threadpool_limits

from research_sleep_behavior_schedule import structure
from research_sleep_ensemble import metrics
from research_sleep_planning import eligible, planning_mask
from research_sleep_care_values import care_values
from research_sleep_predictions import read_structured_records, WakeAnalogs

CARE_COLUMNS=13


def completed_records(path, zone):
    records=read_structured_records(path, ZoneInfo(zone))
    return [r for r in records if r['Type']!='Feed' or r['endEpoch']>r['startEpoch']]


def value_inputs(records, wakes):
    return care_values(records, wakes)[0]


def replay(data, context, base, history, progress=None, factory=None):
    if history.shape != (len(base), CARE_COLUMNS) or np.isinf(history).any():
        raise ValueError('Invalid completed-care inputs')
    if factory is None:
        factory=lambda: WakeAnalogs('forest', 5)
    C=np.column_stack([data['X'], context['X'][:, 5:8]])
    X=dict(planningForestControl=C,
           paddedDimensionControl=np.column_stack([C, np.zeros_like(history)]),
           completedCareValuesForest=np.column_stack([C, history]))
    out={name:base.copy() for name in X}
    fitted, fit_labels=-24, 0
    models={};fits=[]
    with threadpool_limits(limits=2):
        for i in range(len(base)):
            known=eligible(data, context, i, True)
            if len(known)<3:
                continue
            interval=1 if len(known)<40 else 24
            if not models or i-fitted>=interval or fit_labels<40<=len(known):
                models={name:factory().fit(values[known], data['y'][known]) for name, values in X.items()}
                fitted, fit_labels=i, len(known)
                row=dict(query=i, labels=len(known));fits.append(row)
                if progress:progress(row)
            for name, model in models.items():
                values=np.asarray(model.predict(X[name][i:i+1]))
                if values.shape!=(1,) or not np.isfinite(values).all():
                    raise ValueError('Invalid forecast; retain all cases and fail')
                out[name][i]=np.clip(float(values[0]), 1, 480)
    return out,dict(refits=fits, featureCounts={name:values.shape[1] for name,values in X.items()})


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for key in ['source','features','baseline','control','output']:
        ap.add_argument('--'+key,type=Path,required=True)
    ap.add_argument('--limit',type=int)
    a=ap.parse_args();root=Path(__file__).resolve().parents[1]
    if a.output.resolve().is_relative_to(root):ap.error('Keep private history and results outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    app=json.loads(a.baseline.read_text());previous=json.loads(a.control.read_text())
    assert app['audit']['sourceSHA256']==previous['audit']['sourceSHA256']==sha(a.source)
    with np.load(a.features,allow_pickle=False) as f:d=dict(f)
    n=len(d['y'])
    if a.limit:d={k:v[:a.limit] if v.ndim and len(v)==n else v for k,v in d.items()}
    rows={e['index']:e for e in app['events']}
    np.testing.assert_array_equal([rows[int(i)]['wakeMinutes'] for i in d['indices']],d['y'])
    c=structure(a.source,d,rows,'America/Los_Angeles')
    base=(np.array([rows[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60
    records=completed_records(a.source,'America/Los_Angeles')
    H=value_inputs(records,d['wakes']);cache=a.output.with_suffix('.values.npy');np.save(cache,H,allow_pickle=False)
    start=time.monotonic()
    out,diag=replay(d,c,base,H,lambda x:print(json.dumps(dict(**x,seconds=time.monotonic()-start)),flush=True))
    prior={e['index']:e for e in previous['events']['planningForestControl']}
    np.testing.assert_array_equal(out['planningForestControl'],[prior[int(i)]['prediction'] for i in d['indices']])
    m=planning_mask(d,c);masks=dict(planning=m,naps=m&(c['labels']==1),bedtime=m&(c['labels']==2),allTimers=np.ones(len(m),bool))
    helpers=['research_sleep_predictions.py','research_sleep_behavior_schedule.py','research_sleep_planning.py','research_sleep_ensemble.py','research_sleep_care_values.py']
    r=dict(audit=dict(sourceSHA256=sha(a.source),scriptSHA256=sha(Path(__file__)),valuesSHA256=sha(cache),
        inputsSHA256={k:sha(getattr(a,k)) for k in ['features','baseline','control']},helperSHA256={k:sha(root/'Scripts'/k) for k in helpers},careExposure='completed',
        strategy='Augment the compact planning forest with13fixed numeric nursing-duration/side and diaper-type summaries from completed records. Same-width zero control isolates the added column count. These durations are not milk-volume measurements.',
        training=dict(days=60,minimumLabels=3,earlyRefitsBelow40=True,refitQueries=24,allClocks=True,trees=80,minimumLeaf=5,maxFeatures=.8,seed=42),
        causalRule='Only completed care at each row own wake forms the numeric inputs; unfinished or nonpositive-duration feeds are excluded. Training labels/type mature at target sleep end. Current/future targets never route. All original cases retained.',diagnostics=diag,compactControlExact=True,
        limitation='Planning-only supervision for fixed numeric care attributes; earlier care-value benchmarks trained all sleep transitions. Not an infant-specific published model. Feature count can change random split proposals; compare against both compact and padded controls. Retrospective archive-selected comparison, not prospective validation. App unchanged.'),models={},events={})
    for name,p in dict(appV8=base,**out).items():
        r['models'][name]={key:metrics(d['y'],p,mask) for key,mask in masks.items()}
        r['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(d['indices'],d['y'],p)]
        print(name,json.dumps(r['models'][name]['planning']),flush=True)
    a.output.write_text(json.dumps(r,indent=2,allow_nan=False)+'\n')


if __name__=='__main__':main()
