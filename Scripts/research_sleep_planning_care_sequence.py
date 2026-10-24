#!/usr/bin/env python3
"""Planning-target supervision of ordered completed-care sequences."""
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
from research_sleep_care_signatures import read_marks
from research_sleep_care_recurrent import CareNetwork,fit_scale,normalized,sequence_view,fit_model,predict_model
from research_sleep_planning_adaptation import split_history
from research_sleep_behavior_schedule import structure
from research_sleep_planning import eligible,planning_mask
from research_sleep_ensemble import metrics,weighted_median


SPECS={'allLabelsOrdered':('all','ordered'),'planningContext':('planning','context'),
       'planningPooled':('planning','pooled'),'planningOrdered':('planning','ordered')}


def fit_trajectory(sequence,context,target,weights,epochs=(16,64,128)):
    """Capture the same deterministic cold-fit trajectory at three budgets."""
    epochs=tuple(sorted(set(epochs)))
    if not epochs or epochs[0]<1:raise ValueError('Positive training checkpoints required')
    torch.manual_seed(42)
    context=np.column_stack([context,np.isfinite(context).astype(float)])
    cs=fit_scale(context,weights)
    ss=fit_scale(sequence.reshape(-1,sequence.shape[-1]),np.repeat(weights,sequence.shape[1]))
    center=float(weighted_median(target,weights))
    x=torch.from_numpy(normalized(sequence,ss));c=torch.from_numpy(normalized(context,cs))
    y=torch.from_numpy(((target-center)/60).astype(np.float32));w=torch.from_numpy((weights/weights.sum()).astype(np.float32))
    model=CareNetwork(sequence.shape[-1],context.shape[1]);optimizer=torch.optim.AdamW(model.parameters(),lr=.01,weight_decay=.01)
    model.train();out={};parameters=sum(p.numel() for p in model.parameters())
    for epoch in range(1,epochs[-1]+1):
        optimizer.zero_grad(set_to_none=True);prediction=model(x,c);loss=torch.sum(abs(prediction-y)*w)
        if not torch.isfinite(loss):raise RuntimeError('Nonfinite care-sequence training loss')
        loss.backward();nn.utils.clip_grad_norm_(model.parameters(),1.);optimizer.step()
        if epoch in epochs:out[epoch]=(copy.deepcopy(model).eval(),ss,cs,center,float(loss.detach()),parameters)
    return out


def choose_duration(sequence,context,data,base,training,validation,now,epochs=(16,64,128),trajectory=fit_trajectory,predict=predict_model):
    weights=np.exp2(-(now-data['wakes'][training])/(14*86400));vw=np.exp2(-(now-data['wakes'][validation])/(14*86400))
    target=data['y'][training]-base[training]
    fits=trajectory(sequence[training],context[training],target,weights,epochs)
    losses={0:float(np.average(abs(data['y'][validation]-base[validation]),weights=vw))}
    for epoch,fit in fits.items():
        p=np.clip(base[validation]+predict(fit,sequence[validation],context[validation]),1,480)
        if not np.isfinite(p).all():raise RuntimeError('Nonfinite validation forecast')
        losses[epoch]=float(np.average(abs(data['y'][validation]-p),weights=vw))
    chosen=min(losses,key=lambda e:(losses[e],e))
    return chosen,losses


def replay(data,context,base,patterns,progress=None,epochs=(16,64,128),choose=choose_duration,fit=fit_model,predict=predict_model):
    torch.set_num_threads(2);torch.use_deterministic_algorithms(True)
    valid=np.isfinite(patterns).all(axis=(1,2));C=np.column_stack([data['X'],context['X'][:,5:8],base])
    views={kind:sequence_view(patterns,kind) for kind in ['context','pooled','ordered']}
    output={name:base.copy() for name in SPECS};models={};fitted=-24;fits=learned=0
    diag={name:dict(epochChoices={str(e):0 for e in (0,*epochs)},trainedFits=0,parameters=None) for name in SPECS}
    with threadpool_limits(limits=2):
        for i,now in enumerate(data['wakes']):
            planning=eligible(data,context,i,True);planning=planning[valid[planning]]
            if not valid[i] or len(planning)<40:continue
            if not models or i-fitted>=24:
                older,validation=split_history(data,context,planning)
                all_known=eligible(data,context,i,False);all_known=all_known[valid[all_known]]
                all_train=all_known[(all_known<validation[0])&(context['knownAt'][all_known]<=data['wakes'][validation[0]])]
                if len(older)<20:raise ValueError('Insufficient purged validation training history')
                cohorts={'planning':(planning,older),'all':(all_known,all_train)};models={};choices={}
                for name,(cohort,view) in SPECS.items():
                    known,training=cohorts[cohort];P=views[view]
                    chosen,_=choose(P,C,data,base,training,validation,now,epochs)
                    choices[name]=chosen;diag[name]['epochChoices'][str(chosen)]+=1
                    models[name]=None
                    if chosen:
                        weights=np.exp2(-(now-data['wakes'][known])/(14*86400))
                        models[name]=fit(P[known],C[known],data['y'][known]-base[known],weights,chosen)
                        diag[name]['trainedFits']+=1;diag[name]['parameters']=models[name][-1]
                fitted=i;fits+=1
                if progress:progress(dict(refits=fits,query=i,planningLabels=len(planning),allLabels=len(all_known),validation=len(validation),selectedEpochs=choices))
            if not 360<=context['wakeClock'][i]<1260:continue
            for name,model in models.items():
                if model is None:continue
                P=views[SPECS[name][1]]
                point=float(predict(model,P[i:i+1],C[i:i+1])[0])+base[i]
                if not np.isfinite(point):raise RuntimeError('Nonfinite care-sequence forecast')
                output[name][i]=np.clip(point,1,480)
            learned+=1
    return output,dict(refits=fits,eligibleQueries=learned,validPatterns=int(valid.sum()),models=diag)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','baseline','output']:ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--limit',type=int);a=ap.parse_args();root=Path(__file__).resolve().parents[1]
    if a.output.resolve().is_relative_to(root):ap.error('Keep private histories and results outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    app=json.loads(a.baseline.read_text());assert app['audit']['sourceSHA256']==sha(a.source)
    with np.load(a.features,allow_pickle=False) as file:d=dict(file)
    n=len(d['y'])
    if a.limit:d={k:v[:a.limit] if v.ndim and len(v)==n else v for k,v in d.items()}
    rows={v['index']:v for v in app['events']}
    np.testing.assert_allclose([rows[int(i)]['wakeMinutes'] for i in d['indices']],d['y'],rtol=0,atol=1e-6)
    c=structure(a.source,d,rows,'America/Los_Angeles');base=(np.array([rows[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60
    events,skipped=read_marks(a.source,'America/Los_Angeles');P=care_patterns(events,d['wakes'],16)
    cache=a.output.with_suffix('.patterns.npy');np.save(cache,P,allow_pickle=False);start=time.monotonic()
    predictions,diag=replay(d,c,base,P,lambda x:print(json.dumps(dict(**x,seconds=time.monotonic()-start)),flush=True))
    mask=planning_mask(d,c);masks={'planning':mask,'naps':mask&(c['labels']==1),'bedtime':mask&(c['labels']==2)}
    result=dict(audit=dict(sourceSHA256=sha(a.source),scriptSHA256=sha(Path(__file__)),featureSHA256=sha(a.features),baselineSHA256=sha(a.baseline),patternSHA256=sha(cache),
        helperSHA256={name:sha(root/'Scripts'/name) for name in ['research_sleep_care_alignment.py','research_sleep_care_signatures.py','research_sleep_care_recurrent.py','research_sleep_planning_adaptation.py','research_sleep_behavior_schedule.py','research_sleep_planning.py','research_sleep_ensemble.py']},
        strategy='Small GRU residual correction from16 completed care-event groups in48hours; matched all-label ordered control versus planning-only zero/pooled/ordered sequence views. Common planning-label validation and fit cadence.',
        training=dict(days=60,halfLifeDays=14,minimumResolvedPlanningLabels=40,refitQueries=24,epochs=[0,16,64,128],optimizer='AdamW',learningRate=.01,weightDecay=.01,gradientCap=1,seed=42),
        selection='Latest20percent/min8 resolved planning labels validate original issued app versus checkpoints16/64/128; older label maturity purged at first validation wake. Choose weighted validation MAE, ties prefer fewer epochs, then cold-refit own full-known cohort.',
        architecture='One16-unit GRU plus16-unit tanh head. Context compact28 plus issued app point and missingness. Training-only scales/weighted residual median; fixed60minute output scale.',
        causalRule='Only completed care and resolved historical labels enter sequences/fits. Current target kind never gates a forecast. Sparse/invalid-pattern/night queries retain app points; all original cases retained.',
        runtime=dict(torchVersion=torch.__version__,threads=2,device='cpu',deterministicAlgorithms=True),diagnostics=diag,skippedInputRecords=skipped,
        limitation='Independent planning-focused care-sequence adaptation, not measured infant physiology. Retrospective archive-selected experiment, not prospective validation or app integration.'),models={},events={})
    for name,p in {'appV8':base,**predictions}.items():
        result['models'][name]={key:metrics(d['y'],p,m) for key,m in masks.items()}
        result['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(d['indices'],d['y'],p)]
        print(name,json.dumps(result['models'][name]['planning']),flush=True)
    a.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')

if __name__=='__main__':main()
