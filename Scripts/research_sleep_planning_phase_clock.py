#!/usr/bin/env python3
"""Sleep-occupancy phase as a causal, personal clock for planning forecasts."""
import argparse
import bisect
import datetime as dt
import hashlib
import json
from pathlib import Path
from zoneinfo import ZoneInfo
import numpy as np
from research_sleep_neural_observer import completed_intervals
from research_sleep_predictions import load_history,WakeAnalogs
from research_sleep_behavior_schedule import structure
from research_sleep_planning import eligible,planning_mask
from research_sleep_ensemble import metrics


def offset_table(lower,upper,zone):
    tz=ZoneInfo(zone);out=[]
    for t in range(int(lower//3600)*3600,int(upper//3600+2)*3600,3600):
        offset=dt.datetime.fromtimestamp(t,tz).utcoffset().total_seconds()
        if not out or offset!=out[-1][1]:out.append((float(t),offset))
    return out


def occupancy_moment(intervals,now,offsets):
    """Exact continuous recency-weighted first harmonic; split at DST changes."""
    rate=np.log(2)/(3*86400);omega=2*np.pi/86400;z=rate+1j*omega
    changes=[v[0] for v in offsets];moment=0j;mass=0.;days=set()
    for a,b in intervals:
        cuts=[a,*[v for v in changes if a<v<b],b]
        for start,end in zip(cuts,cuts[1:]):
            index=bisect.bisect_right(changes,start)-1
            if index<0:raise ValueError('Missing time-zone offset')
            offset=offsets[index][1];length=end-start
            weight=np.exp(rate*(end-now))
            moment+=weight*np.exp(1j*omega*((end+offset)%86400))*(-np.expm1(-z*length))/z
            mass+=weight*(-np.expm1(-rate*length))/rate
            days.update(range(int((start+offset)//86400),int((end-1e-6+offset)//86400)+1))
    return moment,float(mass),len(days)


def phase_features(sleeps,wakes,zone):
    offsets=offset_table(float(sleeps[:,0].min())-86400,float(max(wakes)),zone)
    result=np.zeros((len(wakes),6));tz=ZoneInfo(zone)
    for i,now in enumerate(wakes):
        lower,intervals=completed_intervals(sleeps,float(now),7)
        moment,mass,days=occupancy_moment(intervals,float(now),offsets)
        strength=abs(moment)/mass if mass else 0.
        # Three days and nonzero harmonic support are needed for a phase.
        valid=days>=3 and now-lower>=3*86400 and mass>0 and abs(moment)>1e-9
        phase=float(np.angle(moment)) if valid else 0.
        minute=(phase%(2*np.pi))*1440/(2*np.pi)
        local=dt.datetime.fromtimestamp(now,tz);clock=local.hour*60+local.minute
        relative=(clock-minute)%1440 if valid else float(clock)
        result[i]=[phase,strength,float(days),float(valid),mass/(7*3600),relative]
    return result


def designs(data,context,phase):
    compact=np.column_stack([data['X'],context['X'][:,5:8]])
    augmented=np.column_stack([compact,np.sin(phase[:,0]),np.cos(phase[:,0]),phase[:,1:5]])
    aligned=compact.copy();names=list(data['names']);angle=2*np.pi*phase[:,5]/1440
    for harmonic in (1,2):
        aligned[:,names.index('clockSin'+str(harmonic))]=np.sin(harmonic*angle)
        aligned[:,names.index('clockCos'+str(harmonic))]=np.cos(harmonic*angle)
    aligned=np.column_stack([aligned,phase[:,1:5]])
    return dict(matchedIntervalControl=(compact,np.zeros(len(phase))),
        phaseAugmentedInterval=(augmented,np.zeros(len(phase))),
        phaseAlignedInterval=(aligned,np.zeros(len(phase))),
        wallClockTargetControl=(compact,context['wakeClock']),
        phaseAlignedClockTarget=(aligned,phase[:,5]))


def replay(data,context,base,phase,progress=None):
    output={};diag={}
    for name,(X,anchor) in designs(data,context,phase).items():
        p=base.copy();model=None;fitted=-24;fits=learned=0
        for i in range(len(p)):
            known=eligible(data,context,i,True)
            if len(known)<40:continue
            if model is None or i-fitted>=24:
                model=WakeAnalogs('forest',5).fit(X[known],data['y'][known]+anchor[known])
                fitted=i;fits+=1
            if 360<=context['wakeClock'][i]<1260:
                p[i]=np.clip(model.predict(X[i:i+1])[0]-anchor[i],1,480);learned+=1
        output[name]=p;diag[name]=dict(refits=fits,learnedQueries=learned,featureCount=X.shape[1])
        if progress:progress(name,diag[name])
    return output,diag


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ('source','features','baseline','output'):ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--limit',type=int);args=ap.parse_args();root=Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root):ap.error('Keep private phase and forecast data outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    app=json.loads(args.baseline.read_text());assert app['audit']['sourceSHA256']==sha(args.source)
    with np.load(args.features,allow_pickle=False) as cache:data=dict(cache)
    n=len(data['y'])
    if args.limit:data={k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in data.items()}
    rows={e['index']:e for e in app['events']};context=structure(args.source,data,rows,'America/Los_Angeles')
    base=(np.array([rows[int(i)]['prediction'] for i in data['indices']])-data['wakes'])/60
    sleeps,_,_,_=load_history(args.source,'1970-01-01','America/Los_Angeles')
    phase=phase_features(sleeps,data['wakes'],'America/Los_Angeles');phasePath=args.output.with_suffix('.phase.npy');np.save(phasePath,phase)
    predictions,diag=replay(data,context,base,phase,lambda name,d:print(name,json.dumps(d),flush=True))
    difference=float(np.max(np.abs(predictions['matchedIntervalControl']-base)))
    assert difference<1e-6,('Matched app control differs',difference)
    masks=dict(planning=planning_mask(data,context),naps=planning_mask(data,context)&(context['labels']==1),bedtime=planning_mask(data,context)&(context['labels']==2),allTimers=np.ones(len(base),bool))
    result=dict(audit=dict(sourceSHA256=sha(args.source),scriptSHA256=sha(Path(__file__)),featureSHA256=sha(args.features),baselineSHA256=sha(args.baseline),phaseSHA256=sha(phasePath),maximumMatchedControlDifference=difference,
        helperSHA256={name:sha(root/'Scripts'/name) for name in ('research_sleep_predictions.py','research_sleep_neural_observer.py','research_sleep_behavior_schedule.py','research_sleep_planning.py','research_sleep_ensemble.py')},
        diagnostics=diag,training=dict(days=60,minimumResolvedPlanningLabels=40,refitQueries=24,trees=80,minimumLeaf=5),
        phase=dict(historyDays=7,occupancyHalfLifeDays=3,minimumObservedDays=3,minimumElapsedDays=3,validQueries=int(phase[:,3].sum())),
        strategy='Exact first circular moment of completed sleep union, recency weighted and split at local offset changes; frozen phase at each wake. Augmented versus phase-aligned clock inputs; interval versus next-clock target with a matched wall-clock target control.',
        limitation='An empirical schedule phase, not a measured physiological circadian phase. No current/future target clock or sleep type enters phase. Retrospective archive-selected research only.'),models={},events={})
    for name,p in dict(appV8=base,**predictions).items():
        result['models'][name]={key:metrics(data['y'],p,m) for key,m in masks.items()}
        result['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(data['indices'],data['y'],p)]
        print(name,json.dumps(result['models'][name]['planning']),flush=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')


if __name__=='__main__':main()
