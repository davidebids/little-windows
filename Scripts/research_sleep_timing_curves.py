#!/usr/bin/env python3
"""Past-only regularized additive median timing curves by known wake context."""
import argparse
import hashlib
import json
import time
from pathlib import Path
import numpy as np
from scipy import sparse
from scipy.optimize import linprog
from research_sleep_behavior_schedule import structure
from research_sleep_ensemble import metrics


def basis(context):
    x=context['X']; n=len(x); columns=[np.ones(n)]; penalties=[]
    def linear_hinges(value,knots):
        columns.append(value); penalties.append((len(columns)-1,.01))
        for knot in knots:
            columns.append(np.maximum(value-knot,0.)); penalties.append((len(columns)-1,1.))
    linear_hinges(x[:,0]/180,np.arange(30,271,30)/180)
    phase=np.mod(context['wakeClock'],1440)/180
    nodes=np.arange(8); distance=np.abs((phase[:,None]-nodes+4)%8-4)
    tents=np.maximum(1-distance,0.)
    clock_indices=[]
    for node in range(1,8): columns.append(tents[:,node]); clock_indices.append(len(columns)-1)
    scale=np.log1p(120.)
    linear_hinges(np.log1p(x[:,5])/scale,np.log1p([20.,40.,60.,90.,120.,240.])/scale)
    linear_hinges(context['ordinal']/3,np.arange(1,6)/3)
    for value in [np.log1p(x[:,4])/scale,np.log1p(x[:,6])/np.log(4),x[:,3],np.log1p(np.maximum(x[:,8],0))/scale,x[:,9]/360,x[:,10]/1440]:
        columns.append(value); penalties.append((len(columns)-1,.01))
    X=np.column_stack(columns); p=X.shape[1]; rows=[]
    for index,weight in penalties:
        row=np.zeros(p); row[index]=weight; rows.append(row)
    # Clock node zero is anchored at zero; intercept carries the common level.
    for node in range(8):
        row=np.zeros(p)
        for neighbor,coefficient in [((node-1)%8,1),(node,-2),((node+1)%8,1)]:
            if neighbor: row[clock_indices[neighbor-1]]+=coefficient
        rows.append(row)
    for index in range(1,p):
        row=np.zeros(p); row[index]=1e-4; rows.append(row)
    return X,np.asarray(rows)


def fit_median(X,y,weights,D,penalty):
    weights=np.asarray(weights,dtype=float); weights=weights/weights.sum(); n,p=X.shape; m=len(D)
    identity=sparse.eye(n,format='csr'); regularizer=sparse.eye(m,format='csr')
    constraints=sparse.vstack([
        sparse.hstack([sparse.csr_matrix(X),identity,-identity,sparse.csr_matrix((n,2*m))]),
        sparse.hstack([sparse.csr_matrix(D),sparse.csr_matrix((m,2*n)),-regularizer,regularizer])],format='csr')
    objective=np.r_[np.zeros(p),weights,weights,np.full(2*m,penalty)]
    target=np.r_[y,np.zeros(m)]
    result=linprog(objective,A_eq=constraints,b_eq=target,bounds=[(None,None)]*p+[(0,None)]*(2*n+2*m),method='highs-ds')
    if not result.success or not np.isfinite(result.x).all(): raise RuntimeError('Median curve solver failed: '+result.message)
    residual=float(np.max(abs(constraints@result.x-target)))
    if residual>1e-6: raise RuntimeError('Median curve equality tolerance failed')
    return result.x[:p],residual


def wake_groups(context,separate):
    clock=context['wakeClock']; last_night=context['X'][:,3]>0
    if not separate: return np.zeros(len(clock),dtype=int)
    return np.where((clock<360)|(clock>=1260),0,np.where(last_night&(clock<720),1,np.where(clock<960,2,3)))


def curve_design(context,mode):
    X,D=basis(context)
    if mode!='shared': return X,D,wake_groups(context,mode=='contexts')
    groups=wake_groups(context,True); p=X.shape[1]
    design=np.column_stack([X,*[X*(groups==group)[:,None] for group in range(4)]])
    penalty=sparse.block_diag([D,*[4*D for _ in range(4)]],format='csr').toarray()
    shrink=np.column_stack([np.zeros((4*p,p)),.1*np.eye(4*p)])
    return design,np.vstack([penalty,shrink]),np.zeros(len(X),dtype=int)


def replay(data,context,base,progress=None):
    n=len(base); outputs={}; diagnostics={}
    for mode in ['pooled','contexts','shared']:
        X,D,groups=curve_design(context,mode)
        for residual in [False,True]:
            for penalty in [.05,.5]:
                p=base.copy(); models={}; fitted={}; fits=learned=0; maximum_error=0.
                for i,now in enumerate(data['wakes']):
                    group=int(groups[i]); known=np.flatnonzero((np.arange(n)<i)&(data['available']<=now)&(data['wakes']>=now-84*86400)&(groups==group))
                    if len(known)<20: continue
                    if group not in models or i-fitted[group]>=24:
                        weights=np.exp2(-(now-data['wakes'][known])/(14*86400))
                        target=data['y'][known]-(base[known] if residual else 0.)
                        models[group],error=fit_median(X[known],target,weights,D,penalty)
                        maximum_error=max(maximum_error,error); fitted[group]=i; fits+=1
                    point=float(X[i]@models[group])+(base[i] if residual else 0.)
                    p[i]=np.clip(point,1,480); learned+=1
                name=f'timingCurve_{mode}_{"residual" if residual else "direct"}_p{penalty:g}'
                outputs[name]=p; diagnostics[name]=dict(refits=fits,learnedQueries=learned,fallbackQueries=n-learned,featureCount=X.shape[1],penaltyRows=len(D),maximumEqualityResidual=maximum_error)
                if progress: progress(name,diagnostics[name])
    return outputs,diagnostics


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','baseline','output']: ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--zone',default='America/Los_Angeles'); ap.add_argument('--limit',type=int); args=ap.parse_args(); root=Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root): ap.error('Keep private forecasts outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    baseline=json.loads(args.baseline.read_text()); assert baseline['audit']['sourceSHA256']==sha(args.source)
    rows={e['index']:e for e in baseline['events']}; data=dict(np.load(args.features,allow_pickle=False)); n=len(data['y'])
    if args.limit: data={k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in data.items()}
    np.testing.assert_allclose([rows[int(i)]['wakeMinutes'] for i in data['indices']],data['y'],rtol=0,atol=1e-6)
    base=(np.array([rows[int(i)]['prediction'] for i in data['indices']])-data['wakes'])/60
    context=structure(args.source,data,rows,args.zone); started=time.monotonic()
    def progress(name,diag): print(json.dumps(dict(candidate=name,**diag,seconds=time.monotonic()-started)),flush=True)
    forecasts,diag=replay(data,context,base,progress)
    result=dict(audit=dict(sourceSHA256=sha(args.source),featureCacheSHA256=sha(args.features),baselineResultSHA256=sha(args.baseline),scriptSHA256=sha(Path(__file__)),
        helperFilesSHA256={name:sha(root/'Scripts'/name) for name in ['research_sleep_behavior_schedule.py','research_sleep_ensemble.py']},careExposure='completed',
        strategy='Regularized additive conditional-median timing curves, pooled versus four independent known-wake contexts versus shared base plus shrunk context deviations; direct times or corrections to issued app',
        basis='Age linear hinges every30days through270 scaled180; cyclic3hour linear clock tents; log completed-episode duration knots20/40/60/90/120/240; logical nap ordinal hinges1..5; fixed linear completed-history summaries',
        penalty='Weighted mean absolute residual plus alpha times L1 hinge slope changes and cyclic clock second differences; small linear-slope and coefficient penalties. Shared context deviations use four-times base curvature penalty plus0.1 L1 coefficient shrinkage. No imposed monotonic age rule.',
        penaltyValues=[.05,.5],training=dict(historyDays=84,halfLifeDays=14,minimumLabelsPerContext=20,refitEveryQueries=24),
        contexts='Overnight21..06; prior-night wake before12; other daytime before16; remaining late-day. All group selection is known at wake, not the next sleep type.',
        optimizer='Sparse HiGHS dual simplex; all fits must succeed with finite coefficients and equality error<=1e-6',diagnostics=diag,
        sourceURLs=['https://www.stat.cmu.edu/~ryantibs/papers/additivetf-aos.pdf','https://scikit-learn.org/stable/modules/generated/sklearn.linear_model.QuantileRegressor.html'],
        limitation='Independent fixed-knot additive absolute-loss adaptation, not the paper full data-adaptive trend-filtering estimator or infant formula; post-selected retrospective archive comparison only'),models={},events={})
    for name,p in forecasts.items():
        result['models'][name]=dict(all=metrics(data['y'],p,np.ones(len(p),dtype=bool)))
        result['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(data['indices'],data['y'],p)]
        print(name,json.dumps(result['models'][name]),flush=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')


if __name__=='__main__': main()
