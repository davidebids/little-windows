#!/usr/bin/env python3
"""Local pretrained tabular prior, conditioned only on distinct planning labels."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import time
import numpy as np
from research_sleep_behavior_schedule import structure
from research_sleep_planning import eligible,planning_mask
from research_sleep_ensemble import metrics


def replay(data,context,base,factory,progress=None):
    X=np.column_stack([data['X'],context['X'][:,5:8]])
    outputs={k:base.copy() for k in ['priorPlanningMean','priorPlanningMedian','priorPlanningMode']}
    model=None;fitted=-24;fits=learned=0
    for i in range(len(base)):
        known=eligible(data,context,i,True)
        if len(known)<40:continue
        if model is None or i-fitted>=24:
            model=factory();model.fit(X[known],data['y'][known]);fitted=i;fits+=1
            if progress:progress(dict(refits=fits,query=i,labels=len(known)))
        if not 360<=context['wakeClock'][i]<1260:continue
        points=model.predict(X[i:i+1],output_type='main')
        for name,key in [('priorPlanningMean','mean'),('priorPlanningMedian','median'),('priorPlanningMode','mode')]:
            point=float(np.asarray(points[key])[0])
            if not np.isfinite(point):raise ValueError('Nonfinite output; retain cohort and fail experiment')
            outputs[name][i]=np.clip(point,1,480)
        learned+=1
    return outputs,dict(refits=fits,learnedQueries=learned,features=X.shape[1])


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for key in ['source','features','baseline','bootstrap','output']:ap.add_argument('--'+key,type=Path,required=True)
    ap.add_argument('--limit',type=int);a=ap.parse_args();root=Path(__file__).resolve().parents[1]
    if a.output.resolve().is_relative_to(root):ap.error('Keep private history and forecasts outside source')
    if os.environ.get('HF_HUB_OFFLINE')!='1':ap.error('Use cached weights with HF_HUB_OFFLINE=1')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    bootstrap=json.loads(a.bootstrap.read_text());assert bootstrap['passed'] and bootstrap['device']=='cpu'
    for path,digest in bootstrap['weights'].items():assert sha(Path(path))==digest
    import torch
    import tabpfn
    from tabpfn import TabPFNRegressor
    from tabpfn.constants import ModelVersion
    torch.set_num_threads(2)
    app=json.loads(a.baseline.read_text());assert app['audit']['sourceSHA256']==sha(a.source)
    with np.load(a.features,allow_pickle=False) as file:d=dict(file)
    n=len(d['y'])
    if a.limit:d={k:v[:a.limit] if v.ndim and len(v)==n else v for k,v in d.items()}
    rows={e['index']:e for e in app['events']}
    np.testing.assert_allclose([rows[int(i)]['wakeMinutes'] for i in d['indices']],d['y'],rtol=0,atol=1e-6)
    c=structure(a.source,d,rows,'America/Los_Angeles');base=(np.array([rows[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60
    def factory():
        return TabPFNRegressor.create_default_for_version(ModelVersion.V2,device='cpu',n_estimators=8,
            auto_scale_n_estimators=False,fit_mode='fit_with_cache',random_state=42)
    start=time.monotonic()
    def progress(diag):print(json.dumps(dict(**diag,seconds=time.monotonic()-start)),flush=True)
    predictions,diag=replay(d,c,base,factory,progress);mask=planning_mask(d,c)
    masks={'planning':mask,'naps':mask&(c['labels']==1),'bedtime':mask&(c['labels']==2)}
    result=dict(audit=dict(sourceSHA256=sha(a.source),scriptSHA256=sha(Path(__file__)),featureSHA256=sha(a.features),baselineSHA256=sha(a.baseline),
        helperSHA256={name:sha(root/'Scripts'/name) for name in ['research_sleep_behavior_schedule.py','research_sleep_planning.py','research_sleep_ensemble.py']},
        strategy='Existing local pretrained tabular v2 prior on compact28 inputs, conditioned only on resolved distinct-planning labels. Mean, median and mode forecast actions. Individual current queries only; no hosted inference.',
        training=dict(days=60,minimumResolvedPlanningLabels=40,refitQueries=24,estimators=8,randomState=42),
        runtime=dict(tabpfnVersion=tabpfn.__version__,torchVersion=torch.__version__,device='cpu',torchThreads=2,offline=True,weights=bootstrap['weights'],modelVersion='v2'),
        causalRule='Current and future outcomes never enter a fit; planning labels mature at next sleep END. Current query kind is not supplied. Sparse/overnight queries retain app points; all original cases retained.',
        sourceURLs=['https://www.nature.com/articles/s41586-024-08328-6','https://github.com/PriorLabs/TabPFN'],
        limitation='General tabular prior, not pretrained infant-specific sleep schedules. Retrospective archive-selected comparison, not prospective validation or a native app model.',diagnostics=diag),models={},events={})
    for name,p in {'appV8':base,**predictions}.items():
        result['models'][name]={k:metrics(d['y'],p,m) for k,m in masks.items()}
        result['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(d['indices'],d['y'],p)]
        print(name,json.dumps(result['models'][name]['planning']),flush=True)
    a.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')

if __name__=='__main__':main()
