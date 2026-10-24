#!/usr/bin/env python3
"""Separate unexpectedly late next-sleep starts from ordinary planning errors."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from sklearn.ensemble import ExtraTreesClassifier
from sklearn.impute import SimpleImputer
from research_sleep_behavior_schedule import structure
from research_sleep_planning import eligible,planning_mask
from research_sleep_predictions import WakeAnalogs
from research_sleep_planning_mixture import distribution,mixture_point
from research_sleep_ensemble import metrics


def replay(data,context,base,progress=None,components=None):
    X=np.column_stack([data['X'],context['X'][:,5:8],base])
    residual=data['y']-base;late=residual>30
    outputs={name:base.copy() for name in ('residualControl','lateHard','lateBalancedHard','lateMixtureRisk30')}
    probabilities=np.full((2,len(base)),np.nan);pooled=None;body=tail=None;fitted=-24
    fits=learned=expertQueries=0
    for i in range(len(base)):
        known=eligible(data,context,i,True)
        if len(known)<40:continue
        if pooled is None or i-fitted>=24:
            pooled=WakeAnalogs('forest',5).fit(X[known],residual[known]);fitted=i;fits+=1
            ordinary=known[~late[known]];long=known[late[known]]
            body=tail=None;gates=[]
            if len(ordinary)>=20 and len(long)>=20:
                body=WakeAnalogs('forest',5).fit(X[ordinary],residual[ordinary])
                tail=WakeAnalogs('forest',5).fit(X[long],residual[long])
                imputer=SimpleImputer(keep_empty_features=True).fit(X[known]);G=imputer.transform(X[known])
                for balanced in (False,True):
                    gate=ExtraTreesClassifier(n_estimators=80,min_samples_leaf=5,max_features=.8,
                        random_state=42,n_jobs=1,class_weight='balanced' if balanced else None)
                    gates.append(gate.fit(G,late[known]))
        if not 360<=context['wakeClock'][i]<1260:continue
        query=X[i:i+1]
        outputs['residualControl'][i]=np.clip(base[i]+pooled.predict(query)[0],1,480);learned+=1
        if body is None or tail is None:continue
        G=imputer.transform(query)
        p=[float(gate.predict_proba(G)[0,list(gate.classes_).index(True)]) for gate in gates]
        probabilities[:,i]=p
        normal=float(body.predict(query)[0]);long=float(tail.predict(query)[0])
        if components is not None:components[:,i]=np.clip(base[i]+np.array([normal,long]),1,480)
        outputs['lateHard'][i]=np.clip(base[i]+(long if p[0]>=.5 else normal),1,480)
        outputs['lateBalancedHard'][i]=np.clip(base[i]+(long if p[1]>=.5 else normal),1,480)
        values,weights=distribution(body,query);parts=[(np.clip(base[i]+values,1,480),weights,1-p[0])]
        values,weights=distribution(tail,query);parts.append((np.clip(base[i]+values,1,480),weights,p[0]))
        outputs['lateMixtureRisk30'][i]=mixture_point(parts,30);expertQueries+=1
    diag=dict(refits=fits,pooledQueries=learned,twoExpertQueries=expertQueries,features=X.shape[1],
        gateFires=[int(np.sum(probabilities[k]>=.5)) for k in (0,1)])
    if progress:progress(diag)
    return outputs,probabilities,diag


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ('source','features','baseline','output'):ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--design',choices=('compact','complete'),default='compact',help='Label the supplied completed-history feature design; fitting policy is unchanged')
    ap.add_argument('--limit',type=int);args=ap.parse_args();root=Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root):ap.error('Keep private results outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    app=json.loads(args.baseline.read_text());assert app['audit']['sourceSHA256']==sha(args.source)
    with np.load(args.features,allow_pickle=False) as cache:data=dict(cache)
    n=len(data['y'])
    if args.limit:data={k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in data.items()}
    rows={e['index']:e for e in app['events']};context=structure(args.source,data,rows,'America/Los_Angeles')
    base=(np.array([rows[int(i)]['prediction'] for i in data['indices']])-data['wakes'])/60
    components=np.full((2,len(base)),np.nan)
    forecasts,probabilities,diag=replay(data,context,base,lambda d:print(json.dumps(d),flush=True),components)
    gatesPath=args.output.with_suffix('.gates.npy');np.save(gatesPath,probabilities)
    componentsPath=args.output.with_suffix('.components.npy');np.save(componentsPath,components)
    primary=planning_mask(data,context)
    masks=dict(planning=primary,naps=primary&(context['labels']==1),bedtime=primary&(context['labels']==2),allTimers=np.ones(len(base),bool))
    confusion={};truth=data['y']-base>30
    # Hindsight diagnostic only. Never feed current true class into a forecast
    # or add this vector to the list of evaluated prediction candidates.
    perfectClass=base.copy();usable=np.isfinite(components).all(axis=0);positions=np.flatnonzero(usable)
    perfectClass[usable]=components[truth[usable].astype(int),positions]
    for k,label in enumerate(('ordinary','classBalanced')):
        valid=np.isfinite(probabilities[k])&primary;pred=probabilities[k]>=.5
        confusion[label]=dict(evaluatedQueries=int(valid.sum()),truePositive=int((valid&truth&pred).sum()),falsePositive=int((valid&~truth&pred).sum()),falseNegative=int((valid&truth&~pred).sum()),trueNegative=int((valid&~truth&~pred).sum()))
    result=dict(audit=dict(sourceSHA256=sha(args.source),scriptSHA256=sha(Path(__file__)),featureSHA256=sha(args.features),baselineSHA256=sha(args.baseline),gatesSHA256=sha(gatesPath),componentsSHA256=sha(componentsPath),
        helperSHA256={name:sha(root/'Scripts'/name) for name in ('research_sleep_predictions.py','research_sleep_behavior_schedule.py','research_sleep_planning.py','research_sleep_planning_mixture.py','research_sleep_ensemble.py')},
        diagnostics=diag,gateConfusionForResolvedPrimary=confusion,
        featureDesign=args.design,featureNames=list(data['names']),
        hindsightTrueClassDiagnostic=dict(planning=metrics(data['y'],perfectClass,primary),scope='Not a forecast: current realized residual class chooses between the two already fitted component points; supplied app points fill unavailable components. Not a bound on other algorithms.'),
        training=dict(days=60,minimumResolvedPlanningLabels=40,minimumPerExpert=20,refitQueries=24,trees=80,minimumLeaf=5,lateResidualBoundaryMinutes=30),
        strategy='Pooled residual control versus two residual experts split by actual next-start delay more than30 minutes beyond the originally issued app point. Wake-known classifier selects experts normally or with class balancing; unweighted probability mixture chooses expected absolute loss+30*miss30. All labels delayed until target sleep end.',
        limitation='Balanced classifier outputs are cost-weighted scores, not calibrated event probabilities. Current outcome never selects a forecast. Supplied completed-history inputs plus episode context and issued app points; archive-selected research, not prospective validation.'),models={},events={})
    for name,p in dict(appV8=base,**forecasts).items():
        result['models'][name]={key:metrics(data['y'],p,m) for key,m in masks.items()}
        result['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(data['indices'],data['y'],p)]
        print(name,json.dumps(result['models'][name]['planning']),flush=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')


if __name__=='__main__':main()
