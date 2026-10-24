#!/usr/bin/env python3
"""Replay distinct nap/bedtime planning with resolved-label training cohorts.

Every wake still receives a forecast. Future gap/type selects evaluation rows
and previously resolved training examples only, never the current prediction.
"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from sklearn.ensemble import ExtraTreesClassifier
from research_sleep_behavior_schedule import structure, weighted_median
from research_sleep_predictions import WakeAnalogs
from research_sleep_timing_curves import wake_groups
from research_sleep_ensemble import metrics


def planning_mask(data, context):
    return (data['y'] > 20) & (context['labels'] != 0)


def eligible(data, context, i, planning_only):
    now=data['wakes'][i]
    mask=(np.arange(len(data['y']))<i)&(context['knownAt']<=now)&(data['wakes']>=now-60*86400)
    if planning_only: mask &= planning_mask(data,context)
    return np.flatnonzero(mask)


def replay(data, context, base, progress=None):
    outputs={}; diagnostics={}; n=len(base)
    # Same model, features, label maturity and cadence; only training population differs.
    X=np.column_stack([data['X'],context['X'][:,5:8]])
    for specialists in [False,True]:
        groups=wake_groups(context,True) if specialists else np.zeros(n,dtype=int)
        for planning_only in [False,True]:
            p=base.copy(); models={}; fitted={}; fits=learned=0
            for i in range(n):
                g=int(groups[i]); known=eligible(data,context,i,planning_only)
                known=known[groups[known]==g]
                if len(known)>=40 and i-fitted.get(g,-24)>=24:
                    models[g]=WakeAnalogs('forest',5).fit(X[known],data['y'][known]); fitted[g]=i; fits+=1
                if g in models: p[i]=np.clip(models[g].predict(X[i:i+1])[0],1,480); learned+=1
            name=('contexts' if specialists else 'pooled')+('_planning' if planning_only else '_all')
            outputs[name]=p; diagnostics[name]=dict(refits=fits,learnedQueries=learned,fallbackQueries=n-learned)
            if progress: progress(name,diagnostics[name])
    # Separate learned nap intervals and bedtime clocks. Gate uses wake-known inputs.
    p=base.copy(); fitted=-24; gate=None; fits=learned=0
    labels=context['labels']; C=context['X']
    for i,now in enumerate(data['wakes']):
        known=eligible(data,context,i,True)
        if len(known)>=40 and i-fitted>=24:
            gate=ExtraTreesClassifier(n_estimators=80,min_samples_leaf=5,max_features=.8,random_state=42,n_jobs=1).fit(C[known],labels[known])
            nap=known[labels[known]==1]; bed=known[labels[known]==2]
            nap_model=WakeAnalogs('forest',5).fit(X[nap],data['y'][nap]) if len(nap)>=20 else None
            # Unwrap bedtime clocks around 18:00 to avoid midnight discontinuity.
            bed_clock=(context['targetClock'][bed]-1080+720)%1440-720+1080
            bed_model=WakeAnalogs('forest',5).fit(X[bed],bed_clock) if len(bed)>=20 else None
            fitted=i; fits+=1
        if gate is None: continue
        probs=dict(zip(gate.classes_,gate.predict_proba(C[i:i+1])[0])); points=[]; weights=[]
        if nap_model is not None: points.append(float(nap_model.predict(X[i:i+1])[0])); weights.append(probs.get(1,0))
        if bed_model is not None:
            point=(float(bed_model.predict(X[i:i+1])[0])-context['wakeClock'][i])%1440
            points.append(point); weights.append(probs.get(2,0))
        if sum(weights)>0: p[i]=np.clip(weighted_median(points,weights),1,480); learned+=1
    outputs['napInterval_bedtimeClock']=p; diagnostics['napInterval_bedtimeClock']=dict(refits=fits,learnedQueries=learned,fallbackQueries=n-learned)
    if progress: progress('napInterval_bedtimeClock',diagnostics['napInterval_bedtimeClock'])
    return outputs,diagnostics


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for key in ['source','features','baseline','output']: ap.add_argument('--'+key,type=Path,required=True)
    ap.add_argument('--limit',type=int); args=ap.parse_args(); root=Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root): ap.error('Keep private results outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    baseline=json.loads(args.baseline.read_text()); assert baseline['audit']['sourceSHA256']==sha(args.source)
    rows={e['index']:e for e in baseline['events']}; data=dict(np.load(args.features,allow_pickle=False)); n=len(data['y'])
    if args.limit: data={k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in data.items()}
    np.testing.assert_allclose([rows[int(i)]['wakeMinutes'] for i in data['indices']],data['y'],rtol=0,atol=1e-6)
    context=structure(args.source,data,rows,'America/Los_Angeles')
    base=(np.array([rows[int(i)]['prediction'] for i in data['indices']])-data['wakes'])/60
    forecasts,diagnostics=replay(data,context,base,lambda name,d:print(name,json.dumps(d),flush=True))
    forecasts={'app':base,**forecasts}; planning=planning_mask(data,context)
    result=dict(audit=dict(sourceSHA256=sha(args.source),scriptSHA256=sha(Path(__file__)),featureCacheSHA256=sha(args.features),baselineSHA256=sha(args.baseline),
        cohort='Actual gap >20 minutes; next nap or preceding nap. Excludes night-to-night returns. Type is inferred from clock and continuity.',
        causalRule='Predict every wake; current target type/gap never routes forecast. Training membership only after target sleep ends.',
        training=dict(lookbackDays=60,minimumLabels=40,refitQueries=24),
        limitation='Retrospective exploratory comparison on one archive; primary cohort changed at user request; not prospective validation.',diagnostics=diagnostics,
        helperSHA256={name:sha(root/'Scripts'/name) for name in ['research_sleep_behavior_schedule.py','research_sleep_predictions.py','research_sleep_timing_curves.py','research_sleep_ensemble.py']}),models={},events={})
    masks=dict(planning=planning,naps=planning&(context['labels']==1),bedtime=planning&(context['labels']==2),briefReturns=data['y']<=20,nightReturns=(~planning)&(data['y']>20),allTimers=np.ones(len(base),bool))
    for name,p in forecasts.items():
        result['models'][name]={key:metrics(data['y'],p,m) for key,m in masks.items()}
        result['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(data['indices'],data['y'],p)]
        print(name,json.dumps(result['models'][name]['planning']),flush=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')

if __name__=='__main__': main()
