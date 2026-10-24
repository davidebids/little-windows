#!/usr/bin/env python3
"""Past-only next-care pretraining as input to the existing planning forest."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import time
import numpy as np
import torch
from torch import nn
from threadpoolctl import threadpool_limits
from research_sleep_care_alignment import care_patterns
from research_sleep_care_signatures import read_marks,MARKS
from research_sleep_care_recurrent import fit_scale,normalized
from research_sleep_predictions import WakeAnalogs
from research_sleep_behavior_schedule import structure
from research_sleep_planning import eligible,planning_mask
from research_sleep_ensemble import metrics


def auxiliary_examples(events):
    ends=np.unique(events[:,1]);patterns=care_patterns(events,ends,16)
    marks=np.array([np.bincount(events[events[:,1]==end,2].astype(int),minlength=len(MARKS)) for end in ends],float)
    marks/=marks.sum(axis=1,keepdims=True)
    return dict(P=patterns[:-1],origins=ends[:-1],available=ends[1:],marks=marks[1:],gap=np.log1p(np.diff(ends)/60)/4)


def auxiliary_known(aux,now):
    return np.flatnonzero((aux['available']<=now)&(aux['origins']>=now-60*86400)&np.isfinite(aux['P']).all(axis=(1,2)))


class CarePredictor(nn.Module):
    def __init__(self):
        super().__init__();self.gru=nn.GRU(len(MARKS)+3,16,batch_first=True)
        self.mark=nn.Linear(16,len(MARKS));self.gap=nn.Linear(16,1)
    def forward(self,P):
        _,h=self.gru(P);z=h[-1]
        return self.mark(z),self.gap(z).squeeze(1)


def train_encoders(aux,known,now,epochs=8,batch_size=128):
    if not len(known):raise ValueError('No resolved auxiliary examples')
    weights=np.ones(len(known),float)
    P=aux['P'][known];scale=fit_scale(P.reshape(-1,P.shape[-1]),np.repeat(weights,P.shape[1]))
    x=torch.from_numpy(normalized(P,scale));weights=torch.from_numpy((weights/weights.mean()).astype(np.float32))
    marks=aux['marks'][known].astype(np.float32);gap=aux['gap'][known].astype(np.float32)
    if not np.isfinite(marks).all() or not np.isfinite(gap).all() or not np.allclose(marks.sum(1),1):raise ValueError('Invalid auxiliary targets')
    torch.manual_seed(42);initial=CarePredictor()
    encoders={'random':(copy.deepcopy(initial.gru).eval(),scale)};diagnostics={}
    shuffled=np.random.default_rng(31415).permutation(len(known))
    for mode in ['shuffled','predictive']:
        model=copy.deepcopy(initial);model.train();optimizer=torch.optim.AdamW(model.parameters(),lr=.01,weight_decay=.01)
        permutation=shuffled if mode=='shuffled' else np.arange(len(known))
        ym=torch.from_numpy(marks[permutation]);yg=torch.from_numpy(gap[permutation])
        rng=np.random.default_rng(42);updates=0
        for _ in range(epochs):
            order=rng.permutation(len(known))
            for start in range(0,len(order),batch_size):
                j=order[start:start+batch_size];optimizer.zero_grad(set_to_none=True)
                logits,delta=model(x[j]);per_row=-(ym[j]*torch.log_softmax(logits,dim=1)).sum(1)+abs(delta-yg[j])
                loss=(per_row*weights[j]).mean()
                if not torch.isfinite(loss):raise RuntimeError('Nonfinite auxiliary loss')
                loss.backward();nn.utils.clip_grad_norm_(model.parameters(),1.);optimizer.step();updates+=1
        model.eval();encoders[mode]=(copy.deepcopy(model.gru).eval(),scale)
        with torch.inference_mode():
            logits,delta=model(x)
            fit_loss=(-(ym*torch.log_softmax(logits,dim=1)).sum(1)+abs(delta-yg)).numpy()
        diagnostics[mode]=dict(updates=updates,trainingLoss=float(np.average(fit_loss,weights=weights.numpy())))
    return encoders,diagnostics


def encode(encoder,P):
    model,scale=encoder;valid=np.isfinite(P).all(axis=(1,2));out=np.full((len(P),16),np.nan)
    if valid.any():
        with torch.inference_mode():
            _,h=model(torch.from_numpy(normalized(P[valid],scale)));out[valid]=h[-1].numpy()
    return out


def replay(data,context,base,patterns,aux,progress=None,epochs=8,trainer=train_encoders,factory=None,minimum_labels=40,daytime_only=True,early_refits=False):
    torch.set_num_threads(2);torch.use_deterministic_algorithms(True)
    if factory is None:factory=lambda:WakeAnalogs('forest',5)
    C=np.column_stack([data['X'],context['X'][:,5:8]])
    outputs={k:base.copy() for k in ['planningForestControl','randomCareEncoder','shuffledCarePretraining','predictiveCarePretraining']}
    names={'random':'randomCareEncoder','shuffled':'shuffledCarePretraining','predictive':'predictiveCarePretraining'}
    models={};encoders={};fitted=-24;fit_labels=0;fits=learned=0;diag=[]
    with threadpool_limits(limits=2):
        for i,now in enumerate(data['wakes']):
            known=eligible(data,context,i,True)
            if len(known)<minimum_labels:continue
            interval=1 if early_refits and len(known)<40 else 24
            if not models or i-fitted>=interval or (early_refits and fit_labels<40<=len(known)):
                training=auxiliary_known(aux,now)
                if not len(training):raise ValueError('No completed care examples at refit')
                encoders,info=trainer(aux,training,now,epochs)
                models={'control':factory().fit(C[known],data['y'][known])}
                for mode,encoder in encoders.items():
                    Z=encode(encoder,patterns[known]);models[mode]=factory().fit(np.column_stack([C[known],Z]),data['y'][known])
                fitted=i;fit_labels=len(known);fits+=1;diag.append(info)
                if progress:progress(dict(refits=fits,query=i,planningLabels=len(known),auxiliaryLabels=len(training)))
            if daytime_only and not 360<=context['wakeClock'][i]<1260:continue
            outputs['planningForestControl'][i]=np.clip(float(models['control'].predict(C[i:i+1])[0]),1,480)
            if np.isfinite(patterns[i]).all():
                for mode,encoder in encoders.items():
                    Z=encode(encoder,patterns[i:i+1]);p=float(models[mode].predict(np.column_stack([C[i:i+1],Z]))[0])
                    if not np.isfinite(p):raise RuntimeError('Nonfinite pretrained-care forecast')
                    outputs[names[mode]][i]=np.clip(p,1,480)
            learned+=1
    return outputs,dict(refits=fits,eligibleQueries=learned,validQueryPatterns=int(np.isfinite(patterns).all(axis=(1,2)).sum()),
        auxiliaryUpdates={mode:sum(d[mode]['updates'] for d in diag) for mode in ['shuffled','predictive']})


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','baseline','output']:ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--limit',type=int);a=ap.parse_args();root=Path(__file__).resolve().parents[1]
    if a.output.resolve().is_relative_to(root):ap.error('Keep private representations and results outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    app=json.loads(a.baseline.read_text());assert app['audit']['sourceSHA256']==sha(a.source)
    with np.load(a.features,allow_pickle=False) as file:d=dict(file)
    n=len(d['y'])
    if a.limit:d={k:v[:a.limit] if v.ndim and len(v)==n else v for k,v in d.items()}
    rows={v['index']:v for v in app['events']}
    np.testing.assert_allclose([rows[int(i)]['wakeMinutes'] for i in d['indices']],d['y'],rtol=0,atol=1e-6)
    c=structure(a.source,d,rows,'America/Los_Angeles');base=(np.array([rows[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60
    events,skipped=read_marks(a.source,'America/Los_Angeles');P=care_patterns(events,d['wakes'],16);aux=auxiliary_examples(events)
    cache=a.output.with_suffix('.patterns.npy');np.save(cache,P,allow_pickle=False);auxcache=a.output.with_suffix('.aux.npz');np.savez_compressed(auxcache,**aux)
    start=time.monotonic();p,diag=replay(d,c,base,P,aux,lambda x:print(json.dumps(dict(**x,seconds=time.monotonic()-start)),flush=True),minimum_labels=3,daytime_only=False,early_refits=True)
    mature=np.array([len(eligible(d,c,i,True))>=40 for i in range(len(base))]);day=(c['wakeClock']>=360)&(c['wakeClock']<1260)
    np.testing.assert_allclose(p['planningForestControl'][mature&day],base[mature&day],rtol=0,atol=1e-6)
    mask=planning_mask(d,c);masks={'planning':mask,'naps':mask&(c['labels']==1),'bedtime':mask&(c['labels']==2),'allTimers':np.ones(len(mask),bool),'nonPlanningNight':(~mask)&(c['X'][:,3]>0)}
    result=dict(audit=dict(sourceSHA256=sha(a.source),scriptSHA256=sha(Path(__file__)),featureSHA256=sha(a.features),baselineSHA256=sha(a.baseline),patternSHA256=sha(cache),auxiliarySHA256=sha(auxcache),matureDayControlMaximumDifference=float(np.max(abs(p['planningForestControl'][mature&day]-base[mature&day]))),
        helperSHA256={name:sha(root/'Scripts'/name) for name in ['research_sleep_care_alignment.py','research_sleep_care_signatures.py','research_sleep_care_recurrent.py','research_sleep_predictions.py','research_sleep_behavior_schedule.py','research_sleep_planning.py','research_sleep_ensemble.py']},
        strategy='GRU16 next-completed-care pretraining, soft mark cross entropy plus log1p waiting-time/4 absolute loss. Eight full passes, batch128, AdamW.01/.01 and gradient cap1. Frozen16-dimensional encoder states augment existing planning forest.',
        controls='Shared early/all-clock planning forest, same random encoder, or encoder trained with fixed shuffled next-mark/time pairs preserving marginal targets and optimizer budget.',
        training=dict(days=60,auxiliaryHalfLifeDays=None,planningMinimumLabels=3,earlyRefitEveryQueryBelow40Labels=True,refitQueries=24,daytimeOnly=False,encoderEpochs=8,batchSize=128,trees=80,minimumLeaf=5,seed=42),
        causalRule='Only auxiliary NEXT-group completions<=fit wake train the encoder. Each query pattern contains completed past care only. Planning labels mature at sleep end; current future sleep type never routes. Before3 resolved planning labels use app points; then forecast the distinct planning target at every wake clock. Current outcome type never selects a mode; all original cases retained.',
        runtime=dict(torchVersion=torch.__version__,threads=2,device='cpu',deterministicAlgorithms=True),diagnostics=diag,auxiliaryRows=len(aux['origins']),skippedInputRecords=skipped,
        sourceURL='https://arxiv.org/abs/1807.03748',
        limitation='All-clock planning research is not an overnight-resettling predictor. Inspired by predictive representation learning, but direct next-mark/time losses, NOT contrastive CPC reproduction. Retrospective archive-selected study; not prospective validation or physiological measurement.'),models={},events={})
    for name,values in {'appV8':base,**p}.items():
        result['models'][name]={key:metrics(d['y'],values,m) for key,m in masks.items()}
        result['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(d['indices'],d['y'],values)]
        print(name,json.dumps(result['models'][name]['planning']),flush=True)
    a.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')

if __name__=='__main__':main()
