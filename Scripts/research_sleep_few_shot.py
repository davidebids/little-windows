#!/usr/bin/env python3
"""Low-label prior-shrunk predictions and explicit mature-model handoffs."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from research_sleep_ensemble import combine,metrics


def replay(data,fallback,prior_masses=(2.,8.)):
    output,diagnostics={},{};names=list(data['names']);X=data['X'];phase=np.arctan2(X[:,names.index('clockSin1')],X[:,names.index('clockCos1')])
    duration=X[:,names.index('lastDuration')];night=X[:,names.index('lastNight')]
    counts=np.zeros(len(fallback),dtype=int)
    for local in [False,True]:
        for prior in prior_masses:
            if not np.isfinite(prior) or prior<=0:raise ValueError('Prior mass must be positive')
            predictions={name:fallback.copy() for name in ['offset','logRatio','directGap']}
            for i,now in enumerate(data['wakes']):
                known=np.flatnonzero((np.arange(len(fallback))<i)&(data['available']<=now)&(data['wakes']>=now-60*86400))
                counts[i]=len(known)
                if not len(known):continue
                weights=np.exp2(-(now-data['wakes'][known])/(14*86400))
                if local:
                    angle=np.abs(phase[known]-phase[i]);minutes=np.minimum(angle,2*np.pi-angle)*1440/(2*np.pi)
                    weights*=np.exp(-minutes/120)*np.exp(-np.abs(np.log((duration[known]+10)/(duration[i]+10)))/.7)
                    weights*=np.where(night[known]==night[i],1.,.2)
                den=prior+weights.sum()
                predictions['offset'][i]=np.clip(fallback[i]+np.sum(weights*(data['y'][known]-fallback[known]))/den,1,480)
                predictions['logRatio'][i]=np.clip(fallback[i]*np.exp(np.sum(weights*np.log(data['y'][known]/fallback[known]))/den),1,480)
                predictions['directGap'][i]=np.clip((prior*fallback[i]+np.sum(weights*data['y'][known]))/den,1,480)
            for kind,p in predictions.items():
                key=f'fewShot_{kind}_{"local" if local else "global"}_prior{prior:g}'
                output[key]=p;output[key+'_handoff40']=np.where(counts<40,p,fallback)
                diagnostics[key]=dict(updatedQueries=int(sum(counts>0)),coldQueries=int(sum(counts<40)),coldUpdatedQueries=int(sum((counts>0)&(counts<40))),matureQueries=int(sum(counts>=40)))
    members=np.column_stack([fallback,*output.values()])
    for name,policy,cal,local in [('localCalibratedSoft','soft',True,True),('localCalibratedBest','best',True,True),
        ('localRawSoft','soft',False,True),('globalCalibratedSoft','soft',True,False),('calibratedMedian','median',True,True)]:
        output['fewShotCombination_'+name]=combine(data,members,policy,cal,local)
    return output,diagnostics,counts


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','baseline','output']:ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--limit',type=int);ap.add_argument('--prior-masses',type=float,nargs='+',default=[2.,8.])
    args=ap.parse_args();root=Path(__file__).resolve().parents[1];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    if args.output.resolve().is_relative_to(root):ap.error('Keep private predictions outside source')
    d=dict(np.load(args.features,allow_pickle=False));n=len(d['y'])
    if args.limit:d={k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in d.items()}
    base=json.loads(args.baseline.read_text());assert base['audit']['sourceSHA256']==sha(args.source);by={r['index']:r for r in base['events']}
    np.testing.assert_allclose([by[int(i)]['actual'] for i in d['indices']],d['available'],rtol=0,atol=1e-6)
    np.testing.assert_allclose([by[int(i)]['wakeMinutes'] for i in d['indices']],d['y'],rtol=0,atol=1e-6)
    fallback=(np.array([by[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60
    forecasts,diag,counts=replay(d,fallback,args.prior_masses)
    r=dict(audit=dict(sourceSHA256=sha(args.source),featureCacheSHA256=sha(args.features),baselineResultSHA256=sha(args.baseline),scriptSHA256=sha(Path(__file__)),
        helperFilesSHA256={'research_sleep_ensemble.py':sha(root/'Scripts/research_sleep_ensemble.py')},careExposure='completed',
        lookbackDays=60,halfLifeDays=14,minimumLabels=1,priorMasses=args.prior_masses,handoffResolvedCount=40,diagnostics=diag,
        rule='Prior-shrunk offset, log-ratio or direct gap; current issued app forecast is the prior; global/local context weights; no extra correction cap; optional native handoff at forty resolved labels',
        context='Circular wake clock 120min scale, log duration .7 scale, night-type mismatch weight .2',
        caveat='The original app already uses age/history before forty forest labels and calibration after eight; this is an alternative update, not comparison with a no-learning baseline',
        limitation='Retrospective single archive; pseudo-observation shrinkage is a modeling choice, not a calibrated Bayesian interval or independent future validation'),models={},events={})
    masks={'all':np.ones(len(counts),dtype=bool),'coldUnder40':counts<40,'mature40Plus':counts>=40,'first80':np.arange(len(counts))<80}
    for name,p in forecasts.items():
        r['models'][name]={key:metrics(d['y'],p,mask) for key,mask in masks.items()}
        r['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(d['indices'],d['y'],p)]
        print(name,json.dumps(r['models'][name]),flush=True)
    args.output.write_text(json.dumps(r,indent=2,allow_nan=False)+'\n')


if __name__=='__main__':main()
