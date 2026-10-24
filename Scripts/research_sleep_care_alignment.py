#!/usr/bin/env python3
"""Direct alignment of completed care-event groups at historical wake queries."""
import argparse
import hashlib
import json
import time
from pathlib import Path
import numpy as np
from research_sleep_care_signatures import read_marks,MARKS
from research_sleep_cycle_alignment import dtw_costs,context_cost,neighbor_points
from research_sleep_ensemble import combine,metrics


def care_patterns(events,wakes,length):
    patterns=np.full((len(wakes),length,len(MARKS)+3),np.nan)
    for i,now in enumerate(wakes):
        known=events[(events[:,0]<=now)&(events[:,1]<=now)&(events[:,1]>=now-48*3600)]
        ends=np.unique(known[:,1])[-length:]
        if len(ends)!=length:continue
        rows=[]
        for end in ends:
            group=known[known[:,1]==end]
            marks=np.bincount(group[:,2].astype(int),minlength=len(MARKS))/len(group)
            duration=np.mean(np.maximum(0,group[:,1]-group[:,0]))/60
            rows.append(np.r_[np.sqrt(2)*marks,np.log1p((now-end)/60)/2,np.log1p(duration)/2,np.log1p(len(group))/2])
        patterns[i]=rows
    return patterns


def replay(data,patterns,fallback,progress=None,parent=None):
    output,diagnostics={},{}
    for length,P in patterns.items():
        assert P.shape==(len(fallback),length,len(MARKS)+3)
        valid=np.isfinite(P).all(axis=(1,2))
        for band in [0,2]:
            points={k:fallback.copy() for k in ['median','risk']};issued=0
            for i,now in enumerate(data['wakes']):
                known=np.flatnonzero((np.arange(len(fallback))<i)&valid&(data['available']<=now)&(data['wakes']>=now-60*86400))
                if not valid[i] or len(known)<40:continue
                distance=np.sqrt(dtw_costs(P[i],P[known],band)/length+context_cost(data,i,known))
                selected=np.lexsort((known,distance))[:15];neighbors=known[selected]
                weights=np.exp2(-(now-data['wakes'][neighbors])/(14*86400))/(.1+distance[selected])
                estimates=neighbor_points(data['y'][neighbors],weights)
                for key,v in estimates.items():points[key][i]=np.clip(v,1,480)
                issued+=1
            name=f'careAlignment_l{length}_band{band}'
            output.update({name+'_'+key:p for key,p in points.items()})
            diagnostics[name]=dict(issuedQueries=issued,fallbackQueries=len(fallback)-issued,validPatterns=int(sum(valid)),length=length,band=band)
            if progress:progress(name,diagnostics[name])
    members=np.column_stack([fallback,*output.values()])
    for name,policy,cal,local in [('localCalibratedSoft','soft',True,True),('localCalibratedBest','best',True,True),
        ('localRawSoft','soft',False,True),('globalCalibratedSoft','soft',True,False),('calibratedMedian','median',True,True)]:
        output['careAlignmentCombination_'+name]=combine(data,members,policy,cal,local)
    if parent is not None:
        assert parent.shape==fallback.shape and np.isfinite(parent).all()
        expanded=np.column_stack([fallback,parent,members[:,1:]])
        for name,policy,cal,local in [('localCalibratedSoft','soft',True,True),('localCalibratedBest','best',True,True),
            ('localRawSoft','soft',False,True),('globalCalibratedSoft','soft',True,False),('calibratedMedian','median',True,True)]:
            output['careAlignmentExpanded_'+name]=combine(data,expanded,policy,cal,local)
    return output,diagnostics


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','baseline','output']:ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--limit',type=int);ap.add_argument('--parent',type=Path);ap.add_argument('--parent-model')
    args=ap.parse_args();root=Path(__file__).resolve().parents[1];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    if bool(args.parent)!=bool(args.parent_model):ap.error('Supply both parent and parent-model')
    if args.output.resolve().is_relative_to(root):ap.error('Keep private care patterns and forecasts outside source')
    data=dict(np.load(args.features,allow_pickle=False));n=len(data['y'])
    if args.limit:data={k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in data.items()}
    base=json.loads(args.baseline.read_text());assert base['audit']['sourceSHA256']==sha(args.source)
    by={r['index']:r for r in base['events']}
    np.testing.assert_allclose([by[int(i)]['actual'] for i in data['indices']],data['available'],rtol=0,atol=1e-6)
    np.testing.assert_allclose([by[int(i)]['wakeMinutes'] for i in data['indices']],data['y'],rtol=0,atol=1e-6)
    fallback=(np.array([by[int(i)]['prediction'] for i in data['indices']])-data['wakes'])/60
    parent=None
    if args.parent:
        previous=json.loads(args.parent.read_text());assert previous['audit']['sourceSHA256']==sha(args.source)
        pb={r['index']:r for r in previous['events'][args.parent_model]}
        np.testing.assert_allclose([pb[int(i)]['actual'] for i in data['indices']],data['y'],rtol=0,atol=1e-6)
        parent=np.array([pb[int(i)]['prediction'] for i in data['indices']])
    events,skipped=read_marks(args.source,'America/Los_Angeles');patterns={length:care_patterns(events,data['wakes'],length) for length in [8,16]}
    cache=args.output.with_suffix('.patterns.npz');np.savez_compressed(cache,**{str(k):v for k,v in patterns.items()})
    start=time.monotonic()
    def progress(name,diag):print(json.dumps(dict(candidate=name,**diag,seconds=time.monotonic()-start)),flush=True)
    forecasts,diag=replay(data,patterns,fallback,progress,parent)
    result=dict(audit=dict(sourceSHA256=sha(args.source),featureCacheSHA256=sha(args.features),baselineResultSHA256=sha(args.baseline),
        patternCacheSHA256=sha(cache),scriptSHA256=sha(Path(__file__)),careExposure='completed',
        parentResultSHA256=sha(args.parent) if args.parent else None,parentModel=args.parent_model,
        helperFilesSHA256={n:sha(root/'Scripts'/n) for n in ['research_sleep_care_signatures.py','research_sleep_cycle_alignment.py','research_sleep_ensemble.py']},
        marks=MARKS,patternLengths=[8,16],patternLookbackHours=48,lookbackDays=60,minimumLabels=40,neighbors=15,weightHalfLifeDays=14,refitEvery=1,skippedInputRecords=skipped,diagnostics=diag,
        patternDimensions='sqrt(2)*eight grouped mark fractions; log1p completion age/2; log1p mean group duration/2; log1p group size/2',
        context='Known wake clock, last sleep duration/type, resolved episode segments and age; same fixed context cost as prior sleep-cycle alignment',
        rule='Grouped simultaneous completions; fixed row alignment control versus band-two DTW; nearest fifteen past-resolved query patterns; weighted median and absolute-error-plus-miss decisions',
        limitations='Finite recent groups, fixed metric and rare types grouped Other; general alignment adaptation, not infant accuracy guarantee or independent future validation',
        sourceURLs=['https://tslearn.readthedocs.io/en/stable/user_guide/dtw.html']),models={},events={})
    for name,p in forecasts.items():
        result['models'][name]=dict(all=metrics(data['y'],p,np.ones(len(p),dtype=bool)))
        result['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(data['indices'],data['y'],p)]
        print(name,json.dumps(result['models'][name]),flush=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')


if __name__=='__main__':main()
