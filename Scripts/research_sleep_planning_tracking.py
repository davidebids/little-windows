#!/usr/bin/env python3
"""Delayed-feedback expert tracking for distinct sleep planning transitions."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from research_sleep_behavior_schedule import structure
from research_sleep_planning import planning_mask
from research_sleep_ensemble import metrics


def update(weights, losses, share):
    """Multiplicative loss update followed by off-diagonal fixed sharing."""
    weights=np.asarray(weights,float);losses=np.asarray(losses,float)
    if len(weights)<2 or weights.shape!=losses.shape or not 0<=share<=1:
        raise ValueError('Invalid tracking inputs')
    if not np.isfinite(weights).all() or not np.isfinite(losses).all() or (weights<=0).any():
        raise ValueError('Tracking inputs must be finite with positive weights')
    log=np.log(weights)-losses/60.;mass=np.exp(log-log.max());mass/=mass.sum()
    mass=(1-share)*mass+share*(1-mass)/(len(mass)-1)
    # Preserve a finite log weight after arbitrarily many static updates.
    mass=np.maximum(mass,np.finfo(float).tiny)
    return mass/mass.sum()


def replay(data,context,members):
    n,k=members.shape
    if k<2 or n!=len(data['y']) or not np.isfinite(members).all():raise ValueError('Invalid expert matrix')
    cohort=planning_mask(data,context)
    clock=context['wakeClock'];day=(clock>=360)&(clock<1260)
    groups=np.where((context['X'][:,3]>0)&(clock<720),0,np.where(clock<960,1,2))
    specs={'staticJoint':(0.,False,30.),'shareJoint':(1/28,False,30.),
           'contextShareJoint':(1/28,True,30.),'contextShareAbsolute':(1/28,True,0.)}
    outputs={};diagnostics={}
    for name,(share,local,penalty) in specs.items():
        weights=np.full((4,k),1/k);counts=np.zeros(4,int);p=members[:,0].copy();used=np.zeros(n,bool);learned=0
        for i,now in enumerate(data['wakes']):
            # Delayed feedback is consumed in observed completion order, once.
            ready=np.flatnonzero((np.arange(n)<i)&cohort&~used&(context['knownAt']<=now))
            ready=ready[np.argsort(context['knownAt'][ready],kind='stable')]
            for j in ready:
                error=abs(members[j]-data['y'][j]);loss=error+penalty*(error>30)
                for group in [0,int(groups[j])+1]:
                    weights[group]=update(weights[group],loss,share);counts[group]+=1
                used[j]=True
            if not day[i] or counts[0]<8:continue
            group=int(groups[i])+1 if local and counts[int(groups[i])+1]>=8 else 0
            p[i]=np.clip(float(members[i]@weights[group]),1,480);learned+=1
        outputs[name]=p
        diagnostics[name]=dict(resolvedLabels=int(counts[0]),learnedQueries=learned,share=share,
            missPenalty=penalty,contextual=local,finalWeights=weights.tolist())
    return outputs,diagnostics


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for key in ['source','features','baseline','mixture','phase','output']:ap.add_argument('--'+key,type=Path,required=True)
    ap.add_argument('--limit',type=int);a=ap.parse_args();root=Path(__file__).resolve().parents[1]
    if a.output.resolve().is_relative_to(root):ap.error('Keep private forecasts outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    reports={k:json.loads(getattr(a,k).read_text()) for k in ['baseline','mixture','phase']}
    for r in reports.values():assert r['audit']['sourceSHA256']==sha(a.source)
    with np.load(a.features,allow_pickle=False) as f:d=dict(f)
    n=len(d['y'])
    if a.limit:d={k:v[:a.limit] if v.ndim and len(v)==n else v for k,v in d.items()}
    rows={e['index']:e for e in reports['baseline']['events']}
    np.testing.assert_allclose([rows[int(i)]['wakeMinutes'] for i in d['indices']],d['y'],rtol=0,atol=1e-6)
    base=(np.array([rows[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60
    c=structure(a.source,d,rows,'America/Los_Angeles');day=(c['wakeClock']>=360)&(c['wakeClock']<1260)
    members=[base]
    for report,name in [('mixture','bedtimeClockRisk30'),('phase','phaseAlignedInterval')]:
        by={e['index']:e for e in reports[report]['events'][name]}
        np.testing.assert_array_equal([by[int(i)]['actual'] for i in d['indices']],d['y'])
        members.append(np.where(day,[by[int(i)]['prediction'] for i in d['indices']],base))
    predictions,diagnostics=replay(d,c,np.column_stack(members));mask=planning_mask(d,c)
    masks={'planning':mask,'naps':mask&(c['labels']==1),'bedtime':mask&(c['labels']==2)}
    out=dict(audit=dict(sourceSHA256=sha(a.source),scriptSHA256=sha(Path(__file__)),
        inputsSHA256={k:sha(getattr(a,k)) for k in ['features','baseline','mixture','phase']},
        helperSHA256={k:sha(root/'Scripts'/k) for k in ['research_sleep_behavior_schedule.py','research_sleep_planning.py','research_sleep_ensemble.py']},
        strategy='Original issued app, clock-risk mixture and phase interval forecasts; delayed multiplicative loss tracking, static versus off-diagonal fixed-share1/28; learning scale60min; global versus known-wake contexts. Minimum8 resolved labels; day06..21 only.',
        causalRule='Only historical distinct-planning labels after target END update weights. Current type/gap is never routing input; each resolved outcome consumed once in completion order.',
        sourceURL='https://mwarmuth.bitbucket.io/pubs/J39.pdf',
        limitation='Independent delayed-feedback adaptation; nonconvex miss penalty does not inherit convex-loss guarantees. Archive-selected members and comparison are not prospective validation.',diagnostics=diagnostics),models={},events={})
    for name,p in {'appV8':base,**predictions}.items():
        out['models'][name]={k:metrics(d['y'],p,m) for k,m in masks.items()}
        out['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(d['indices'],d['y'],p)]
        print(name,json.dumps(out['models'][name]['planning']),flush=True)
    a.output.write_text(json.dumps(out,indent=2,allow_nan=False)+'\n')

if __name__=='__main__':main()
