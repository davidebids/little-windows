#!/usr/bin/env python3
"""Chronological, personal weight adaptation of a local tabular sleep prior."""
import argparse
import hashlib
from importlib.metadata import version
import json
import os
from pathlib import Path
import time
import numpy as np
from research_sleep_behavior_schedule import structure
from research_sleep_planning import eligible,planning_mask
from research_sleep_ensemble import metrics


def split_history(data,context,known):
    count=max(8,int(np.ceil(.2*len(known))))
    validation=known[-count:]
    training=known[:-count]
    training=training[context['knownAt'][training]<=data['wakes'][validation[0]]]
    return training,validation


def expand_context(wrapper,X,y):
    selected=wrapper.model_
    inner=wrapper._build_inner_estimator(selected,wrapper.n_estimators_inference,wrapper._resolve_device())
    inner.fit(wrapper._transform_X_for_inference(X),y)
    if inner.model_ is not selected:raise RuntimeError('Context expansion replaced selected weights')
    inner.__dict__.pop('_load_model',None)
    inner._save_model_weights=True
    wrapper._final_estimator_=inner


def local_factory(weight,epochs=30):
    import torch
    from tabicl import FinetunedTabICLRegressor
    from tabicl._finetune.base import ValidationMetrics
    class MedianValidation(FinetunedTabICLRegressor):
        def _run_validation(self,inner,X_train,y_train,X_val,y_val):
            self.validationCalls=getattr(self,'validationCalls',0)+1
            inner.fit(X_train,y_train)
            p=np.array([float(inner.predict(X_val[j:j+1],output_type='median')[0]) for j in range(len(y_val))])
            if not np.isfinite(p).all():raise ValueError('Nonfinite internal validation')
            mae=float(np.mean(abs(p-y_val)))
            return ValidationMetrics(primary=-mae,secondary={'median_mae':mae})
        def _metric_improved(self,current,best):
            improved=super()._metric_improved(current,best)
            if improved:self.bestEpoch=self.validationCalls-1
            return improved
        def _compute_batch_loss(self,batch,model):
            loss=super()._compute_batch_loss(batch,model)
            if not torch.isfinite(loss):raise ValueError('Nonfinite adaptation loss')
            self.trainingSteps=getattr(self,'trainingSteps',0)+1
            return loss
    class Adapter:
        def __init__(self,mode):self.mode=mode;self.model=None
        def fit(self,X,y,X_val,y_val):
            torch.manual_seed(42)
            self.model=MedianValidation(epochs=0 if self.mode=='frozen' else epochs,
                learning_rate=1e-5,weight_decay=.01,grad_clip=1.,amp=False,
                n_estimators_finetune=2,n_estimators_validation=2,n_estimators_inference=8,
                early_stopping=True,patience=8,min_delta=1e-4,freeze_col=True,freeze_row=True,
                model_path=weight,allow_auto_download=False,checkpoint_version='tabicl-regressor-v2-20260212.ckpt',
                device='cpu',random_state=42,verbose=False,wandb_kwargs=None,eval_metric='mae',
                extra_regressor_kwargs=dict(kv_cache=True,use_amp=False,use_fa3=False,offload_mode=False,n_jobs=2))
            self.model.bestEpoch=0
            self.model.fit(X,y,X_val=X_val,y_val=y_val)
            self.bestEpoch=self.model.bestEpoch;self.trainingSteps=getattr(self.model,'trainingSteps',0)
            return self
        def update_context(self,X,y):
            # Keep the older-training imputer unchanged for both models, but
            # expose all currently resolved labels to final in-context inference.
            # A plain final-estimator .fit reloads public weights in this API.
            # Build a new context estimator sharing the selected model instead.
            expand_context(self.model,X,y)
        def predict(self,X,output_type):return self.model.predict(X,output_type=output_type)
    return Adapter


def replay(data,context,base,factory,progress=None):
    X=np.column_stack([data['X'],context['X'][:,5:8]])
    outputs={mode+action:base.copy() for mode in ['frozen','personalized'] for action in ['Mean','Median']}
    models={};fitted=-24;fits=learned=0;diag={mode:dict(bestEpochs={},trainingSteps=0) for mode in ['frozen','personalized']}
    for i in range(len(base)):
        known=eligible(data,context,i,True)
        if len(known)<40:continue
        if not models or i-fitted>=24:
            train,val=split_history(data,context,known)
            if len(train)<20:raise ValueError('Insufficient purged older training history; retain cohort and fail')
            models={}
            for mode in ['frozen','personalized']:
                m=factory(mode).fit(X[train],data['y'][train],X_val=X[val],y_val=data['y'][val])
                m.update_context(X[known],data['y'][known]);models[mode]=m
                epoch=str(getattr(m,'bestEpoch',0));diag[mode]['bestEpochs'][epoch]=diag[mode]['bestEpochs'].get(epoch,0)+1
                diag[mode]['trainingSteps']+=getattr(m,'trainingSteps',0)
            fitted=i;fits+=1
            if progress:progress(dict(refits=fits,query=i,training=len(train),validation=len(val),bestEpoch=getattr(models['personalized'],'bestEpoch',0)))
        if not 360<=context['wakeClock'][i]<1260:continue
        for mode,m in models.items():
            p=m.predict(X[i:i+1],output_type=['mean','median'])
            for action,key in [('Mean','mean'),('Median','median')]:
                v=np.asarray(p[key])
                if v.shape!=(1,) or not np.isfinite(v).all():raise ValueError('Invalid adaptation forecast')
                outputs[mode+action][i]=np.clip(float(v[0]),1,480)
        learned+=1
    return outputs,dict(refits=fits,learnedQueries=learned,models=diag)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for key in ['source','features','baseline','bootstrap','output']:ap.add_argument('--'+key,type=Path,required=True)
    ap.add_argument('--limit',type=int);a=ap.parse_args();root=Path(__file__).resolve().parents[1]
    if a.output.resolve().is_relative_to(root):ap.error('Keep private data and outputs outside source')
    if os.environ.get('HF_HUB_OFFLINE')!='1':ap.error('Require offline inference')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    boot=json.loads(a.bootstrap.read_text());assert boot['passed'] and boot['device']=='cpu'
    for path,digest in boot['weights'].items():assert sha(Path(path))==digest
    assert len(boot['weights'])==1;weight=next(iter(boot['weights']))
    import torch
    torch.set_num_threads(2)
    app=json.loads(a.baseline.read_text());assert app['audit']['sourceSHA256']==sha(a.source)
    with np.load(a.features,allow_pickle=False) as file:d=dict(file)
    n=len(d['y'])
    if a.limit:d={k:v[:a.limit] if v.ndim and len(v)==n else v for k,v in d.items()}
    rows={e['index']:e for e in app['events']}
    np.testing.assert_allclose([rows[int(i)]['wakeMinutes'] for i in d['indices']],d['y'],rtol=0,atol=1e-6)
    c=structure(a.source,d,rows,'America/Los_Angeles');base=(np.array([rows[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60
    start=time.monotonic()
    p,diag=replay(d,c,base,local_factory(weight),lambda x:print(json.dumps(dict(**x,seconds=time.monotonic()-start)),flush=True))
    mask=planning_mask(d,c);masks={'planning':mask,'naps':mask&(c['labels']==1),'bedtime':mask&(c['labels']==2)}
    result=dict(audit=dict(sourceSHA256=sha(a.source),scriptSHA256=sha(Path(__file__)),featureSHA256=sha(a.features),baselineSHA256=sha(a.baseline),
        helperSHA256={name:sha(root/'Scripts'/name) for name in ['research_sleep_behavior_schedule.py','research_sleep_planning.py','research_sleep_ensemble.py']},
        strategy='TabICLv2 personal in-context prediction-layer weight adaptation; frozen column/row encoders, pinball loss, up to30epochs/AdamW1e-5, clip1, two training/validation estimators and eight inference estimators. Matched zero-epoch control.',
        selection='Latest20percent/min8 resolved labels held out; older training purged by label maturity at first validation wake. Single-query median MAE chooses baseline or best epoch, patience8. Final context expands to all resolved labels with older-only imputer retained.',
        runtime=dict(device='cpu',threads=2,weights=boot['weights'],tabiclVersion=version('tabicl'),torchVersion=torch.__version__,transformersVersion=version('transformers'),offline=True,wandb=None),
        causalRule='Only resolved planning labels in60days, min40, refit24; no current/future outcomes or hosted logging. Each origin starts public weights. Sparse/night retain app points; all original cases retained.',
        sourceURLs=['https://arxiv.org/abs/2602.11139','https://github.com/soda-inria/tabicl'],
        limitation='Independent chronological selection/median-validation/context-expansion adaptation of authors fine-tuning API. Retrospective archive-selected research, not prospective validation or app integration.',diagnostics=diag),models={},events={})
    for name,values in {'appV8':base,**p}.items():
        result['models'][name]={key:metrics(d['y'],values,m) for key,m in masks.items()}
        result['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(d['indices'],d['y'],values)]
        print(name,json.dumps(result['models'][name]['planning']),flush=True)
    a.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')

if __name__=='__main__':main()
