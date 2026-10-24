#!/usr/bin/env python3
"""Distinct-planning neighbors with partial, wake-known sleep-cycle suffixes."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from research_sleep_behavior_schedule import structure
from research_sleep_cycle_alignment import dtw_costs, context_cost
from research_sleep_ensemble import metrics, weighted_median
from research_sleep_planning import eligible, planning_mask


def suffix_patterns(data, length=6):
    names=list(data['names']);X=data['X'];n=len(data['y'])
    cycles=np.column_stack([np.log1p(X[:,names.index('lastDuration')])/2,
        np.log1p(data['y'])/2,X[:,names.index('clockSin1')]/2,X[:,names.index('clockCos1')]/2])
    patterns=[]
    for i,now in enumerate(data['wakes']):
        rows=[];expected=int(data['indices'][i])-1
        for j in range(i-1,-1,-1):
            if len(rows)==length or data['wakes'][j]<now-7*86400:break
            if data['indices'][j]!=expected or data['available'][j]>now:break
            if not np.isfinite(cycles[j]).all():break
            rows.append(j);expected-=1
        patterns.append(cycles[rows[::-1]].copy())
    return patterns


def sequence_costs(query, histories, band):
    out=np.zeros(len(histories))
    # Compare the common observed suffix. Missing cycles are not invented.
    for length in range(1,len(query)+1):
        positions=[i for i,h in enumerate(histories) if min(len(query),len(h))==length]
        if positions:
            H=np.stack([histories[i][-length:] for i in positions])
            out[positions]=dtw_costs(query[-length:],H,band)/length
    return out


def replay(data, context, base, patterns):
    names=['contextOnly','fixedSequence','warpedSequence']
    out={name:base.copy() for name in names};counts=np.zeros(len(base),int)
    for i,now in enumerate(data['wakes']):
        known=eligible(data,context,i,True);counts[i]=len(known)
        if len(known)<3:continue
        anchor=context_cost(data,i,known)
        costs=[np.zeros(len(known)),sequence_costs(patterns[i],[patterns[j] for j in known],0),sequence_costs(patterns[i],[patterns[j] for j in known],2)]
        for name,cost in zip(names,costs):
            distance=np.sqrt(anchor+cost)
            if not np.isfinite(distance).all():raise ValueError('Nonfinite distance; retain cases and fail')
            order=np.lexsort((known,distance))[:15];neighbors=known[order]
            weights=np.exp2(-(now-data['wakes'][neighbors])/(14*86400))/(.1+distance[order])
            point=float(weighted_median(data['y'][neighbors],weights))
            if not np.isfinite(point):raise ValueError('Nonfinite forecast')
            out[name][i]=np.clip(point,1,480)
    return out,counts


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for key in ['source','features','baseline','output']:ap.add_argument('--'+key,type=Path,required=True)
    ap.add_argument('--limit',type=int);a=ap.parse_args();root=Path(__file__).resolve().parents[1]
    if a.output.resolve().is_relative_to(root):ap.error('Keep private history and results outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();app=json.loads(a.baseline.read_text())
    assert sha(a.source)==app['audit']['sourceSHA256']
    with np.load(a.features,allow_pickle=False) as z:d=dict(z)
    n=len(d['y'])
    if a.limit:d={k:v[:a.limit] if v.ndim and len(v)==n else v for k,v in d.items()}
    rows={e['index']:e for e in app['events']}
    np.testing.assert_array_equal([rows[int(i)]['wakeMinutes'] for i in d['indices']],d['y'])
    c=structure(a.source,d,rows,'America/Los_Angeles');base=(np.array([rows[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60
    patterns=suffix_patterns(d);forecasts,counts=replay(d,c,base,patterns)
    m=planning_mask(d,c);masks=dict(planning=m,naps=m&(c['labels']==1),bedtime=m&(c['labels']==2),allTimers=np.ones(len(m),bool))
    helpers=['research_sleep_cycle_alignment.py','research_sleep_behavior_schedule.py','research_sleep_ensemble.py','research_sleep_planning.py']
    r=dict(audit=dict(sourceSHA256=sha(a.source),scriptSHA256=sha(Path(__file__)),inputsSHA256={k:sha(getattr(a,k)) for k in ['features','baseline']},helperSHA256={k:sha(root/'Scripts'/k) for k in helpers},
        rule='Every wake receives a forecast. Only target-end-mature distinct-planning labels train neighbors. Frozen partial contiguous suffixes include only past resolved gaps. No current target routing.',
        settings=dict(maximumCycles=6,patternDays=7,trainingDays=60,minimumLabels=3,neighbors=15,halfLifeDays=14,warpingBand=2),
        patternLengths=[len(p) for p in patterns],trainingCounts=counts.tolist(),
        necessaryCapacity=dict(fixedPrimary=int(sum(m&(counts<3))),minimumPossibleMAE=float(sum(abs(base-d['y'])[m&(counts<3)])/sum(m)),maximumPossibleWithin30=float(100*(sum(m)-sum((abs(base-d['y'])>30)&m&(counts<3)))/sum(m))),
        limitation='General partial-suffix neighbor adaptation. Archive-selected retrospective comparison, not infant-specific published or prospective accuracy. Missing suffixes use context alone.'),models={},events={})
    for name,p in dict(appV8=base,**forecasts).items():
        r['models'][name]={key:metrics(d['y'],p,mask) for key,mask in masks.items()}
        r['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(d['indices'],d['y'],p)]
        print(name,json.dumps(r['models'][name]['planning']),flush=True)
    a.output.write_text(json.dumps(r,indent=2,allow_nan=False)+'\n')

if __name__=='__main__':main()
