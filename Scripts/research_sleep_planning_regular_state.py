#!/usr/bin/env python3
"""Forecast a regular minute sleep-state history and decode its first future start."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import time
from zoneinfo import ZoneInfo
import numpy as np
from research_sleep_predictions import load_history
from research_sleep_behavior_schedule import structure
from research_sleep_planning import planning_mask
from research_sleep_planning_recurrent_prior import validate_bootstrap
from research_sleep_ensemble import metrics

CONTEXT=2048
HORIZON=480


def state_at(sleeps,times):
    """Recorded timer union at exact points, with half-open [start,end) edges."""
    if not len(sleeps):return np.zeros(len(times),np.float32)
    started=np.searchsorted(np.sort(sleeps[:,0]),times,side='right')
    ended=np.searchsorted(np.sort(sleeps[:,1]),times,side='right')
    return (started>ended).astype(np.float32)


def histories(sleeps,wakes):
    out=np.full((len(wakes),CONTEXT),np.nan,np.float32);length=np.zeros(len(wakes),int)
    for i,now in enumerate(wakes):
        known=sleeps[(sleeps[:,1]<=now)&(sleeps[:,0]<=now)]
        if not len(known):continue
        n=min(CONTEXT,int((now-known[:,0].min())//60)+1)
        points=now+np.arange(-n+1,1)*60
        values=state_at(known,points)
        if values[-1]!=0:raise ValueError('Wake origin must be outside completed sleep timers')
        out[i,-n:]=values;length[i]=n
    return out,length


def clock_features(times,zone):
    tz=ZoneInfo(zone)
    clock=np.array([((v:=dt.datetime.fromtimestamp(t,tz)).hour*60+v.minute+v.second/60) for t in times])
    phase=clock*2*np.pi/1440
    return np.stack([np.sin(phase),np.cos(phase)]).astype(np.float32)


def request(history,length,now,conditioned,zone):
    if length<3:return None
    future=clock_features(now+np.arange(-length+1,HORIZON+1)*60,zone) if conditioned else None
    return dict(target=history[-length:][None,:].copy(),past_covariates=None,future_covariates=future)


def first_start(values):
    values=np.asarray(values,float)
    if values.shape!=(HORIZON,) or not np.isfinite(values).all():raise ValueError('Need finite minute-state trajectory')
    asleep=np.flatnonzero(values>=.5)
    return float(asleep[0]+1) if len(asleep) else float(HORIZON)


def extend_forecast(args,call,maximum_chunk=320):
    """Extend a limited-horizon native model using its own predicted states only."""
    if maximum_chunk<1:raise ValueError('Need a positive native horizon')
    original=np.asarray(args['target'],np.float32);n=original.shape[1];parts=[];generated=0
    while generated<HORIZON:
        chunk=min(maximum_chunk,HORIZON-generated)
        combined=np.concatenate([original,*[np.clip(p,0,1)[None,:] for p in parts]],axis=1)
        begin=max(0,combined.shape[1]-CONTEXT)
        future=args['future_covariates']
        current=dict(target=combined[:,begin:].copy(),past_covariates=None,
            future_covariates=future[:,begin:n+generated+chunk].copy() if future is not None else None)
        values=np.asarray(call(current,chunk),np.float32)
        if values.shape!=(chunk,) or not np.isfinite(values).all():raise RuntimeError('Invalid native state block')
        parts.append(values);generated+=chunk
    return np.concatenate(parts)


def replay(wakes,history,length,base,predict,zone,progress=None):
    out={k:base.copy() for k in ['regularState','clockConditionedState']};issued=[]
    for i,now in enumerate(wakes):
        if length[i]<3:continue
        for name,conditioned in [('regularState',False),('clockConditionedState',True)]:
            args=request(history[i],int(length[i]),now,conditioned,zone)
            out[name][i]=first_start(predict(args))
        issued.append(dict(query=i,historyMinutes=int(length[i])))
        if progress and (len(issued)%25==0 or i==len(base)-1):progress(issued[-1])
    return out,dict(issuedQueries=len(issued),contexts=issued)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for key in ['source','features','baseline','control','model','bootstrap','horizon-bootstrap','runtime','output']:ap.add_argument('--'+key,type=Path,required=True)
    ap.add_argument('--limit',type=int);a=ap.parse_args();root=Path(__file__).resolve().parents[1]
    if a.output.resolve().is_relative_to(root):ap.error('Keep private arrays/results outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();boot=json.loads(a.bootstrap.read_text());extended=json.loads(a.horizon_bootstrap.read_text())
    if not a.model.is_dir() or os.environ.get('HF_HUB_OFFLINE')!='1':ap.error('Require local model and HF_HUB_OFFLINE=1')
    validate_bootstrap(boot,a.model,a.runtime)
    if not all(extended.get(k) for k in ['passed','publicOnly','repeatedExact','crossModeIsolated','shortContextSupported']) or extended.get('baseBootstrapSHA256')!=sha(a.bootstrap) or extended.get('adapterSHA256')!=sha(Path(__file__)) or extended.get('horizon')!=HORIZON:
        raise ValueError('Need passing public-only full-horizon bootstrap')
    import importlib.metadata as md
    for name,version in boot['packageVersions'].items():
        if md.version(name)!=version:raise RuntimeError('Changed library: '+name)
    import torch
    from tirex2 import load_model,TimeseriesType
    torch.set_num_threads(2);torch.manual_seed(42);torch.use_deterministic_algorithms(True)
    model=load_model(a.model,device='cpu',use_flex_attention=False,compile=False)
    if model.training:raise RuntimeError('Model must be in evaluation mode')
    q=np.array([float(v) for v in model.quantiles]);median=int(np.argmin(abs(q-.5)))
    if abs(q[median]-.5)>1e-6:raise RuntimeError('Missing native median')
    def native(args,horizon):
        tensors={key:torch.from_numpy(v) if v is not None else None for key,v in args.items()}
        with torch.inference_mode():forecast=model.forecast([TimeseriesType(**tensors)],prediction_length=horizon,output_type='numpy')[0]
        if forecast.shape!=(1,len(q),horizon) or not np.isfinite(forecast).all():raise RuntimeError('Invalid native trajectory')
        return forecast[0,median]
    predict=lambda args:extend_forecast(args,native,int(model.future_len))
    app=json.loads(a.baseline.read_text());control=json.loads(a.control.read_text());assert app['audit']['sourceSHA256']==control['audit']['sourceSHA256']==sha(a.source)
    with np.load(a.features,allow_pickle=False) as f:d=dict(f)
    n=len(d['y'])
    if a.limit:d={key:v[:a.limit] if v.ndim and len(v)==n else v for key,v in d.items()}
    rows={e['index']:e for e in app['events']};c=structure(a.source,d,rows,'America/Los_Angeles')
    original=(np.array([rows[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60
    by={e['index']:e for e in control['events']['planningForestControl']};np.testing.assert_array_equal([by[int(i)]['actual'] for i in d['indices']],d['y'])
    base=np.array([by[int(i)]['prediction'] for i in d['indices']]);sleeps,_,_,_=load_history(a.source,'1970-01-01','America/Los_Angeles')
    history,length=histories(sleeps,d['wakes']);cache=a.output.with_suffix('.history.npz');np.savez_compressed(cache,history=history,length=length)
    # Representation-only audit. Actual future states never enter predict().
    ideal=np.array([first_start(state_at(sleeps,now+np.arange(1,HORIZON+1)*60)) for now in d['wakes']])
    np.testing.assert_allclose(ideal,np.clip(d['y'],1,HORIZON),rtol=0,atol=1e-6)
    mask=planning_mask(d,c);fixed=length<3;minimum=np.where(fixed,abs(base-d['y']),abs(np.clip(d['y'],1,HORIZON)-d['y']))
    floor=float(minimum[mask].mean());ceiling=float(100*np.mean(minimum[mask]<=30))
    if floor>2 or ceiling<98:raise RuntimeError('Fallback/output bounds prevent goal before model evaluation')
    start=time.monotonic();out,diag=replay(d['wakes'],history,length,base,predict,'America/Los_Angeles',lambda row:print(json.dumps(dict(**row,seconds=time.monotonic()-start)),flush=True))
    masks=dict(planning=mask,naps=mask&(c['labels']==1),bedtime=mask&(c['labels']==2),allTimers=np.ones(len(mask),bool))
    r=dict(audit=dict(sourceSHA256=sha(a.source),scriptSHA256=sha(Path(__file__)),historySHA256=sha(cache),
        inputsSHA256={key:sha(getattr(a,key)) for key in ['features','baseline','control','bootstrap','horizon_bootstrap']},
        helperSHA256={key:sha(root/'Scripts'/key) for key in ['research_sleep_predictions.py','research_sleep_behavior_schedule.py','research_sleep_planning_recurrent_prior.py','research_sleep_planning.py','research_sleep_ensemble.py']},
        modelFilesSHA256=boot['modelFilesSHA256'],packageVersions=boot['packageVersions'],diagnostics=diag,runtimeSeconds=time.monotonic()-start,
        strategy='TiRex-2 regular1minute recorded sleep/wake points. Last2048points end at CURRENTobservedwake(state0). Predict320then160futureminute native medians, appending only clipped predicted states for second block; known clock sin/cos optional. Decodefirstvalue>=.5,or480ifnone. FrozenmodelCPU2threads/defaultpadding/defaultdifferencing/no signflip/no compile/denseattention.',
        causalRule='Only completed sleep timers form past union. Future clock metadata is deterministic calendar information. Actual future sleep states are used ONLY in a separate representation round-trip audit, never request/predict. Query stays at recorded wake, all scoring cases retained.',
        representationRoundTripExact=True,capacity=dict(fixedPrimary=int((mask&fixed).sum()),meanFloor=floor,perfectElsewhereCoverageCeiling=ceiling,limitation='Necessary capacity bound only, not achieved model accuracy.'),
        sourceURL='https://github.com/NX-AI/tirex-2',
        limitation='Numeric state medians are not calibrated sleep probabilities; first-threshold crossing is an empirical decoder, not guaranteed median onset time. Uses timer occupancy rather than measured physiology. Regular history covers34hours8minutes; main1104cohortunchanged. Retrospective archive-selected research, not app/overnight-resettling integration.'),models={},events={})
    for name,p in dict(appV8=original,planningForestControl=base,**out).items():
        r['models'][name]={key:metrics(d['y'],p,m) for key,m in masks.items()}
        r['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(d['indices'],d['y'],p)]
        print(name,json.dumps(r['models'][name]['planning']),flush=True)
    a.output.write_text(json.dumps(r,indent=2,allow_nan=False)+'\n')


if __name__=='__main__':main()
