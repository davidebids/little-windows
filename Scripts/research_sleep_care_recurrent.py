#!/usr/bin/env python3
"""Causal small recurrent models of completed care groups, with matched controls."""
import argparse
import hashlib
import json
import time
from pathlib import Path
import numpy as np
import torch
from torch import nn
from threadpoolctl import threadpool_limits
from research_sleep_care_alignment import care_patterns
from research_sleep_care_signatures import read_marks
from research_sleep_ensemble import combine,metrics,weighted_median


def sequence_view(sequence,kind):
    if kind=='context':return np.zeros_like(sequence)
    if kind=='pooled':return np.repeat(np.mean(sequence,axis=1,keepdims=True),sequence.shape[1],axis=1)
    if kind=='ordered':return sequence.copy()
    raise ValueError(kind)


def fit_scale(x,weights):
    finite=np.isfinite(x);den=np.sum(finite*weights[:,None],axis=0)
    mean=np.divide(np.sum(np.where(finite,x,0)*weights[:,None],axis=0),den,out=np.zeros(x.shape[1]),where=den>0)
    filled=np.where(finite,x,mean)
    scale=np.maximum(.05,np.sqrt(np.average((filled-mean)**2,axis=0,weights=weights)))
    return mean,scale


def normalized(x,scale):
    mean,std=scale
    return np.clip((np.where(np.isfinite(x),x,mean)-mean)/std,-10,10).astype(np.float32)


class CareNetwork(nn.Module):
    def __init__(self,sequence_width,context_width):
        super().__init__()
        self.gru=nn.GRU(sequence_width,16,batch_first=True)
        self.head=nn.Sequential(nn.Linear(16+context_width,16),nn.Tanh(),nn.Linear(16,1))

    def forward(self,sequence,context):
        _,state=self.gru(sequence)
        return self.head(torch.cat([state[-1],context],dim=1)).squeeze(1)


def fit_model(sequence,context,target,weights,epochs):
    torch.manual_seed(42)
    # Context missingness indicators are inputs, with all statistics fitted
    # only on the resolved training rows of this particular refit.
    context=np.column_stack([context,np.isfinite(context).astype(float)])
    cs=fit_scale(context,weights)
    flat=sequence.reshape(-1,sequence.shape[-1]);sw=np.repeat(weights,sequence.shape[1])
    ss=fit_scale(flat,sw)
    center=float(weighted_median(target,weights))
    x=torch.from_numpy(normalized(sequence,ss));c=torch.from_numpy(normalized(context,cs))
    y=torch.from_numpy(((target-center)/60).astype(np.float32));w=torch.from_numpy((weights/weights.sum()).astype(np.float32))
    model=CareNetwork(sequence.shape[-1],context.shape[1]);optimizer=torch.optim.AdamW(model.parameters(),lr=.01,weight_decay=.01)
    model.train()
    for _ in range(epochs):
        optimizer.zero_grad(set_to_none=True);prediction=model(x,c)
        loss=torch.sum(torch.abs(prediction-y)*w)
        if not torch.isfinite(loss):raise RuntimeError('Nonfinite recurrent training loss')
        loss.backward();nn.utils.clip_grad_norm_(model.parameters(),1.);optimizer.step()
    model.eval()
    return model,ss,cs,center,float(loss.detach()),sum(p.numel() for p in model.parameters())


def predict_model(fit,sequence,context):
    model,ss,cs,center,_,_=fit
    context=np.column_stack([context,np.isfinite(context).astype(float)])
    with torch.inference_mode():
        value=model(torch.from_numpy(normalized(sequence,ss)),torch.from_numpy(normalized(context,cs))).numpy()
    return value.astype(float)*60+center


def replay(data,sequence,fallback,progress=None,epochs=64,minimum_labels=80,refit_every=48,fit_function=None):
    torch.set_num_threads(2);torch.use_deterministic_algorithms(True)
    valid=np.isfinite(sequence).all(axis=(1,2));context=np.column_stack([data['X'],fallback]);outputs,diagnostics={},{}
    with threadpool_limits(limits=2):
        for kind in ['context','pooled','ordered']:
            P=sequence_view(sequence,kind)
            for residual in [False,True]:
                key=f'careRecurrent_{kind}_{"residual" if residual else "direct"}'
                pred=fallback.copy();fit=None;last=-refit_every;fits=0;learned=0;losses=[]
                for i,now in enumerate(data['wakes']):
                    known=np.flatnonzero((np.arange(len(pred))<i)&valid&(data['available']<=now)&(data['wakes']>=now-60*86400))
                    if not valid[i] or len(known)<minimum_labels:continue
                    if fit is None or i-last>=refit_every:
                        weights=np.exp2(-(now-data['wakes'][known])/(14*86400))
                        target=data['y'][known]-(fallback[known] if residual else 0)
                        fit=(fit_function or fit_model)(P[known],context[known],target,weights,epochs);last=i;fits+=1;losses.append(fit[-2])
                    value=predict_model(fit,P[i:i+1],context[i:i+1])[0]+(fallback[i] if residual else 0)
                    if not np.isfinite(value):raise RuntimeError('Nonfinite recurrent forecast')
                    pred[i]=np.clip(value,1,480);learned+=1
                outputs[key]=pred;diagnostics[key]=dict(refits=fits,learnedQueries=learned,fallbackQueries=len(pred)-learned,validPatterns=int(sum(valid)),
                    parameters=fit[-1] if fit else None,meanFinalTrainingLoss=float(np.mean(losses)) if losses else None)
                if progress:progress(key,diagnostics[key])
        members=np.column_stack([fallback,*outputs.values()])
        for name,policy,cal,local in [('localCalibratedSoft','soft',True,True),('localCalibratedBest','best',True,True),
            ('localRawSoft','soft',False,True),('globalCalibratedSoft','soft',True,False),('calibratedMedian','median',True,True)]:
            outputs['careRecurrentCombination_'+name]=combine(data,members,policy,cal,local)
    return outputs,diagnostics


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','baseline','output']:ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--limit',type=int);ap.add_argument('--epochs',type=int,default=64)
    args=ap.parse_args();root=Path(__file__).resolve().parents[1];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    if args.output.resolve().is_relative_to(root):ap.error('Keep private care groups and forecasts outside source')
    d=dict(np.load(args.features,allow_pickle=False));n=len(d['y'])
    if args.limit:d={k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in d.items()}
    base=json.loads(args.baseline.read_text());assert base['audit']['sourceSHA256']==sha(args.source)
    by={r['index']:r for r in base['events']}
    np.testing.assert_allclose([by[int(i)]['actual'] for i in d['indices']],d['available'],rtol=0,atol=1e-6)
    np.testing.assert_allclose([by[int(i)]['wakeMinutes'] for i in d['indices']],d['y'],rtol=0,atol=1e-6)
    fallback=(np.array([by[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60
    events,skipped=read_marks(args.source,'America/Los_Angeles');P=care_patterns(events,d['wakes'],16)
    cache=args.output.with_suffix('.patterns.npy');np.save(cache,P,allow_pickle=False)
    start=time.monotonic()
    def progress(name,diag):print(json.dumps(dict(candidate=name,**diag,seconds=time.monotonic()-start)),flush=True)
    predictions,diag=replay(d,P,fallback,progress,epochs=args.epochs)
    r=dict(audit=dict(sourceSHA256=sha(args.source),featureCacheSHA256=sha(args.features),baselineResultSHA256=sha(args.baseline),patternCacheSHA256=sha(cache),
        scriptSHA256=sha(Path(__file__)),helperFilesSHA256={n:sha(root/'Scripts'/n) for n in ['research_sleep_care_alignment.py','research_sleep_care_signatures.py','research_sleep_cycle_alignment.py','research_sleep_ensemble.py']},
        careExposure='completed',torchVersion=torch.__version__,numpyVersion=np.__version__,epochs=args.epochs,lookbackDays=60,halfLifeDays=14,minimumLabels=80,refitEvery=48,patternLength=16,
        optimizer=dict(kind='AdamW',learningRate=.01,weightDecay=.01,gradientNormCap=1.),seed=42,deterministicAlgorithms=True,device='cpu',threads=2,diagnostics=diag,skippedInputRecords=skipped,
        architecture='One GRU layer width16; concatenated standardized known context/missingness; tanh decoder width16; direct/residual normalized weighted L1',
        controls='Same architecture with zero sequence, repeated mean sequence, or actual ordered sequence; same cold initialization and fixed optimization budget',
        normalization='Training-only weighted means/scales; .05 scale floor; input z clipped to +-10; weighted target median and fixed60minute output scale',
        limitations='Fixed small recurrent architecture and optimization budget; general sequence adaptation, not infant accuracy guarantee or independent future validation',
        sourceURLs=['https://docs.pytorch.org/docs/2.14/generated/torch.nn.GRU.html']),models={},events={})
    for name,p in predictions.items():
        r['models'][name]=dict(all=metrics(d['y'],p,np.ones(len(p),dtype=bool)))
        r['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(d['indices'],d['y'],p)]
        print(name,json.dumps(r['models'][name]),flush=True)
    args.output.write_text(json.dumps(r,indent=2,allow_nan=False)+'\n')


if __name__=='__main__':main()
