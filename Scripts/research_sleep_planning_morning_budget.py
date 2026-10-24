#!/usr/bin/env python3
"""Compare wake-gap targets with morning-relative elapsed and awake totals."""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
from zoneinfo import ZoneInfo
import numpy as np
from research_sleep_predictions import load_history,WakeAnalogs
from research_sleep_behavior_schedule import structure
from research_sleep_planning_boost import night_summary
from research_sleep_neural_observer import completed_intervals
from research_sleep_planning import eligible,planning_mask
from research_sleep_ensemble import metrics


def morning_features(sleeps,wakes,zone):
    tz=ZoneInfo(zone);out=np.full((len(wakes),4),np.nan)
    for i,now in enumerate(wakes):
        history=sleeps[(sleeps[:,0]<=now)&(sleeps[:,1]<=now)]
        anchor,clock,_=night_summary(history,dt.datetime.fromtimestamp(now,tz).date(),tz)
        if not np.isfinite(anchor):continue
        _,union=completed_intervals(history,now)
        elapsed=(now-anchor)/60
        asleep=sum(max(0,b-max(a,anchor)) for a,b in union if b>anchor)/60
        out[i]=[clock,elapsed,asleep,max(0,elapsed-asleep)]
    return out


def replay(data,context,base,morning,model_factory=None):
    if model_factory is None:model_factory=lambda:WakeAnalogs('forest',5)
    X=np.column_stack([data['X'],context['X'][:,5:8],morning])
    valid=np.isfinite(morning).all(axis=1);output={};diag={}
    for name,column in [('morningIntervalControl',None),('morningElapsedTarget',1),('morningAwakeTarget',3)]:
        anchor=np.zeros(len(base)) if column is None else morning[:,column]
        p=base.copy();model=None;fitted=-24;fits=learned=0
        for i in range(len(base)):
            known=eligible(data,context,i,True);known=known[valid[known]]
            if len(known)<40:continue
            if model is None or i-fitted>=24:
                model=model_factory().fit(X[known],data['y'][known]+anchor[known]);fitted=i;fits+=1
            if valid[i] and 360<=context['wakeClock'][i]<1260:
                p[i]=np.clip(float(model.predict(X[i:i+1])[0])-anchor[i],1,480);learned+=1
        output[name]=p;diag[name]=dict(refits=fits,learnedQueries=learned,validAnchorQueries=int(valid.sum()),features=X.shape[1])
    return output,diag


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for key in ['source','features','baseline','output']:ap.add_argument('--'+key,type=Path,required=True)
    ap.add_argument('--limit',type=int);a=ap.parse_args();root=Path(__file__).resolve().parents[1]
    if a.output.resolve().is_relative_to(root):ap.error('Keep private results outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    app=json.loads(a.baseline.read_text());assert app['audit']['sourceSHA256']==sha(a.source)
    with np.load(a.features,allow_pickle=False) as f:d=dict(f)
    n=len(d['y'])
    if a.limit:d={k:v[:a.limit] if v.ndim and len(v)==n else v for k,v in d.items()}
    rows={e['index']:e for e in app['events']}
    np.testing.assert_allclose([rows[int(i)]['wakeMinutes'] for i in d['indices']],d['y'],rtol=0,atol=1e-6)
    base=(np.array([rows[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60
    c=structure(a.source,d,rows,'America/Los_Angeles')
    sleeps,_,_,_=load_history(a.source,'1970-01-01','America/Los_Angeles')
    morning=morning_features(sleeps,d['wakes'],'America/Los_Angeles');featurePath=a.output.with_suffix('.morning.npy');np.save(featurePath,morning)
    predictions,diag=replay(d,c,base,morning);mask=planning_mask(d,c)
    masks={'planning':mask,'naps':mask&(c['labels']==1),'bedtime':mask&(c['labels']==2)}
    out=dict(audit=dict(sourceSHA256=sha(a.source),scriptSHA256=sha(Path(__file__)),featureSHA256=sha(a.features),baselineSHA256=sha(a.baseline),morningSHA256=sha(featurePath),
        helperSHA256={name:sha(root/'Scripts'/name) for name in ['research_sleep_predictions.py','research_sleep_behavior_schedule.py','research_sleep_planning_boost.py','research_sleep_neural_observer.py','research_sleep_planning.py','research_sleep_ensemble.py']},
        strategy='Last completed overnight end before local noon anchors the observed day. Four new shared inputs are morning clock, elapsed time, union sleep minutes and cumulative awake minutes since that anchor. Matched interval versus next-sleep elapsed or cumulative-awake targets, subtracting the known query anchor after prediction.',
        training=dict(days=60,minimumResolvedPlanningLabelsWithAnchor=40,refitQueries=24,trees=80,minimumLeaf=5),
        causalRule='Only completed sleep enters each origin anchor; target type and gap are only historical resolved labels. Missing morning anchors and overnight queries retain app points.',
        limitation='Empirical target transformation, not an imposed physiological sleep budget. Retrospective archive-selected comparison, not prospective validation.',diagnostics=diag),models={},events={})
    for name,p in {'appV8':base,**predictions}.items():
        out['models'][name]={k:metrics(d['y'],p,m) for k,m in masks.items()}
        out['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(d['indices'],d['y'],p)]
        print(name,json.dumps(out['models'][name]['planning']),flush=True)
    a.output.write_text(json.dumps(out,indent=2,allow_nan=False)+'\n')

if __name__=='__main__':main()
