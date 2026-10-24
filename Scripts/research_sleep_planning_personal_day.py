#!/usr/bin/env python3
"""Learn personal night categories without changing the frozen evaluation cohort."""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
from zoneinfo import ZoneInfo
import numpy as np
from research_sleep_predictions import load_history,WakeAnalogs
from research_sleep_behavior_schedule import structure
from research_sleep_planning_phase_clock import phase_features
from research_sleep_planning import planning_mask
from research_sleep_ensemble import metrics


def midpoint_night(sleeps,center,zone):
    tz=ZoneInfo(zone)
    mid=(sleeps[:,0]+sleeps[:,1])/2
    clock=np.array([((v:=dt.datetime.fromtimestamp(t,tz)).hour*60+v.minute+v.second/60) for t in mid])
    return abs((clock-center+720)%1440-720)<=360


def adaptive_design(sleeps,data,context,phase,zone):
    """Query features use completed records; target midpoint only forms a label.

    The phase is frozen at the historical wake, not recomputed from future sleep.
    """
    C=np.column_stack([data['X'],context['X'][:,5:8]]);A=C.copy();labels=context['labels'].copy()
    names=list(data['names']);night_column=names.index('lastNight');count_column=names.index('napsToday');median_column=names.index('prior14d_kind_median')
    tz=ZoneInfo(zone)
    for k,index in enumerate(data['indices'].astype(int)):
        if not phase[k,3]:continue
        now=data['wakes'][k];center=phase[k,0]%(2*np.pi)*1440/(2*np.pi)
        current=sleeps[index];target=sleeps[index+1]
        current_night,target_night=midpoint_night(sleeps[index:index+2],center,zone)
        labels[k]=0 if data['y'][k]<=20 or (current_night and target_night) else (2 if target_night else 1)
        # Classification of a future target above never enters the feature path.
        history=sleeps[:index+1];history=history[history[:,1]<=now]
        flags=midpoint_night(history,center,zone)
        midnight=dt.datetime.fromtimestamp(now,tz).replace(hour=0,minute=0,second=0,microsecond=0).timestamp()
        A[k,night_column]=current_night;A[k,count_column]=np.sum((history[:,0]>=midnight)&~flags)
        ordinal=0
        for j,sleep in enumerate(history):
            if sleep[0]<midnight or flags[j]:continue
            joined=j>0 and not flags[j-1] and 0<=sleep[0]-history[j-1,1]<=1200
            if not joined:ordinal+=1
        A[k,-1]=ordinal
        old=np.flatnonzero((np.arange(len(data['y']))<k)&(data['available']<=now)&(data['wakes']>=now-14*86400))
        if len(old):
            old_flags=midpoint_night(sleeps[data['indices'][old].astype(int)],center,zone)
            same=old[old_flags==current_night]
        else:same=old
        A[k,median_column]=np.median(data['y'][same]) if len(same) else np.nan
    return C,A,labels


def replay(data,context,base,ordinary,adaptive,labels,progress=None,factory=None):
    if factory is None:factory=lambda:WakeAnalogs('forest',5)
    designs=dict(fixedDayControl=(ordinary,context['labels']),personalInputsOnly=(adaptive,context['labels']),
        personalCohortOnly=(ordinary,labels),personalDayPlanning=(adaptive,labels))
    out={};diag={};n=len(base)
    for name,(X,kind) in designs.items():
        p=base.copy();model=None;fitted=-24;fit_labels=0;fits=[]
        for i,now in enumerate(data['wakes']):
            known=np.flatnonzero((np.arange(n)<i)&(context['knownAt']<=now)&(data['wakes']>=now-60*86400)&(data['y']>20)&(kind!=0))
            if len(known)<3:continue
            interval=1 if len(known)<40 else 24
            if model is None or i-fitted>=interval or fit_labels<40<=len(known):
                model=factory().fit(X[known],data['y'][known]);fitted=i;fit_labels=len(known)
                entry=dict(query=i,labels=len(known));fits.append(entry)
                if progress:progress(dict(model=name,**entry))
            p[i]=np.clip(float(model.predict(X[i:i+1])[0]),1,480)
        out[name]=p;diag[name]=dict(refits=fits)
    return out,diag


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for key in ['source','features','baseline','control','output']:ap.add_argument('--'+key,type=Path,required=True)
    ap.add_argument('--limit',type=int);a=ap.parse_args();root=Path(__file__).resolve().parents[1]
    if a.output.resolve().is_relative_to(root):ap.error('Keep private results outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();app=json.loads(a.baseline.read_text());control=json.loads(a.control.read_text())
    assert app['audit']['sourceSHA256']==control['audit']['sourceSHA256']==sha(a.source)
    with np.load(a.features,allow_pickle=False) as f:d=dict(f)
    n=len(d['y'])
    if a.limit:d={k:v[:a.limit] if v.ndim and len(v)==n else v for k,v in d.items()}
    rows={e['index']:e for e in app['events']};c=structure(a.source,d,rows,'America/Los_Angeles')
    base=(np.array([rows[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60
    np.testing.assert_allclose([rows[int(i)]['wakeMinutes'] for i in d['indices']],d['y'],rtol=0,atol=1e-6)
    sleeps,_,_,_=load_history(a.source,'1970-01-01','America/Los_Angeles')
    phase=phase_features(sleeps,d['wakes'],'America/Los_Angeles');C,A,labels=adaptive_design(sleeps,d,c,phase,'America/Los_Angeles')
    cache=a.output.with_suffix('.design.npz');np.savez_compressed(cache,phase=phase,ordinary=C,adaptive=A,labels=labels)
    out,diag=replay(d,c,base,C,A,labels,lambda row:print(json.dumps(row),flush=True))
    by={e['index']:e for e in control['events']['planningForestControl']}
    np.testing.assert_array_equal([by[int(i)]['actual'] for i in d['indices']],d['y'])
    np.testing.assert_array_equal(out['fixedDayControl'],[by[int(i)]['prediction'] for i in d['indices']])
    m=planning_mask(d,c);alternative=(d['y']>20)&(labels!=0)
    masks=dict(planning=m,naps=m&(c['labels']==1),bedtime=m&(c['labels']==2),allTimers=np.ones(len(m),bool))
    r=dict(audit=dict(sourceSHA256=sha(a.source),scriptSHA256=sha(Path(__file__)),designSHA256=sha(cache),
        inputsSHA256={key:sha(getattr(a,key)) for key in ['features','baseline','control']},
        helperSHA256={key:sha(root/'Scripts'/key) for key in ['research_sleep_predictions.py','research_sleep_behavior_schedule.py','research_sleep_planning_phase_clock.py','research_sleep_neural_observer.py','research_sleep_planning.py','research_sleep_ensemble.py']},
        strategy='Personal night centered on completed-sleep occupancy first harmonic (7day history,3day half-life,min3elapsed days). Night if sleep midpoint within6h of frozen wake-time center. Change training cohort and/or four night-derived inputs in matched2x2 comparison; keep original1104 primaryevaluation.',
        training='28features,80trees,leaf5,seed42,60day history,min3labels,early per-query refitsbelow40/forced40crossingthen24querycadence,allclocks.',
        causalRule='Phase/features from completed sleep at each historical wake. Target midpoint only forms a label which matures at target END. Current target type/gap never routes predictions. No scored cases dropped or relabeled.',
        diagnostics=diag,fixedControlExact=True,validPhaseQueries=int(phase[:,3].sum()),
        cohortChanges=dict(added=int((alternative&~m).sum()),removed=int((m&~alternative).sum()),kindChanged=int((labels!=c['labels']).sum())),
        motivation='Public product documentation describes configurable day/night labels; no proprietary formula assumed.',
        limitation='An inferred category, not verified family day settings, measured circadian phase or proprietary-model reproduction. Product documentation motivates testing category assumptions, not this harmonic formula. Frozen scoring cohort unchanged. All-clock planning research is not overnight-resettling integration. Retrospective archive-selected comparison.'),models={},events={})
    for name,p in dict(appV8=base,**out).items():
        r['models'][name]={key:metrics(d['y'],p,mask) for key,mask in masks.items()}
        r['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(d['indices'],d['y'],p)]
        print(name,json.dumps(r['models'][name]['planning']),flush=True)
    a.output.write_text(json.dumps(r,indent=2,allow_nan=False)+'\n')


if __name__=='__main__':main()
