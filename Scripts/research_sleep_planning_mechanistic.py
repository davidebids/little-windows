#!/usr/bin/env python3
"""Fit existing mechanistic forecast banks to resolved distinct planning labels."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from research_sleep_predictions import two_process_bank,load_history
from research_sleep_neural_observer import make_input
from research_sleep_behavior_schedule import structure
from research_sleep_planning import eligible,planning_mask
from research_sleep_ensemble import metrics


def blend_planning(data,context,alternative,base,local):
    output=base.copy();learned=0;active=0
    duration=data['X'][:,list(data['names']).index('lastDuration')]
    for i,now in enumerate(data['wakes']):
        if not 360<=context['wakeClock'][i]<1260:continue
        known=eligible(data,context,i,True)
        if len(known)<40:continue
        weights=np.exp2(-(now-data['wakes'][known])/(14*86400))
        if local:
            distance=np.abs(context['wakeClock'][known]-context['wakeClock'][i])
            w=weights*np.exp(-np.minimum(distance,1440-distance)/120)
            w*=np.exp(-np.abs(np.log((duration[known]+10)/(duration[i]+10)))/.7)
            if w.sum()**2/max(1e-12,np.sum(w*w))>=8:weights=w
        delta=alternative[known]-base[known];valid=np.abs(delta)>1e-9
        if not valid.any():continue
        # |y-base-w*delta| = |delta|*|w-(y-base)/delta|.
        # Its exact constrained L1 optimum is a clipped weighted median.
        ratios=(data['y'][known][valid]-base[known][valid])/delta[valid]
        mass=weights[valid]*np.abs(delta[valid]);order=np.argsort(ratios,kind='stable')
        median=ratios[order[np.searchsorted(np.cumsum(mass[order]),mass.sum()/2)]]
        fraction=float(np.clip(median,0,1))
        output[i]=np.clip(base[i]+fraction*(alternative[i]-base[i]),1,480)
        learned+=1;active+=int(fraction>0)
    return output,dict(learnedQueries=learned,nonzeroAlternativeWeight=active)


def select_planning(data,context,bank,base,local):
    output=base.copy();choices=np.full(len(base),-1,int);effective=[]
    error=np.abs(bank.astype(float)-data['y'][:,None])
    duration=data['X'][:,list(data['names']).index('lastDuration')]
    for i,now in enumerate(data['wakes']):
        if not 360<=context['wakeClock'][i]<1260:continue
        known=eligible(data,context,i,True)
        if len(known)<40:continue
        weights=np.exp2(-(now-data['wakes'][known])/(14*86400))
        if local:
            difference=np.abs(context['wakeClock'][known]-context['wakeClock'][i])
            w=weights*np.exp(-np.minimum(difference,1440-difference)/120)
            w*=np.exp(-np.abs(np.log((duration[known]+10)/(duration[i]+10)))/.7)
            ess=w.sum()**2/max(1e-12,np.sum(w*w))
            if ess>=8:weights=w
        score=weights@error[known]/weights.sum()
        choices[i]=int(np.argmin(score));output[i]=bank[i,choices[i]]
        effective.append(float(weights.sum()**2/np.sum(weights*weights)))
    return output,dict(learnedQueries=int((choices>=0).sum()),selectedMembers=len(set(choices[choices>=0].tolist())),
        minimumEffectiveSampleSize=min(effective) if effective else None)


def replay(data,context,banks,base,progress=None):
    outputs={};diagnostics={}
    for family,bank in banks.items():
        if bank.shape[0]!=len(base) or not np.isfinite(bank).all():raise ValueError('Invalid bank')
        for local in (False,True):
            name=family+('_local' if local else '_global')
            outputs[name],diagnostics[name]=select_planning(data,context,bank,base,local)
            if progress:progress(name,diagnostics[name])
    if 'twoProcess_local' in outputs:
        for local in (False,True):
            name='twoProcess_blend'+('_local' if local else '_global')
            outputs[name],diagnostics[name]=blend_planning(data,context,outputs['twoProcess_local'],base,local)
            if progress:progress(name,diagnostics[name])
    return outputs,diagnostics


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ('source','features','complete','baseline','observer','output'):ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--limit',type=int);args=ap.parse_args();root=Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root):ap.error('Keep private predictions outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    data=dict(np.load(args.features,allow_pickle=False));full=dict(np.load(args.complete,allow_pickle=False))
    for name in ('indices','y','wakes','available'):np.testing.assert_array_equal(data[name],full[name])
    app=json.loads(args.baseline.read_text());old=json.loads(args.observer.read_text());audit=old['audit']
    assert audit['sourceSHA256']==app['audit']['sourceSHA256']==sha(args.source)
    assert audit['featureCacheSHA256']==sha(args.features)
    for name,key in [('NeuralSleepCore.cpp','coreSHA256'),('NeuralSleepObserver.cpp','observerSHA256')]:
        assert audit[key]==sha(root/'Scripts/SleepReplay'/name)
    for name,digest in audit['helpersSHA256'].items():assert digest==sha(root/'Scripts'/name)
    statePath=args.observer.with_suffix('.states.json');assert audit['statesSHA256']==sha(statePath)
    inputPath=args.observer.with_suffix('.input.tsv');assert audit['inputSHA256']==sha(inputPath)
    sleeps,_,_,_=load_history(args.source,'1970-01-01','America/Los_Angeles')
    generated=make_input(sleeps,data['wakes'],'America/Los_Angeles')
    assert hashlib.sha256(generated.encode()).hexdigest()==audit['inputSHA256']
    raw=np.asarray(json.loads(statePath.read_text()));assert raw.shape==(len(data['y']),14,5)
    n=len(data['y'])
    if args.limit:
        data={k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in data.items()}
        full={k:(v[:args.limit] if isinstance(v,np.ndarray) and v.ndim and len(v)==n else v) for k,v in full.items()}
        raw=raw[:args.limit]
    rows={e['index']:e for e in app['events']};context=structure(args.source,data,rows,'America/Los_Angeles')
    base=(np.array([rows[int(i)]['prediction'] for i in data['indices']])-data['wakes'])/60
    full['names']=list(full['names'])
    banks=dict(twoProcess=two_process_bank(full),sixStateObserver=raw[:,:,0])
    forecasts,diag=replay(data,context,banks,base,lambda name,d:print(name,json.dumps(d),flush=True))
    masks=dict(planning=planning_mask(data,context),naps=planning_mask(data,context)&(context['labels']==1),bedtime=planning_mask(data,context)&(context['labels']==2),allTimers=np.ones(len(base),bool))
    result=dict(audit=dict(sourceSHA256=sha(args.source),scriptSHA256=sha(Path(__file__)),featureSHA256=sha(args.features),completeSHA256=sha(args.complete),baselineSHA256=sha(args.baseline),observerSHA256=sha(args.observer),statesSHA256=sha(statePath),
        helperSHA256={name:sha(root/'Scripts'/name) for name in ('research_sleep_predictions.py','research_sleep_neural_observer.py','research_sleep_neural_dynamics.py','research_sleep_behavior_schedule.py','research_sleep_planning.py','research_sleep_ensemble.py')},
        diagnostics=diag,bankSizes={name:bank.shape[1] for name,bank in banks.items()},
        training=dict(days=60,halfLifeDays=14,minimumResolvedPlanningLabels=40,querySpecificSelection=True),
        strategy='Original equations and completed-history states, but member choice is fitted only to past resolved distinct nap/bedtime errors; global or wake-clock/duration-local absolute loss. Two additional blends choose an L1-optimal convex weight on the originally issued local two-process points and app points using resolved past errors only. Preserve app sparse-history and overnight points.',
        limitation='Fixed latent initialization, assumed light and observation rule; not measured physiology or the paper weekly fitting procedure. Retrospective archive-selected research only.'),models={},events={})
    for name,p in dict(appV8=base,**forecasts).items():
        result['models'][name]={key:metrics(data['y'],p,m) for key,m in masks.items()}
        result['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(data['indices'],data['y'],p)]
        print(name,json.dumps(result['models'][name]['planning']),flush=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')


if __name__=='__main__':main()
