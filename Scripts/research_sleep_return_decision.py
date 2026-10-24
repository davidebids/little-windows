#!/usr/bin/env python3
"""Choose between issued app timing and a short nap-return estimate by learned loss."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from sklearn.tree import DecisionTreeRegressor
from sklearn.linear_model import Ridge
from sklearn.preprocessing import StandardScaler
from research_sleep_behavior_schedule import structure, weighted_median
from research_sleep_ensemble import metrics


def snapshots(data,context,base):
    """Freeze return estimates and behavior rates at each original wake."""
    n=len(base); cx=context['X']; clock=context['wakeClock']; ordinal=context['ordinal']
    eligible=(cx[:,3]==0)&(clock>=360)&(clock<1260)&(base>20)
    returned=np.full(n,8.); history_features=[]
    for i,now in enumerate(data['wakes']):
        known=np.flatnonzero((np.arange(n)<i)&(data['available']<=now)&eligible&(data['wakes']>=now-28*86400))
        short=known[data['y'][known]<=20]
        if len(short)>=3:
            weights=np.exp2(-(now-data['wakes'][short])/(7*86400))
            weights*=np.where(ordinal[short]==ordinal[i],1.,.2)
            returned[i]=weighted_median(data['y'][short],weights)
        features=[]
        for days in [5,14]:
            selected=known[data['wakes'][known]>=now-days*86400]
            w=np.exp2(-(now-data['wakes'][selected])/(days*86400))
            short_label=(data['y'][selected]<=20).astype(float)
            angle=np.mod(clock[selected]-clock[i]+720,1440)-720
            same_ordinal=(ordinal[selected]==ordinal[i]).astype(float)
            duration=np.exp(-.5*(np.log1p(cx[selected,5])-np.log1p(cx[i,5]))**2/.7**2)
            local=np.exp(-.5*(angle/120)**2)*duration
            for kernel in [np.ones(len(selected)),same_ordinal,duration,local]:
                weights=w*kernel
                features.extend([(1+weights@short_label)/(5+weights.sum()),np.log1p(weights.sum())])
        recent=known[-3:]
        features.extend([float(np.mean(data['y'][recent]<=20)) if len(recent) else .2,float(len(recent))])
        history_features.append(features)
    core=np.column_stack([cx,base,returned])
    return eligible,returned,core,np.column_stack([core,np.asarray(history_features)])


def benefit(y,base,returned,risk=0.):
    app_error=np.abs(base-y); return_error=np.abs(returned-y)
    return app_error-return_error+risk*((app_error>30).astype(float)-(return_error>30).astype(float))


def replay(data,context,base):
    eligible,returned,core,augmented=snapshots(data,context,base); n=len(base); outputs={}; diagnostics={}
    for learned_history,X in [(False,core),(True,augmented)]:
        for learner in ['tree','ridge']:
            for risk in [0.,30.]:
                p=base.copy(); last=-8; model=None; scaler=None; fits=queries=0; gains=np.zeros(n)
                for i,now in enumerate(data['wakes']):
                    if not eligible[i]: continue
                    known=np.flatnonzero((np.arange(n)<i)&(data['available']<=now)&eligible&(data['wakes']>=now-28*86400))
                    if len(known)<30: continue
                    if model is None or i-last>=8:
                        target=benefit(data['y'][known],base[known],returned[known],risk)
                        weights=np.exp2(-(now-data['wakes'][known])/(7*86400))
                        if learner=='tree':
                            model=DecisionTreeRegressor(max_depth=3,min_samples_leaf=12,random_state=42)
                            model.fit(X[known],target,sample_weight=weights); scaler=None
                        else:
                            scaler=StandardScaler().fit(X[known]); model=Ridge(alpha=10.)
                            model.fit(scaler.transform(X[known]),target,sample_weight=weights)
                        last=i; fits+=1
                    query=X[i:i+1] if scaler is None else scaler.transform(X[i:i+1])
                    gain=float(model.predict(query)[0]); gains[i]=gain
                    if gain>0: p[i]=returned[i]
                    queries+=1
                switched=p!=base; ae=np.abs(base-data['y']); pe=np.abs(p-data['y'])
                short=(data['y']<=20)&eligible; longer=(data['y']>20)&eligible
                name=f'returnDecision_{"history" if learned_history else "core"}_{learner}_risk{risk:g}'
                outputs[name]=p
                diagnostics[name]=dict(refits=fits,learnedEligibleQueries=queries,eligibleQueries=int(sum(eligible)),switches=int(sum(switched)),
                    trueShortSwitches=int(sum(switched&short)),longerWakeSwitches=int(sum(switched&longer)),
                    absoluteErrorMinutesSaved=float(np.sum(ae-pe)),newWithin30Count=int(sum((pe<=30)&(ae>30))),lostWithin30Count=int(sum((pe>30)&(ae<=30))),
                    shortReturnMAE=float(np.mean(pe[short])) if sum(short) else None,longerWakeMAE=float(np.mean(pe[longer])) if sum(longer) else None,
                    sourceShortReturnMAE=float(np.mean(ae[short])) if sum(short) else None,sourceLongerWakeMAE=float(np.mean(ae[longer])) if sum(longer) else None)
    return outputs,diagnostics,eligible,returned


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','baseline','output']: ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--zone',default='America/Los_Angeles'); ap.add_argument('--limit',type=int); args=ap.parse_args()
    root=Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root): ap.error('Keep private forecasts outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    baseline=json.loads(args.baseline.read_text()); assert baseline['audit']['sourceSHA256']==sha(args.source)
    rows={e['index']:e for e in baseline['events']}; data=dict(np.load(args.features,allow_pickle=False)); n=len(data['y'])
    if args.limit: data={k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in data.items()}
    np.testing.assert_allclose([rows[int(i)]['wakeMinutes'] for i in data['indices']],data['y'],rtol=0,atol=1e-6)
    base=(np.array([rows[int(i)]['prediction'] for i in data['indices']])-data['wakes'])/60
    context=structure(args.source,data,rows,args.zone); forecasts,diag,eligible,returned=replay(data,context,base)
    result=dict(audit=dict(sourceSHA256=sha(args.source),featureCacheSHA256=sha(args.features),baselineResultSHA256=sha(args.baseline),scriptSHA256=sha(Path(__file__)),
        helperFilesSHA256={name:sha(root/'Scripts'/name) for name in ['research_sleep_behavior_schedule.py','research_sleep_ensemble.py']},careExposure='completed',
        strategy='Cost-sensitive app-versus-short-return decision; forecast original timer starts without merging or excluding cases',
        eligibility='Preceding completed sleep is nap; wake clock06:00..21:00; issued app gap over20 minutes. All other cases retain app and remain scored.',
        returnEstimate='At least3 prior available short eligible gaps: ordinal/7day weighted median over28days; otherwise8minute fixed research prior',
        historyInputs='Frozen own-origin 5/14day past-return rates with global/ordinal/episode-duration/clock kernels, pseudocount1/5; effective counts; last3 available eligible outcomes',
        learner=dict(historyDays=28,minimumLabels=30,weightHalfLifeDays=7,refitEveryQueries=8,treeDepth=3,treeMinimumLeaf=12,ridgePenalty=10),
        target='Past issued app loss minus own-origin return estimate loss. Absolute minutes, optionally plus30 per thirty-minute miss. Choose return only when fitted expected benefit is positive.',
        diagnostics=diag,sourceURLs=['https://scikit-learn.org/stable/auto_examples/model_selection/plot_cost_sensitive_learning.html'],
        limitation='Independent full-information decision adaptation, not a commercial formula; retrospective only. Nap-return component study does not solve all remaining behaviors.'),models={},events={})
    for name,p in forecasts.items():
        result['models'][name]=dict(all=metrics(data['y'],p,np.ones(len(p),dtype=bool)))
        result['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v),eligible=bool(e),shortReturnPoint=float(q)) for i,y,v,e,q in zip(data['indices'],data['y'],p,eligible,returned)]
        print(name,json.dumps(result['models'][name]),flush=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')


if __name__=='__main__': main()
