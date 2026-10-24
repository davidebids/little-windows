#!/usr/bin/env python3
"""Causal nap/bedtime distribution mixtures, retaining uncertainty in type."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from sklearn.ensemble import ExtraTreesClassifier
from research_sleep_behavior_schedule import structure,weighted_median
from research_sleep_planning import eligible,planning_mask
from research_sleep_predictions import WakeAnalogs
from research_sleep_ensemble import metrics


def distribution(model,query):
    values=model.imputer.transform(query)
    leaf=model.forest.apply(values)[0];same=model.leaves==leaf
    weights=np.sum(same/np.maximum(np.sum(same,axis=0),1),axis=1)
    selected=weights>0;weights=weights[selected]
    return model.y[selected],weights/weights.sum()


def mixture_point(parts,miss_penalty=0.):
    values=[];weights=[]
    for samples,mass,probability in parts:
        if probability<=0:continue
        values.extend(samples);weights.extend(mass*probability)
    if not len(values) or sum(weights)<=0:raise ValueError('Mixture has no positive mass')
    values=np.asarray(values);weights=np.asarray(weights);median=weighted_median(values,weights)
    if miss_penalty==0:return float(np.clip(median,1,480))
    if not np.isfinite(miss_penalty) or miss_penalty<0:raise ValueError('Invalid miss penalty')
    # Absolute loss is linear between samples. Coverage changes only at y +/-30.
    # Thus every optimum in [1,480] occurs among these endpoints or sample knots.
    order=np.argsort(values,kind='stable');values=values[order];weights=weights[order]
    cumulative=np.r_[0.,np.cumsum(weights)];weighted=np.r_[0.,np.cumsum(weights*values)]
    candidates=np.unique(np.clip(np.r_[values,values-30,values+30,1.,480.],1,480))
    idx=np.searchsorted(values,candidates,side='right')
    absolute=(candidates*cumulative[idx]-weighted[idx]+weighted[-1]-weighted[idx]-candidates*(cumulative[-1]-cumulative[idx]))/cumulative[-1]
    left=np.searchsorted(values,candidates-30-1e-9,side='left');right=np.searchsorted(values,candidates+30+1e-9,side='right')
    covered=(cumulative[right]-cumulative[left])/cumulative[-1]
    risk=absolute+miss_penalty*(1-covered)
    choice=np.lexsort((candidates,abs(candidates-median),risk))[0]
    return float(candidates[choice])


def replay(data,context,fallback,progress=None):
    X=np.column_stack([data['X'],context['X'][:,5:8]]);C=context['X'];labels=context['labels'];n=len(fallback)
    predictions={name:fallback.copy() for name in ['hardNapBedtimeControl','gapDistributionMixture','bedtimeClockDistributionMixture']}
    for kind in ['gap','bedtimeClock']:
        for penalty in [30.,90.]:predictions[f'{kind}Risk{penalty:g}']=fallback.copy()
    fitted=-24;gate=None;fits=learned=0
    for i in range(n):
        known=eligible(data,context,i,True)
        if len(known)>=40 and i-fitted>=24:
            gate=ExtraTreesClassifier(n_estimators=80,min_samples_leaf=5,max_features=.8,random_state=42,n_jobs=1).fit(C[known],labels[known])
            nap=known[labels[known]==1];bed=known[labels[known]==2]
            nm=WakeAnalogs('forest',5).fit(X[nap],data['y'][nap]) if len(nap)>=20 else None
            bg=WakeAnalogs('forest',5).fit(X[bed],data['y'][bed]) if len(bed)>=20 else None
            clock=(context['targetClock'][bed]-1080+720)%1440-720+1080
            bc=WakeAnalogs('forest',5).fit(X[bed],clock) if len(bed)>=20 else None
            fitted=i;fits+=1
        if gate is None:continue
        probabilities=dict(zip(gate.classes_,gate.predict_proba(C[i:i+1])[0]));gap_parts=[];clock_parts=[];points=[];masses=[]
        if nm is not None:
            vals,weights=distribution(nm,X[i:i+1]);gap_parts.append((vals,weights,probabilities.get(1,0)));clock_parts.append((vals,weights,probabilities.get(1,0)))
            points.append(float(nm.predict(X[i:i+1])[0]));masses.append(probabilities.get(1,0))
        if bg is not None:
            vals,weights=distribution(bg,X[i:i+1]);gap_parts.append((vals,weights,probabilities.get(2,0)))
            clocks,weights=distribution(bc,X[i:i+1]);gaps=(clocks-context['wakeClock'][i])%1440;clock_parts.append((gaps,weights,probabilities.get(2,0)))
            points.append((float(bc.predict(X[i:i+1])[0])-context['wakeClock'][i])%1440);masses.append(probabilities.get(2,0))
        if sum(masses)<=0:continue
        predictions['hardNapBedtimeControl'][i]=np.clip(weighted_median(points,masses),1,480)
        predictions['gapDistributionMixture'][i]=mixture_point(gap_parts)
        predictions['bedtimeClockDistributionMixture'][i]=mixture_point(clock_parts)
        for kind,parts in [('gap',gap_parts),('bedtimeClock',clock_parts)]:
            for penalty in [30.,90.]:predictions[f'{kind}Risk{penalty:g}'][i]=mixture_point(parts,penalty)
        learned+=1
    diag=dict(refits=fits,learnedQueries=learned,fallbackQueries=n-learned)
    if progress:progress(diag)
    return predictions,diag


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for key in ['source','features','baseline','planning','warmup','output']:ap.add_argument('--'+key,type=Path,required=True)
    ap.add_argument('--limit',type=int);args=ap.parse_args();root=Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root):ap.error('Keep private results outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    app=json.loads(args.baseline.read_text());prior=json.loads(args.planning.read_text());warm=json.loads(args.warmup.read_text());digest=sha(args.source)
    assert app['audit']['sourceSHA256']==prior['audit']['sourceSHA256']==warm['audit']['sourceSHA256']==digest
    d=dict(np.load(args.features,allow_pickle=False));n=len(d['y'])
    if args.limit:d={k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in d.items()}
    rows={r['index']:r for r in app['events']};context=structure(args.source,d,rows,'America/Los_Angeles')
    fallback=(np.array([rows[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60
    issued={r['index']:r for r in warm['events']['warmupAgeCurve']};cold=np.array([len(eligible(d,context,i,True))<40 for i in range(len(fallback))])
    predictions,diag=replay(d,context,fallback,lambda diag:print(json.dumps(diag),flush=True))
    # Freeze the shared warmup control across both mature estimators.
    for name in predictions:
        if name=='hardNapBedtimeControl':continue
        predictions[name][cold]=np.array([issued[int(i)]['prediction'] for i in d['indices']])[cold]
    control={r['index']:r for r in prior['events']['napInterval_bedtimeClock']}
    np.testing.assert_array_equal(predictions['hardNapBedtimeControl'],[control[int(i)]['prediction'] for i in d['indices']])
    mask=planning_mask(d,context);masks=dict(planning=mask,naps=mask&(context['labels']==1),bedtime=mask&(context['labels']==2),maturePlanning=mask&~cold,allTimers=np.ones(len(mask),bool))
    result=dict(audit=dict(sourceSHA256=digest,scriptSHA256=sha(Path(__file__)),featureSHA256=sha(args.features),baselineSHA256=sha(args.baseline),planningSHA256=sha(args.planning),warmupSHA256=sha(args.warmup),
        strategy='Wake-known two-class forest probabilities times class-conditional forest neighborhood mass, followed by the mixture median or minimum expected absolute loss plus fixed30/90-minute penalty for missing within30. Nap gaps plus bedtime gaps or bedtime clocks.',
        training=dict(historyDays=60,minimumLabels=40,minimumPerExpert=20,refitEveryQueries=24,trees=80,minimumLeaf=5),
        causalRule='Only resolved planning labels at target sleep end; current outcome type never gates forecast. Shared originally issued age-curve warmup retained.',
        limitation='Retrospective archive-selected research, not prospective validation.',controlExactlyReproduced=True,diagnostics=diag,
        helperFilesSHA256={name:sha(root/'Scripts'/name) for name in ['research_sleep_behavior_schedule.py','research_sleep_planning.py','research_sleep_predictions.py','research_sleep_ensemble.py']}),models={},events={})
    for name,p in predictions.items():
        result['models'][name]={key:metrics(d['y'],p,m) for key,m in masks.items()}
        result['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(d['indices'],d['y'],p)]
        print(name,json.dumps(result['models'][name]['planning']),flush=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')

if __name__=='__main__':main()
