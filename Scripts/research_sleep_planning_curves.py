#!/usr/bin/env python3
"""Planning-only additive age/clock/episode curves and forest corrections."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from research_sleep_behavior_schedule import structure
from research_sleep_planning import planning_mask
from research_sleep_timing_curves import curve_design, fit_median
from research_sleep_ensemble import metrics


def replay(data, context, forest, progress=None):
    n=len(forest); cohort=planning_mask(data,context); outputs={}; diagnostics={}
    for mode in ['pooled','shared']:
        X,D,_=curve_design(context,mode)
        for residual in [False,True]:
            for penalty in [.05,.5]:
                p=forest.copy(); model=None; fitted=-24; fits=learned=0; maximum_error=0.
                for i,now in enumerate(data['wakes']):
                    known=np.flatnonzero((np.arange(n)<i)&cohort&(context['knownAt']<=now)&(data['wakes']>=now-84*86400))
                    if len(known)<20: continue
                    if model is None or i-fitted>=24:
                        weights=np.exp2(-(now-data['wakes'][known])/(14*86400))
                        target=data['y'][known]-(forest[known] if residual else 0.)
                        model,error=fit_median(X[known],target,weights,D,penalty)
                        maximum_error=max(maximum_error,error); fitted=i; fits+=1
                    p[i]=np.clip(float(X[i]@model)+(forest[i] if residual else 0.),1,480); learned+=1
                name=f'planningCurve_{mode}_{"correction" if residual else "direct"}_p{penalty:g}'
                outputs[name]=p; diagnostics[name]=dict(refits=fits,learnedQueries=learned,fallbackQueries=n-learned,maximumEqualityResidual=maximum_error)
                if progress: progress(name,diagnostics[name])
    return outputs,diagnostics


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','baseline','planning','output']: ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--limit',type=int); args=ap.parse_args(); root=Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root): ap.error('Keep private results outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    app=json.loads(args.baseline.read_text()); prior=json.loads(args.planning.read_text()); digest=sha(args.source)
    assert app['audit']['sourceSHA256']==prior['audit']['sourceSHA256']==digest
    data=dict(np.load(args.features,allow_pickle=False)); n=len(data['y'])
    if args.limit:data={k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in data.items()}
    rows={e['index']:e for e in app['events']}; forecast_rows={e['index']:e for e in prior['events']['pooled_planning']}
    np.testing.assert_allclose([forecast_rows[int(i)]['actual'] for i in data['indices']],data['y'],rtol=0,atol=1e-6)
    forest=np.array([forecast_rows[int(i)]['prediction'] for i in data['indices']]); context=structure(args.source,data,rows,'America/Los_Angeles')
    forecasts,diagnostics=replay(data,context,forest,lambda name,d:print(name,json.dumps(d),flush=True))
    mask=planning_mask(data,context)
    masks=dict(planning=mask,naps=mask&(context['labels']==1),bedtime=mask&(context['labels']==2),allTimers=np.ones(len(mask),bool))
    for lower,upper in [(0,90),(90,180),(180,1000)]:masks[f'planningAge{lower}to{upper}']=mask&(context['X'][:,0]>=lower)&(context['X'][:,0]<upper)
    result=dict(audit=dict(sourceSHA256=digest,scriptSHA256=sha(Path(__file__)),featureSHA256=sha(args.features),planningResultSHA256=sha(args.planning),baselineResultSHA256=sha(args.baseline),
        strategy='Fixed additive age, cyclic clock, completed episode duration, nap order and completed history curves; direct gaps or corrections to originally issued planning forest forecasts.',
        training=dict(lookbackDays=84,halfLifeDays=14,minimumResolvedPlanningLabels=20,refitQueries=24),
        causalRule='Planning membership is used only for scoring and completed training labels; no current outcome routing. Label maturity is target sleep end.',
        optimizer='Sparse HiGHS absolute-loss fit; shared context deviations shrink toward pooled curve. All solves finite and equality error <=1e-6.',
        helperFilesSHA256={name:sha(root/'Scripts'/name) for name in ['research_sleep_behavior_schedule.py','research_sleep_planning.py','research_sleep_timing_curves.py','research_sleep_ensemble.py']},
        sourceURL='https://www.stat.cmu.edu/~ryantibs/papers/additivetf-aos.pdf',
        limitation='Fixed-knot median adaptation, not full data-adaptive squared-loss estimator from the paper. Retrospective selected-history evidence only.',diagnostics=diagnostics),models={},events={})
    for name,p in {'planningForest':forest,**forecasts}.items():
        result['models'][name]={k:metrics(data['y'],p,v) for k,v in masks.items()}
        result['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(data['indices'],data['y'],p)]
        print(name,json.dumps(result['models'][name]['planning']),flush=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')

if __name__=='__main__':main()
