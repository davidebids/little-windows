#!/usr/bin/env python3
"""Causal nearest-cycle regression with bounded dynamic time warping."""
import argparse
import hashlib
import json
from pathlib import Path
import time
import numpy as np
from research_sleep_ensemble import combine,metrics,weighted_median


def cycle_patterns(data,length):
    names=list(data['names']);X=data['X'];n=len(data['y'])
    output=np.full((n,length,4),np.nan)
    duration=X[:,names.index('lastDuration')]
    cycle=np.column_stack([np.log1p(duration)/2,np.log1p(data['y'])/2,
        X[:,names.index('clockSin1')]*.5,X[:,names.index('clockCos1')]*.5])
    for i,now in enumerate(data['wakes']):
        known=np.flatnonzero((np.arange(n)<i)&(data['available']<=now)
            &(data['wakes']>=now-7*86400))[-length:]
        if len(known)!=length:continue
        # Reset across unknown or ambiguous transitions. Their later targets
        # remain scored with the fallback; this only controls history inputs.
        if data['indices'][known[-1]]!=data['indices'][i]-1:continue
        if np.any(np.diff(data['indices'][known])!=1):continue
        output[i]=cycle[known]
    return output


def dtw_costs(query,histories,band):
    n,length,dimensions=histories.shape
    assert query.shape==(length,dimensions) and band>=0
    if band==0:
        return np.sum((histories-query)**2,axis=(1,2))
    cost=np.full((n,length+1,length+1),np.inf);cost[:,0,0]=0
    for i in range(1,length+1):
        for j in range(max(1,i-band),min(length,i+band)+1):
            local=np.sum((histories[:,i-1]-query[j-1])**2,axis=1)
            cost[:,i,j]=local+np.minimum(np.minimum(cost[:,i-1,j],cost[:,i,j-1]),cost[:,i-1,j-1])
    return cost[:,-1,-1]


def context_cost(data,index,known):
    names=list(data['names']);X=data['X'];current=X[index]
    result=np.zeros(len(known))
    for name,weight in [('clockSin1',2.),('clockCos1',2.),('lastNight',.5)]:
        k=names.index(name);result+=weight*(X[known,k]-current[k])**2
    k=names.index('lastDuration');result+=np.log((X[known,k]+10)/(current[k]+10))**2
    k=names.index('episodeSegments');result+=.25*np.log((X[known,k]+1)/(current[k]+1))**2
    k=names.index('ageDays');result+=.25*((X[known,k]-current[k])/30)**2
    return result


def neighbor_points(target,weights):
    median=float(weighted_median(target,weights))
    candidates=np.unique(np.clip(np.r_[target,target-30,target+30,median],1,480))
    errors=np.abs(candidates[:,None]-target[None,:])
    risk=(errors+30*(errors>30))@weights/weights.sum()
    chosen=min(range(len(candidates)),key=lambda j:(risk[j],abs(candidates[j]-median),candidates[j]))
    return dict(median=median,risk=float(candidates[chosen]))


def replay(data,fallback,progress=None):
    forecasts,diagnostics={},{}
    for length in [6,12]:
        patterns=cycle_patterns(data,length);valid=np.isfinite(patterns).all(axis=(1,2))
        for band in [0,2]:
            points={k:fallback.copy() for k in ['median','risk']};issued=0
            for i,now in enumerate(data['wakes']):
                known=np.flatnonzero((np.arange(len(fallback))<i)&valid
                    &(data['available']<=now)&(data['wakes']>=now-60*86400))
                if not valid[i] or len(known)<40:continue
                distance=np.sqrt(dtw_costs(patterns[i],patterns[known],band)/length+context_cost(data,i,known))
                # Explicit chronological tie-breaking preserves query-prefix behavior.
                selected=np.lexsort((known,distance))[:15]
                neighbors=known[selected]
                weights=np.exp2(-(now-data['wakes'][neighbors])/(14*86400))/(.1+distance[selected])
                estimates=neighbor_points(data['y'][neighbors],weights)
                for key,v in estimates.items():points[key][i]=np.clip(v,1,480)
                issued+=1
            name=f'cycle_l{length}_band{band}'
            forecasts.update({name+'_'+k:v for k,v in points.items()})
            diagnostics[name]=dict(issuedQueries=issued,fallbackQueries=len(fallback)-issued,
                eligiblePatterns=int(sum(valid)),length=length,band=band)
            if progress:progress(name,issued)
    return forecasts,diagnostics


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','baseline','output']:
        parser.add_argument('--'+name,type=Path,required=True)
    args=parser.parse_args()
    if args.output.resolve().is_relative_to(Path(__file__).resolve().parents[1]):
        parser.error('Keep private event forecasts outside the repository')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    data=dict(np.load(args.features,allow_pickle=False));base=json.loads(args.baseline.read_text())
    assert sha(args.source)==base['audit']['sourceSHA256']
    by={r['index']:r for r in base['events']};indices=data['indices'].astype(int).tolist();assert set(by)==set(indices)
    np.testing.assert_allclose([by[i]['actual'] for i in indices],data['available'],rtol=0,atol=1e-6)
    np.testing.assert_allclose([by[i]['wakeMinutes'] for i in indices],data['y'],rtol=0,atol=1e-6)
    fallback=(np.array([by[i]['prediction'] for i in indices])-data['wakes'])/60
    start=time.monotonic()
    def progress(name,issued):print(json.dumps(dict(configuration=name,issuedQueries=issued,seconds=time.monotonic()-start)),flush=True)
    forecasts,diag=replay(data,fallback,progress)
    result=dict(audit=dict(sourceSHA256=sha(args.source),careExposure='completed',scriptSHA256=sha(Path(__file__)),
        featureCacheSHA256=sha(args.features),baselineResultSHA256=sha(args.baseline),
        helperFilesSHA256={'research_sleep_ensemble.py':sha(Path(__file__).parent/'research_sleep_ensemble.py')},
        lookbackDays=60,patternLookbackDays=7,minimumLabels=40,neighbors=15,weightHalfLifeDays=14,
        diagnostics=diag,refitEvery=1,patternDimensions=['logPastSleepDuration/2','logResolvedGap/2','clockSin/2','clockCos/2'],
        rule='Frozen past-resolved pattern at each origin; reset across ambiguous/missing links; band0 control versus band2 DTW; known current wake anchor; median/custom risk',
        sourceURLs=['https://tslearn.readthedocs.io/en/stable/user_guide/dtw.html','https://tslearn.readthedocs.io/en/stable/gen_modules/neighbors/tslearn.neighbors.KNeighborsTimeSeriesRegressor.html']),models={},events={})
    def save(name,p):
        assert np.isfinite(p).all()
        result['models'][name]=dict(all=metrics(data['y'],p,np.ones(len(indices),dtype=bool)))
        result['events'][name]=[dict(index=i,actual=float(y),prediction=float(v)) for i,y,v in zip(indices,data['y'],p)]
        args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n');print(name,json.dumps(result['models'][name]),flush=True)
    for name,p in forecasts.items():save(name,p)
    members=np.column_stack([fallback,*forecasts.values()])
    for name,policy,cal,local in [('localCalibratedSoft','soft',True,True),('localCalibratedBest','best',True,True),
        ('localRawSoft','soft',False,True),('globalCalibratedSoft','soft',True,False),('calibratedMedian','median',True,True)]:
        save('cycleAlignment_'+name,combine(data,members,policy,cal,local))


if __name__=='__main__':main()
