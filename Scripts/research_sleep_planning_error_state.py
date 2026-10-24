#!/usr/bin/env python3
"""Causal schedule-error states over previously issued planning forecasts."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from scipy.linalg import cho_factor,cho_solve
from scipy.optimize import minimize
from research_sleep_behavior_schedule import structure
from research_sleep_planning import eligible,planning_mask
from research_sleep_ensemble import metrics


def kernels(times,queries=None):
    other=times if queries is None else queries
    distance=abs(np.asarray(times)[:,None]-np.asarray(other)[None,:])/3600
    return np.stack([np.exp(-distance/6),np.exp(-distance/72)])


def fit_state(times,residuals):
    """Two stationary OU components; zero-state nested model always available.

    Parameter selection uses marginal Gaussian likelihood of clipped, already
    resolved prequential residuals. Clipping is a robust research adaptation.
    """
    t=np.asarray(times,float);y=np.clip(np.asarray(residuals,float),-90,90)
    if len(t)<12 or len(t)!=len(y) or not np.isfinite(t).all() or not np.isfinite(y).all():
        raise ValueError('Need at least twelve finite resolved residuals')
    K=kernels(t);identity=np.eye(len(t));mean=float(y.mean());noise=max(25.,float(np.mean((y-mean)**2)))
    def objective(params):
        mu,qfast,qslow,r=params;C=qfast*K[0]+qslow*K[1]+r*identity
        factor=cho_factor(C,lower=True,check_finite=False);z=y-mu;alpha=cho_solve(factor,z,check_finite=False)
        value=.5*(z@alpha+2*np.log(np.diag(factor[0])).sum())
        inv=cho_solve(factor,identity,check_finite=False);G=inv-np.outer(alpha,alpha)
        gradient=np.array([-alpha.sum(),.5*np.sum(G*K[0]),.5*np.sum(G*K[1]),.5*np.trace(G)])
        return float(value),gradient
    null=np.array([mean,0.,0.,noise]);null_loss,_=objective(null)
    fitted=minimize(objective,[mean,noise*.05,noise*.05,noise*.9],jac=True,method='L-BFGS-B',
        bounds=[(-90,90),(0,32400),(0,32400),(25,32400)],options=dict(maxiter=80,ftol=1e-10))
    if not np.isfinite(fitted.fun) or not np.isfinite(fitted.x).all():raise RuntimeError('Nonfinite state fit')
    chosen=fitted.x if fitted.success and fitted.fun<null_loss else null
    return chosen,dict(optimizerSuccess=bool(fitted.success),nullSelected=bool(np.array_equal(chosen,null)),
        iterations=int(fitted.nit),loss=float(min(fitted.fun,null_loss)) if fitted.success else float(null_loss))


def correction(params,times,residuals,now):
    mu,qfast,qslow,noise=np.asarray(params,float);y=np.clip(np.asarray(residuals,float),-90,90)
    if not len(y):return float(mu)
    K=kernels(times);C=qfast*K[0]+qslow*K[1]+noise*np.eye(len(y))
    alpha=cho_solve(cho_factor(C,lower=True,check_finite=False),y-mu,check_finite=False)
    cross=kernels(times,[now])[:,:,0]
    value=float(mu+(qfast*cross[0]+qslow*cross[1])@alpha)
    if not np.isfinite(value):raise RuntimeError('Nonfinite filtered correction')
    return value


def replay(data,context,issued,progress=None):
    n=len(issued);out={name:issued.copy() for name in ['resolvedBiasControl','transientErrorState']}
    residuals=data['y']-issued;params=None;fitted=-24;fits=[];adjusted=0
    for i,now in enumerate(data['wakes']):
        known=eligible(data,context,i,True)
        if len(known)<12:continue
        if params is None or i-fitted>=24:
            params,info=fit_state(data['wakes'][known],residuals[known]);bias=float(np.clip(residuals[known],-90,90).mean())
            fitted=i;entry=dict(query=i,labels=len(known),parameters=params.tolist(),**info);fits.append(entry)
            if progress:progress(entry)
        out['resolvedBiasControl'][i]=np.clip(issued[i]+bias,1,480)
        shift=correction(params,data['wakes'][known],residuals[known],now)
        out['transientErrorState'][i]=np.clip(issued[i]+shift,1,480);adjusted+=1
    return out,dict(refits=fits,adjustedQueries=adjusted)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for key in ['source','features','baseline','issued','output']:ap.add_argument('--'+key,type=Path,required=True)
    ap.add_argument('--limit',type=int);a=ap.parse_args();root=Path(__file__).resolve().parents[1]
    if a.output.resolve().is_relative_to(root):ap.error('Keep private results outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    app=json.loads(a.baseline.read_text());issued=json.loads(a.issued.read_text())
    assert app['audit']['sourceSHA256']==issued['audit']['sourceSHA256']==sha(a.source)
    with np.load(a.features,allow_pickle=False) as f:d=dict(f)
    n=len(d['y'])
    if a.limit:d={k:v[:a.limit] if v.ndim and len(v)==n else v for k,v in d.items()}
    rows={e['index']:e for e in app['events']};c=structure(a.source,d,rows,'America/Los_Angeles')
    base=(np.array([rows[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60
    by={e['index']:e for e in issued['events']['planningForestControl']}
    np.testing.assert_array_equal([by[int(i)]['actual'] for i in d['indices']],d['y'])
    p=np.array([by[int(i)]['prediction'] for i in d['indices']]);out,diag=replay(d,c,p,lambda row:print(json.dumps(row),flush=True))
    m=planning_mask(d,c);masks=dict(planning=m,naps=m&(c['labels']==1),bedtime=m&(c['labels']==2),allTimers=np.ones(len(m),bool))
    result=dict(audit=dict(sourceSHA256=sha(a.source),scriptSHA256=sha(Path(__file__)),
        inputsSHA256={k:sha(getattr(a,k)) for k in ['features','baseline','issued']},
        helperSHA256={k:sha(root/'Scripts'/k) for k in ['research_sleep_behavior_schedule.py','research_sleep_planning.py','research_sleep_ensemble.py']},
        strategy='Two independent stationary OU residual states with6h/72h timescales plus constant mean/noise; variances learned by past-only marginal likelihood. Prequential errors clipped90min. Nested no-state fit included. Minimum12 mature labels,60day history,24-query parameter refit, all newly resolved labels condition each query.',
        causalRule='Use original issued forest points, never in-sample refitted errors. Training type/gap only after target END. Current/future target never routes or updates a state. Full/prefix issued source must be independently validated.',
        sourceURL='https://www.statsmodels.org/stable/statespace.html',diagnostics=diag,
        limitation='Independent irregular-time covariance implementation of linear Gaussian states with robust clipping, not an infant-specific published result. All-clock planning research, not overnight-return integration. Retrospective archive-selected comparisons.'),models={},events={})
    for name,v in dict(appV8=base,planningForestControl=p,**out).items():
        result['models'][name]={k:metrics(d['y'],v,mask) for k,mask in masks.items()}
        result['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(pred)) for i,y,pred in zip(d['indices'],d['y'],v)]
        print(name,json.dumps(result['models'][name]['planning']),flush=True)
    a.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')

if __name__=='__main__':main()
