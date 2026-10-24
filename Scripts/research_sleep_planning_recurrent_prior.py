#!/usr/bin/env python3
"""Offline pretrained recurrent forecasting of the next distinct sleep gap."""
import argparse
import hashlib
import json
from pathlib import Path
import time
import numpy as np
from research_sleep_behavior_schedule import structure
from research_sleep_planning import eligible,planning_mask
from research_sleep_ensemble import metrics


def covariates(data,context):
    names=list(data['names'])
    chosen=['ageDays','clockSin1','clockCos1','lastDuration','lastNight','sleepMinutes24h']
    X=np.column_stack([data['X'][:,[names.index(k) for k in chosen]],context['X'][:,7]])
    if not np.isfinite(X).all():raise ValueError('Nonfinite wake-known covariates')
    return X,chosen+['completedNapEpisodesToday']


def request(data,context,X,i,conditioned):
    known=eligible(data,context,i,True)
    if len(known)<3:return None
    target=np.asarray(data['y'][known],np.float32)[None,:]
    # The only forecast-step covariates are already known at the CURRENT wake.
    future=np.column_stack([X[known].T,X[i]]) if conditioned else None
    return dict(target=target,future_covariates=None if future is None else future.astype(np.float32),past_covariates=None),known


def replay(data,context,base,X,predict,progress=None):
    out={k:base.copy() for k in ['sequenceOnly','wakeConditionedSequence']};queries=0;counts=[]
    for i in range(len(base)):
        for name,conditioned in [('sequenceOnly',False),('wakeConditionedSequence',True)]:
            item=request(data,context,X,i,conditioned)
            if item is None:continue
            args,known=item;value=float(predict(args))
            if not np.isfinite(value):raise RuntimeError('Nonfinite recurrent-prior prediction')
            out[name][i]=np.clip(value,1,480)
        if item is not None:
            queries+=1;counts.append(dict(query=i,contextLabels=len(known)))
            if progress and (queries%25==0 or i==len(base)-1):progress(counts[-1])
    return out,dict(issuedQueries=queries,contexts=counts)


def validate_bootstrap(bootstrap,model_dir,runtime_root):
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    if not all(bootstrap.get(k) for k in ['passed','publicOnly','repeatedExact','shortContextSupported','crossModeIsolated']):
        raise ValueError('Need passing public-only bootstrap')
    for name,digest in bootstrap['modelFilesSHA256'].items():
        if sha(model_dir/name)!=digest:raise ValueError('Model file changed: '+name)
    for name,digest in bootstrap['packageSourceSHA256'].items():
        if sha(runtime_root/name)!=digest:raise ValueError('Library source changed: '+name)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for key in ['source','features','baseline','control','model','bootstrap','runtime','output']:ap.add_argument('--'+key,type=Path,required=True)
    ap.add_argument('--limit',type=int);a=ap.parse_args();root=Path(__file__).resolve().parents[1]
    if a.output.resolve().is_relative_to(root):ap.error('Keep private results outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();boot=json.loads(a.bootstrap.read_text())
    if not a.model.is_dir():ap.error('Need a local offline model directory')
    validate_bootstrap(boot,a.model,a.runtime)
    import os
    if os.environ.get('HF_HUB_OFFLINE')!='1':ap.error('Set HF_HUB_OFFLINE=1 before private inference')
    import importlib.metadata as md
    for name,version in boot['packageVersions'].items():
        if md.version(name)!=version:raise RuntimeError('Library version changed: '+name)
    import torch
    from tirex2 import load_model,TimeseriesType
    torch.set_num_threads(2);torch.manual_seed(42);torch.use_deterministic_algorithms(True)
    model=load_model(a.model,device='cpu',use_flex_attention=False,compile=False)
    if model.training:raise RuntimeError('Model must be in evaluation mode')
    quantiles=np.array([float(v) for v in model.quantiles]);median=int(np.argmin(abs(quantiles-.5)))
    if abs(quantiles[median]-.5)>1e-6:raise RuntimeError('Missing native median')
    def predict(args):
        tensors={key:torch.from_numpy(v) if v is not None else None for key,v in args.items()}
        with torch.inference_mode():forecast=model.forecast([TimeseriesType(**tensors)],prediction_length=1,output_type='numpy')[0]
        if forecast.shape!=(1,len(quantiles),1) or not np.isfinite(forecast).all():raise RuntimeError('Invalid native forecast')
        return float(forecast[0,median,0])
    app=json.loads(a.baseline.read_text());control=json.loads(a.control.read_text());assert app['audit']['sourceSHA256']==control['audit']['sourceSHA256']==sha(a.source)
    with np.load(a.features,allow_pickle=False) as f:d=dict(f)
    n=len(d['y'])
    if a.limit:d={key:v[:a.limit] if v.ndim and len(v)==n else v for key,v in d.items()}
    rows={e['index']:e for e in app['events']};c=structure(a.source,d,rows,'America/Los_Angeles')
    original=(np.array([rows[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60
    by={e['index']:e for e in control['events']['planningForestControl']}
    np.testing.assert_array_equal([by[int(i)]['actual'] for i in d['indices']],d['y'])
    base=np.array([by[int(i)]['prediction'] for i in d['indices']]);X,names=covariates(d,c)
    start=time.monotonic();out,diag=replay(d,c,base,X,predict,lambda row:print(json.dumps(dict(**row,seconds=time.monotonic()-start)),flush=True))
    m=planning_mask(d,c);masks=dict(planning=m,naps=m&(c['labels']==1),bedtime=m&(c['labels']==2),allTimers=np.ones(len(m),bool))
    r=dict(audit=dict(sourceSHA256=sha(a.source),scriptSHA256=sha(Path(__file__)),
        inputsSHA256={key:sha(getattr(a,key)) for key in ['features','baseline','control','bootstrap']},
        helperSHA256={key:sha(root/'Scripts'/key) for key in ['research_sleep_behavior_schedule.py','research_sleep_planning.py','research_sleep_ensemble.py']},
        modelFilesSHA256=boot['modelFilesSHA256'],packageVersions=boot['packageVersions'],
        strategy='TiRex-2 native median: resolved planning-gap sequence alone versus seven known-wake covariates including current query.60day window,min3labels,each query separately,CPU2threads,eval/inference_mode,default2048contextpadding/defaultdifferencing,no signflip/no compile,denseattention. No private gradient training.',
        causalRule='Only END-mature previous planning labels form target history. Known covariates for those origins plus CURRENT wake occupy the forecast-step covariates. No actual future sleep/care/timing supplied. All original cases retained; matched early/all-clock forest supplies sparse fallback.',
        covariates=names,diagnostics=diag,runtimeSeconds=time.monotonic()-start,
        sourceURL='https://github.com/NX-AI/tirex-2',
        limitation='General forecasting prior adapted to event-indexed wake-gap sequences, not regularly spaced calendar observations or an infant-specific validated model. Retrospective archive-selected comparison; all-clock distinct planning is not overnight-return integration; app unchanged.'),models={},events={})
    for name,p in dict(appV8=original,planningForestControl=base,**out).items():
        r['models'][name]={key:metrics(d['y'],p,mask) for key,mask in masks.items()}
        r['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(d['indices'],d['y'],p)]
        print(name,json.dumps(r['models'][name]['planning']),flush=True)
    a.output.write_text(json.dumps(r,indent=2,allow_nan=False)+'\n')


if __name__=='__main__':main()
