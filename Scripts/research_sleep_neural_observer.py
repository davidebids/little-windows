#!/usr/bin/env python3
"""Research observer using completed sleep intervals, never future timer starts."""
import argparse
import datetime as dt
import hashlib
import json
import shutil
import subprocess
from pathlib import Path
from zoneinfo import ZoneInfo
import numpy as np
from research_sleep_predictions import load_history
from research_sleep_neural_dynamics import select
from research_sleep_ensemble import combine, metrics
from threadpoolctl import threadpool_limits


def parameters():
    return [[chi, mu, circ, .9] for chi in [float(np.exp(1.5)),15.,float(np.exp(3.5))]
            for mu in [6.,10.2] for circ in [-2.,-4.]]+[[45.,4.2,-3.37,.4],[float(np.exp(3.5)),7.8,-3.25,.9]]


def completed_intervals(sleeps, now, lookback_days=7):
    # Only completed records are exposed. Merge their union so overlapping
    # records cannot double-count sleep or reverse the integration clock.
    known=sleeps[(sleeps[:,1]<=now)&(sleeps[:,0]<now)]
    lower=max(now-lookback_days*86400,float(np.min(known[:,0]))) if len(known) else now
    union=[]
    for start,end in sorted(known[:,:2].tolist()):
        start=max(start,lower)
        if end<=start:continue
        if union and start<=union[-1][1]:union[-1][1]=max(union[-1][1],end)
        else:union.append([start,end])
    return lower,union


def make_input(sleeps, wakes, zone):
    assert len(wakes) and np.isfinite(sleeps).all() and np.isfinite(wakes).all()
    tz=ZoneInfo(zone);lo=float(np.min(wakes)-8*86400);hi=float(np.max(wakes)+9*3600)
    offsets=[]
    # Hourly scan includes the archive's hourly DST transitions exactly;
    # offsets are known calendar metadata, not future care observations.
    for t in range(int(lo//3600)*3600,int(hi//3600+2)*3600,3600):
        offset=dt.datetime.fromtimestamp(t,tz).utcoffset().total_seconds()/3600
        if not offsets or offset!=offsets[-1][1]:offsets.append([t/3600,offset])
    pp=parameters();lines=[f'{len(wakes)} {len(pp)} {len(offsets)}']
    lines+=[' '.join(map(repr,p)) for p in pp]
    lines+=[' '.join(map(repr,p)) for p in offsets]
    for now in wakes:
        lower,union=completed_intervals(sleeps,float(now))
        fields=[now/3600,lower/3600,len(union)]
        fields += [v/3600 for p in union for v in p]
        lines.append(' '.join(map(str,fields)))
    return '\n'.join(lines)+'\n'


def replay(data, bank, fallback):
    output,diagnostics={},{}
    with threadpool_limits(limits=2):
        for local in [False,True]:
            for penalty in [0,30]:
                name=f'observer_{"local" if local else "global"}_{"risk" if penalty else "mae"}'
                output[name],diagnostics[name]=select(data,bank,fallback,local,penalty)
        members=np.column_stack([fallback,*output.values()])
        for name,policy,cal,local in [('localCalibratedSoft','soft',True,True),('localCalibratedBest','best',True,True),
            ('localRawSoft','soft',False,True),('globalCalibratedSoft','soft',True,False),('calibratedMedian','median',True,True)]:
            output['observerCombination_'+name]=combine(data,members,policy,cal,local)
    return output,diagnostics


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for n in ['source','features','baseline','binary','output']:ap.add_argument('--'+n,type=Path,required=True)
    ap.add_argument('--limit',type=int);ap.add_argument('--forecast-seconds',type=float,default=1.)
    ap.add_argument('--forcing-seconds',type=float,default=60.)
    ap.add_argument('--cached-result',type=Path,help='Reuse native states only after input, source, binary and step hashes match')
    args=ap.parse_args()
    root=Path(__file__).resolve().parents[1];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    if args.output.resolve().is_relative_to(root):ap.error('Keep private observer states and forecasts outside source')
    # Only intervals are used here. Age remains in the separately verified
    # feature cache; the loader's discarded birth output uses a neutral epoch.
    sleeps,_,_,_=load_history(args.source,'1970-01-01','America/Los_Angeles')
    d=dict(np.load(args.features,allow_pickle=False));n=len(d['y'])
    if args.limit:d={k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in d.items()}
    base=json.loads(args.baseline.read_text());assert sha(args.source)==base['audit']['sourceSHA256']
    by={r['index']:r for r in base['events']};indices=d['indices'].astype(int).tolist()
    np.testing.assert_allclose([by[i]['wakeMinutes'] for i in indices],d['y'],rtol=0,atol=1e-6)
    np.testing.assert_allclose([by[i]['actual'] for i in indices],d['available'],rtol=0,atol=1e-6)
    fallback=(np.array([by[i]['prediction'] for i in indices])-d['wakes'])/60
    input_path=args.output.with_suffix('.input.tsv');input_path.write_text(make_input(sleeps,d['wakes'],'America/Los_Angeles'))
    raw_path=args.output.with_suffix('.states.json')
    cached_hash=None
    if args.cached_result:
        cached_hash=sha(args.cached_result);old=json.loads(args.cached_result.read_text())['audit']
        raw_cached=args.cached_result.with_suffix('.states.json')
        for key,path in [('sourceSHA256',args.source),('binarySHA256',args.binary),('inputSHA256',input_path),
                         ('statesSHA256',raw_cached),('featureCacheSHA256',args.features),('baselineResultSHA256',args.baseline),
                         ('coreSHA256',root/'Scripts/SleepReplay/NeuralSleepCore.cpp'),('observerSHA256',root/'Scripts/SleepReplay/NeuralSleepObserver.cpp')]:
            assert old[key]==sha(path),(key,'Cached native lineage differs')
        assert old['forecastSeconds']==args.forecast_seconds and old['forcingSeconds']==args.forcing_seconds
        if raw_cached.resolve()!=raw_path.resolve():shutil.copyfile(raw_cached,raw_path)
    else:
        with raw_path.open('w') as f:subprocess.run([str(args.binary),str(input_path),str(args.forecast_seconds),str(args.forcing_seconds)],stdout=f,check=True)
    raw=np.asarray(json.loads(raw_path.read_text()));assert raw.shape==(len(indices),14,5) and np.isfinite(raw).all()
    forecasts,diag=replay(d,raw[:,:,0],fallback)
    r=dict(audit=dict(sourceSHA256=sha(args.source),scriptSHA256=sha(Path(__file__)),binarySHA256=sha(args.binary),
        coreSHA256=sha(root/'Scripts/SleepReplay/NeuralSleepCore.cpp'),observerSHA256=sha(root/'Scripts/SleepReplay/NeuralSleepObserver.cpp'),
        helpersSHA256={n:sha(root/'Scripts'/n) for n in ['research_sleep_predictions.py','research_sleep_neural_dynamics.py','research_sleep_ensemble.py']},
        featureCacheSHA256=sha(args.features),baselineResultSHA256=sha(args.baseline),inputSHA256=sha(input_path),statesSHA256=sha(raw_path),careExposure='completed',
        forecastSeconds=args.forecast_seconds,forcingSeconds=args.forcing_seconds,cachedNativeResultSHA256=cached_hash,parameters=parameters(),diagnostics=diag,
        adaptation='Seven elapsed days of completed sleep union force slow states; assumed fixed firing voltages awake (1.3,-6.7), asleep (-15,1.3); reset fast states awake at query and release full equations',
        initialization=[.6,-6.7,14.6,.35,-.86,-.59],light='Source 20/1000 lux curve with observed awake gate during history; model awake gate during forecast; local DST calendar',
        limitation='New observation/reset assumptions, not measured physiology, upstream likelihood fit, or independent future validation'),models={},events={})
    for name,p in forecasts.items():
        r['models'][name]=dict(all=metrics(d['y'],p,np.ones(len(p),dtype=bool)))
        r['events'][name]=[dict(index=i,actual=float(y),prediction=float(v)) for i,y,v in zip(indices,d['y'],p)]
        print(name,json.dumps(r['models'][name]),flush=True)
    args.output.write_text(json.dumps(r,indent=2,allow_nan=False)+'\n')


if __name__=='__main__':main()
