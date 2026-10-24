#!/usr/bin/env python3
"""Causal run-length filtering of issued sleep-prediction residuals."""
import argparse
import hashlib
import json
import math
import time
from pathlib import Path
import numpy as np
from scipy.special import gammaln,logsumexp,stdtr
from scipy.optimize import brentq
from research_sleep_ensemble import combine,metrics


class RunLengthModel:
    """Unpruned BOCPD messages with normal-inverse-gamma sufficient statistics."""
    def __init__(self,prior_sd,reset_before=False):
        self.prior=(0.,.5,2.,prior_sd**2/3)
        self.mu,self.kappa,self.alpha,self.beta=[np.array([v]) for v in self.prior]
        self.logp=np.array([0.]);self.count=0;self.reset_before=reset_before

    def log_density(self,value):
        df=2*self.alpha;scale2=self.beta*(self.kappa+1)/(self.alpha*self.kappa)
        return gammaln((df+1)/2)-gammaln(df/2)-.5*np.log(df*np.pi*scale2)-(df+1)/2*np.log1p((value-self.mu)**2/(df*scale2))

    def update(self,value,hazard):
        if not np.isfinite(value) or not 0<=hazard<1:raise ValueError('Invalid observation or hazard')
        joint=self.logp+self.log_density(value)
        if self.reset_before:
            reset=self.log_density(value)[0]+np.log(hazard) if hazard else -np.inf
            first=np.logaddexp(reset,joint[0]+np.log1p(-hazard))
            messages=np.r_[-np.inf,first,joint[1:]+np.log1p(-hazard)]
        else:
            reset=logsumexp(joint)+np.log(hazard) if hazard else -np.inf
            messages=np.r_[reset,joint+np.log1p(-hazard)]
        self.logp=messages-logsumexp(messages)
        old_mu=self.mu.copy();old_k=self.kappa.copy()
        self.mu=np.r_[self.prior[0],(old_k*old_mu+value)/(old_k+1)]
        self.kappa=np.r_[self.prior[1],old_k+1]
        self.alpha=np.r_[self.prior[2],self.alpha+.5]
        self.beta=np.r_[self.prior[3],self.beta+old_k*(value-old_mu)**2/(2*(old_k+1))]
        self.count+=1

    def locations(self,idle_hazard=0.,median=True):
        if not 0<=idle_hazard<1:raise ValueError('Invalid idle hazard')
        weights=np.exp(self.logp)*(1-idle_hazard);weights[0]+=idle_hazard;weights/=weights.sum()
        mean=float(weights@self.mu)
        if not median:return mean,None
        active=weights>0;w=weights[active];mu=self.mu[active];df=2*self.alpha[active]
        scale=np.sqrt(self.beta[active]*(self.kappa[active]+1)/(self.alpha[active]*self.kappa[active]))
        lower,upper=float(min(mu)),float(max(mu))
        if lower==upper:return mean,lower
        cdf=lambda x:float(w@stdtr(df,(x-mu)/scale)-.5)
        point=float(brentq(cdf,lower,upper,xtol=1e-7,rtol=1e-12))
        return mean,point


def groups(data,kind):
    names=list(data['names']);X=data['X']
    if kind=='global':return np.zeros(len(X),dtype=int)
    night=X[:,names.index('lastNight')]>0
    if kind=='night':return night.astype(int)
    clock=np.mod(np.arctan2(X[:,names.index('clockSin1')],X[:,names.index('clockCos1')]),2*np.pi)*1440/(2*np.pi)
    clock=np.mod(np.round(clock,9),1440)
    overnight=(clock<360)|(clock>=1260);naps=X[:,names.index('napsToday')]
    return np.where(overnight,0,np.where(night,1,np.where(naps<2,2,3)))


def calendar_hazard(elapsed,days):
    if days is None or elapsed<=0:return 0.
    return float(min(1-1e-12,-np.expm1(-elapsed/(days*86400))))


def replay(data,base,progress=None,reset_before=False):
    output,diagnostics={},{};n=len(base)
    for kind in ['global','night','roles']:
        group=groups(data,kind)
        for transform in ['offset','logRatio']:
            for days in [None,7,28]:
                states={};last={};seen=set();pred={key:base.copy() for key in (['locationMean'] if days is None else ['locationMean','predictiveMedian'])};learned=0;updates=0;maximum_normalization_error=0.
                for i,now in enumerate(data['wakes']):
                    known=np.flatnonzero((np.arange(n)<i)&(data['available']<=now))
                    pending=sorted((int(j) for j in known if int(j) not in seen),key=lambda j:(data['available'][j],j))
                    for j in pending:
                        g=int(group[j]);at=float(data['available'][j]);model=states.setdefault(g,RunLengthModel(60. if transform=='offset' else .75,reset_before))
                        h=calendar_hazard(at-last[g],days) if g in last else 0.
                        value=float(data['y'][j]-base[j]) if transform=='offset' else math.log(float(data['y'][j])/float(base[j]))
                        model.update(value,h);last[g]=at;seen.add(j);updates+=1
                        maximum_normalization_error=max(maximum_normalization_error,abs(float(np.exp(model.logp).sum())-1))
                    g=int(group[i]);model=states.setdefault(g,RunLengthModel(60. if transform=='offset' else .75,reset_before))
                    idle=calendar_hazard(now-last[g],days) if g in last else 0.
                    mean,median=model.locations(idle,median=days is not None)
                    if model.count:learned+=1
                    for key,value in [('locationMean',mean),('predictiveMedian',median)]:
                        if key not in pred:continue
                        point=base[i]+value if transform=='offset' else base[i]*np.exp(value)
                        pred[key][i]=np.clip(point,1,480)
                name=f'changePoint_{kind}_{transform}_h{days if days is not None else "none"}'
                output.update({name+'_'+key:p for key,p in pred.items()})
                diagnostics[name]=dict(updatedLabels=updates,learnedQueries=learned,priorOnlyQueries=n-learned,streams=len(states),maximumNormalizationError=maximum_normalization_error,maximumStreamObservations=max(v.count for v in states.values()))
                if progress:progress(name,diagnostics[name])
    members=np.column_stack([base,*output.values()])
    for name,policy,cal,local in [('localCalibratedSoft','soft',True,True),('localCalibratedBest','best',True,True),
        ('localRawSoft','soft',False,True),('globalCalibratedSoft','soft',True,False),('calibratedMedian','median',True,True)]:
        output['changePointCombination_'+name]=combine(data,members,policy,cal,local)
    return output,diagnostics


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','baseline','output']:ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--limit',type=int);ap.add_argument('--reset-before',action='store_true')
    args=ap.parse_args();root=Path(__file__).resolve().parents[1];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    if args.output.resolve().is_relative_to(root):ap.error('Keep private forecasts outside source')
    d=dict(np.load(args.features,allow_pickle=False));n=len(d['y'])
    if args.limit:d={k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in d.items()}
    baseline=json.loads(args.baseline.read_text());assert baseline['audit']['sourceSHA256']==sha(args.source);rows={r['index']:r for r in baseline['events']}
    np.testing.assert_allclose([rows[int(i)]['actual'] for i in d['indices']],d['available'],rtol=0,atol=1e-6)
    np.testing.assert_allclose([rows[int(i)]['wakeMinutes'] for i in d['indices']],d['y'],rtol=0,atol=1e-6)
    base=(np.array([rows[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60;start=time.monotonic()
    def progress(name,diag):print(json.dumps(dict(candidate=name,**diag,seconds=time.monotonic()-start)),flush=True)
    forecasts,diag=replay(d,base,progress,reset_before=args.reset_before)
    r=dict(audit=dict(sourceSHA256=sha(args.source),featureCacheSHA256=sha(args.features),baselineResultSHA256=sha(args.baseline),scriptSHA256=sha(Path(__file__)),helperFilesSHA256={'research_sleep_ensemble.py':sha(root/'Scripts/research_sleep_ensemble.py')},
        careExposure='completed',hazardDays=[None,7,28],history='All prior resolved labels in arrival order; no run-length pruning',groups=['global','night','roles'],transforms=['offset','logRatio'],
        prior=dict(mu=0,kappa=.5,alpha=2,offsetPredictiveSDMinutes=60,logRatioPredictiveSD=.75,betaRule='predictiveSD squared / 3'),
        resetTiming='before observation, conditioned on its prior predictive' if args.reset_before else 'paper post-observation reset; previous elapsed gap is a step-hazard proxy',
        diagnostics=diag,rule='NIG Student-t run-length components; exponential elapsed-gap hazard plus idle forecast mixture; reset placement stated separately; no current label',
        decisions='Posterior component-location mean; exact predictive-mixture median via CDF root. In log space, exponentiated location mean is a geometric center, not arithmetic duration mean',
        limitation='Independent calendar/context adaptation of general change-point method; not a paper sleep replication, physiological state inference or independent future validation',
        sourceURLs=['https://arxiv.org/abs/0710.3742','https://docs.scipy.org/doc/scipy/reference/generated/scipy.stats.normal_inverse_gamma.html']),models={},events={})
    for name,p in forecasts.items():
        assert np.isfinite(p).all();r['models'][name]=dict(all=metrics(d['y'],p,np.ones(len(p),dtype=bool)))
        r['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(d['indices'],d['y'],p)]
        print(name,json.dumps(r['models'][name]),flush=True)
    args.output.write_text(json.dumps(r,indent=2,allow_nan=False)+'\n')


if __name__=='__main__':main()
