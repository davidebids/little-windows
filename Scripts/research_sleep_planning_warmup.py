#!/usr/bin/env python3
"""Personalize planning warmup while preserving the mature forest exactly."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from research_sleep_behavior_schedule import structure,weighted_median
from research_sleep_planning import eligible,planning_mask
from research_sleep_ensemble import metrics


def warmup(data,context,forest,curve):
    recent=forest.copy();curved=forest.copy();active=np.zeros(len(forest),bool)
    for i,now in enumerate(data['wakes']):
        known=eligible(data,context,i,True)
        if len(known)>=40:continue
        active[i]=True;curved[i]=curve[i]
        if len(known)<3:continue
        same=known[context['X'][known,3]==context['X'][i,3]]
        if len(same)>=3:known=same
        distance=(context['wakeClock'][known]-context['wakeClock'][i]+720)%1440-720
        weights=np.exp2(-(now-data['wakes'][known])/(7*86400))*(.1+.9*np.exp(-.5*(distance/180)**2))
        recent[i]=np.clip(weighted_median(data['y'][known],weights),1,480)
    return dict(warmupRecentMedian=recent,warmupAgeCurve=curved),active


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','baseline','planning','curves','output']:ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--limit',type=int);args=ap.parse_args();root=Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root):ap.error('Keep private results outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    app=json.loads(args.baseline.read_text());r=json.loads(args.planning.read_text());curves=json.loads(args.curves.read_text());digest=sha(args.source)
    assert app['audit']['sourceSHA256']==r['audit']['sourceSHA256']==curves['audit']['sourceSHA256']==digest
    d=dict(np.load(args.features,allow_pickle=False));n=len(d['y'])
    if args.limit:d={k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in d.items()}
    rows={v['index']:v for v in app['events']};context=structure(args.source,d,rows,'America/Los_Angeles')
    def points(report,name):
        by={v['index']:v for v in report['events'][name]}
        np.testing.assert_allclose([by[int(i)]['actual'] for i in d['indices']],d['y'],rtol=0,atol=1e-6)
        return np.array([by[int(i)]['prediction'] for i in d['indices']])
    forest=points(r,'pooled_planning');curve=points(curves,'planningCurve_pooled_direct_p0.5');predictions,active=warmup(d,context,forest,curve);cohort=planning_mask(d,context)
    masks=dict(planning=cohort,warmupPlanning=active&cohort,maturePlanning=~active&cohort,naps=cohort&(context['labels']==1),bedtime=cohort&(context['labels']==2))
    result=dict(audit=dict(sourceSHA256=digest,scriptSHA256=sha(Path(__file__)),featuresSHA256=sha(args.features),planningSHA256=sha(args.planning),curvesSHA256=sha(args.curves),
        rule='Only before40 resolved planning labels in60days: recent median after3 labels with preceding-kind match if3 available, wake clock180min kernel and half7day weights; alternatively supplied pooled strong-penalty direct age curve after20labels. Mature forest unchanged.',
        causalRule='Current and future outcomes never choose warmup versus mature; training counts use target-end maturity.',
        limitation='Retrospective selected-history warmup tests, not prospective validation.'),models={},events={})
    for name,p in {'planningForest':forest,**predictions}.items():
        result['models'][name]={key:metrics(d['y'],p,m) for key,m in masks.items()}
        result['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(d['indices'],d['y'],p)]
        print(name,json.dumps(result['models'][name]),flush=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')

if __name__=='__main__':main()
