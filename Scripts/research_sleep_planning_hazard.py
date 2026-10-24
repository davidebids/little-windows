#!/usr/bin/env python3
"""Planning-only discrete-time hazards with separate nap and bedtime events."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from sklearn.ensemble import HistGradientBoostingClassifier
from threadpoolctl import threadpool_limits
from research_sleep_predictions import hazard_features
from research_sleep_behavior_schedule import structure
from research_sleep_planning import eligible,planning_mask
from research_sleep_planning_mixture import mixture_point
from research_sleep_ensemble import metrics

GRID=np.arange(21.,481.)


def exposure(row,gap,label,names):
    end=min(480,int(np.ceil(gap)))
    if end<21:raise ValueError('Exposure requires a distinct planning interval')
    grid=GRID[:end-20]
    X=hazard_features(np.repeat(row[None,:],len(grid),axis=0),grid,list(names))
    target=np.zeros(len(grid),int)
    if gap<=480:target[-1]=label
    return X,target


def event_mass(probabilities,classes):
    hazard=np.clip(probabilities[:,np.asarray(classes)!=0].sum(axis=1),0,1)
    before=np.r_[1.,np.cumprod(1-hazard[:-1])]
    mass=before*hazard
    # Forecast support is bounded; preserve unobserved tail as terminal mass.
    mass[-1]+=float(np.prod(1-hazard))
    return mass/mass.sum()


def replay(data,context,base,progress=None,factory=None):
    if factory is None:
        factory=lambda:HistGradientBoostingClassifier(max_iter=150,max_leaf_nodes=15,
            min_samples_leaf=30,l2_regularization=10,early_stopping=False,random_state=42)
    X=np.column_stack([data['X'],context['X'][:,5:8]]);cohort=planning_mask(data,context)
    exposures={j:exposure(X[j],data['y'][j],int(context['labels'][j]),data['names']) for j in np.flatnonzero(cohort)}
    outputs={};diagnostics={}
    with threadpool_limits(limits=1):
        for kind in ['single','competing']:
            p={action:base.copy() for action in ['Median','Risk30']};model=None;fitted=-24;fits=learned=0
            for i in range(len(base)):
                known=eligible(data,context,i,True)
                if len(known)<40:continue
                if model is None or i-fitted>=24:
                    tx=np.vstack([exposures[j][0] for j in known]);ty=np.concatenate([exposures[j][1] for j in known])
                    if kind=='single':ty=(ty>0).astype(int)
                    model=factory().fit(tx,ty);fitted=i;fits+=1
                    if progress and fits%20==0:progress(kind,dict(refits=fits,query=i))
                if not 360<=context['wakeClock'][i]<1260:continue
                future=hazard_features(np.repeat(X[i:i+1],len(GRID),axis=0),GRID,list(data['names']))
                mass=event_mass(model.predict_proba(future),model.classes_)
                p['Median'][i]=mixture_point([(GRID,mass,1.)])
                p['Risk30'][i]=mixture_point([(GRID,mass,1.)],30.)
                learned+=1
            for action,points in p.items():outputs[kind+'Hazard'+action]=points
            diagnostics[kind]=dict(refits=fits,learnedQueries=learned,exposureRows=sum(len(exposures[j][1]) for j in exposures))
    return outputs,diagnostics


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for key in ['source','features','baseline','output']:ap.add_argument('--'+key,type=Path,required=True)
    ap.add_argument('--limit',type=int);a=ap.parse_args();root=Path(__file__).resolve().parents[1]
    if a.output.resolve().is_relative_to(root):ap.error('Keep private forecasts outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    app=json.loads(a.baseline.read_text());assert app['audit']['sourceSHA256']==sha(a.source)
    with np.load(a.features,allow_pickle=False) as file:d=dict(file)
    n=len(d['y'])
    if a.limit:d={k:v[:a.limit] if v.ndim and len(v)==n else v for k,v in d.items()}
    rows={e['index']:e for e in app['events']}
    np.testing.assert_allclose([rows[int(i)]['wakeMinutes'] for i in d['indices']],d['y'],rtol=0,atol=1e-6)
    c=structure(a.source,d,rows,'America/Los_Angeles');base=(np.array([rows[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60
    forecasts,diag=replay(d,c,base,lambda name,diag:print(name,json.dumps(diag),flush=True))
    mask=planning_mask(d,c);masks={'planning':mask,'naps':mask&(c['labels']==1),'bedtime':mask&(c['labels']==2)}
    result=dict(audit=dict(sourceSHA256=sha(a.source),scriptSHA256=sha(Path(__file__)),featureSHA256=sha(a.features),baselineSHA256=sha(a.baseline),
        helperSHA256={name:sha(root/'Scripts'/name) for name in ['research_sleep_predictions.py','research_sleep_behavior_schedule.py','research_sleep_planning.py','research_sleep_planning_mixture.py','research_sleep_ensemble.py']},
        strategy='One-minute conditional planning hazard from21..480min; binary sleep versus separate nap/bedtime event labels sharing still-awake class. Origin context plus elapsed, future wall-clock phase and deterministic continued-awake homeostats. Median or absolute-error-plus30miss-penalty decision.',
        training=dict(days=60,minimumResolvedPlanningLabels=40,refitQueries=24,iterations=150,leaves=15,minimumLeaf=30,L2=10),
        causalRule='Only historical target-end-resolved planning outcomes enter hazard exposures. No current kind or future care enters a curve. Conditional on distinct planning sleep, not a short-return probability model. Sparse/overnight use app forecast; all original scored cases retained.',
        sourceURL='https://scikit-learn.org/stable/modules/generated/sklearn.ensemble.HistGradientBoostingClassifier.html',
        limitation='Independent empirical discrete-time model, not a published infant predictor. Terminal survival mass assigned480min; archive-selected retrospective comparison only.',diagnostics=diag),models={},events={})
    for name,p in {'appV8':base,**forecasts}.items():
        result['models'][name]={k:metrics(d['y'],p,m) for k,m in masks.items()}
        result['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(d['indices'],d['y'],p)]
        print(name,json.dumps(result['models'][name]['planning']),flush=True)
    a.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')

if __name__=='__main__':main()
