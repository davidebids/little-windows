#!/usr/bin/env python3
"""Exact finite-location filtering with matched normal/heavy-tail observations."""
import argparse
import hashlib
import json
import time
from pathlib import Path
import numpy as np
from scipy.special import gammaln, logsumexp, ndtr, stdtr
from scipy.optimize import brentq
from research_sleep_changepoints import calendar_hazard, groups
from research_sleep_ensemble import combine, metrics


def observation_logpdf(delta, family, sd=60.):
    if family == 'normal':
        z = np.asarray(delta)/sd
        return -.5*z*z-np.log(sd*np.sqrt(2*np.pi))
    if family == 'laplace':
        scale = sd/np.sqrt(2.)
        return -np.abs(delta)/scale-np.log(2*scale)
    if family == 'student3':
        scale = sd/np.sqrt(3.); z = np.asarray(delta)/scale
        return gammaln(2.)-gammaln(1.5)-.5*np.log(3*np.pi)-np.log(scale)-2*np.log1p(z*z/3)
    raise ValueError('Unknown observation family')


def observation_cdf(delta, family, sd=60.):
    if family == 'normal': return ndtr(np.asarray(delta)/sd)
    if family == 'student3': return stdtr(3.,np.asarray(delta)/(sd/np.sqrt(3.)))
    if family == 'laplace':
        z = np.asarray(delta)/(sd/np.sqrt(2.)); half = .5*np.exp(-np.abs(z))
        return np.where(z<0,half,1-half)
    raise ValueError('Unknown observation family')


class LocationFilter:
    """Marginalize run length exactly for a fixed discrete reset-location prior."""
    def __init__(self, family, grid=None, sd=60., prior_scale=60.):
        self.grid = np.arange(-480.,481.) if grid is None else np.asarray(grid,dtype=float)
        if self.grid.ndim != 1 or not len(self.grid) or not np.isfinite(self.grid).all() or np.any(np.diff(self.grid)<=0):
            raise ValueError('Ordered finite location grid required')
        if sd<=0 or prior_scale<=0 or not np.isfinite([sd,prior_scale]).all(): raise ValueError('Invalid scales')
        observation_logpdf(0.,family,sd)
        self.family, self.sd = family, sd
        self.logprior = -np.abs(self.grid)/prior_scale
        self.logprior -= logsumexp(self.logprior)
        self.logp = self.logprior.copy(); self.count = 0

    def transition(self, hazard):
        if not 0<=hazard<1: raise ValueError('Invalid hazard')
        if not hazard: return self.logp.copy()
        return np.logaddexp(self.logp+np.log1p(-hazard),self.logprior+np.log(hazard))

    def update(self, value, hazard):
        if not np.isfinite(value): raise ValueError('Finite observation required')
        messages = self.transition(hazard)+observation_logpdf(value-self.grid,self.family,self.sd)
        self.logp = messages-logsumexp(messages); self.count += 1

    def locations(self, idle=0.):
        logw = self.transition(idle); logw -= logsumexp(logw); w = np.exp(logw)
        mean = float(w@self.grid)
        lo,hi = float(self.grid[0]),float(self.grid[-1])
        if lo==hi: return mean,lo
        point = brentq(lambda x:float(w@observation_cdf(x-self.grid,self.family,self.sd)-.5),lo,hi,xtol=1e-7,rtol=1e-12)
        return mean,float(point)


def replay(data,base,progress=None):
    output,diagnostics = {},{}; n=len(base)
    for kind in ['global','night','roles']:
        group=groups(data,kind)
        for family in ['normal','laplace','student3']:
            for days in [None,7,28]:
                states,last,seen={},{},set(); pred={k:base.copy() for k in ['locationMean','predictiveMedian']}
                learned=updates=0; maximum_error=0.
                for i,now in enumerate(data['wakes']):
                    known=np.flatnonzero((np.arange(n)<i)&(data['available']<=now))
                    for j in sorted((int(j) for j in known if int(j) not in seen),key=lambda j:(data['available'][j],j)):
                        g=int(group[j]); at=float(data['available'][j]); state=states.setdefault(g,LocationFilter(family))
                        state.update(float(data['y'][j]-base[j]),calendar_hazard(at-last[g],days) if g in last else 0.)
                        last[g]=at; seen.add(j); updates+=1
                        maximum_error=max(maximum_error,abs(float(np.exp(state.logp).sum())-1))
                    g=int(group[i]); state=states.setdefault(g,LocationFilter(family))
                    points=state.locations(calendar_hazard(now-last[g],days) if g in last else 0.)
                    if state.count: learned+=1
                    for key,point in zip(pred,points): pred[key][i]=np.clip(base[i]+point,1,480)
                name=f'robustFilter_{kind}_{family}_h{days if days is not None else "none"}'
                output.update({name+'_'+key:p for key,p in pred.items()})
                diagnostics[name]=dict(updatedLabels=updates,learnedQueries=learned,priorOnlyQueries=n-learned,streams=len(states),maximumNormalizationError=maximum_error)
                if progress: progress(name,diagnostics[name])
    members=np.column_stack([base,*output.values()])
    for name,policy,cal,local in [('localCalibratedSoft','soft',True,True),('localCalibratedBest','best',True,True),
            ('localRawSoft','soft',False,True),('globalCalibratedSoft','soft',True,False),('calibratedMedian','median',True,True)]:
        output['robustFilterCombination_'+name]=combine(data,members,policy,cal,local)
    return output,diagnostics


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','baseline','output']: ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--limit',type=int); args=ap.parse_args(); root=Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root): ap.error('Keep private forecasts outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    data=dict(np.load(args.features,allow_pickle=False)); n=len(data['y'])
    if args.limit: data={k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in data.items()}
    baseline=json.loads(args.baseline.read_text()); assert baseline['audit']['sourceSHA256']==sha(args.source)
    rows={e['index']:e for e in baseline['events']}
    np.testing.assert_allclose([rows[int(i)]['actual'] for i in data['indices']],data['available'],rtol=0,atol=1e-6)
    np.testing.assert_allclose([rows[int(i)]['wakeMinutes'] for i in data['indices']],data['y'],rtol=0,atol=1e-6)
    base=(np.array([rows[int(i)]['prediction'] for i in data['indices']])-data['wakes'])/60
    started=time.monotonic()
    def progress(name,diag): print(json.dumps(dict(candidate=name,**diag,seconds=time.monotonic()-started)),flush=True)
    forecasts,diag=replay(data,base,progress)
    result=dict(audit=dict(sourceSHA256=sha(args.source),featureCacheSHA256=sha(args.features),baselineResultSHA256=sha(args.baseline),scriptSHA256=sha(Path(__file__)),
        helperFilesSHA256={name:sha(root/'Scripts'/name) for name in ['research_sleep_changepoints.py','research_sleep_ensemble.py']},careExposure='completed',
        locationGrid=dict(minimum=-480,maximum=480,step=1,points=961,prior='Discrete Laplace weights with scale60'),
        observationModels=dict(families=['normal','laplace','student3'],commonSDMinutes=60,normalScale=60,laplaceScale=60/np.sqrt(2),student3Scale=60/np.sqrt(3),studentDF=3),
        transition='Before-observation reset to fixed prior with none/7/28-day calendar hazard; independent global/night/role streams; forecast idle prior mixture',
        inference='Exact finite-location forward filter, analytically marginalizing all run lengths; no state pruning, sample minimum or removed observations',
        decisions='Posterior location mean and numerical predictive-mixture median; additive residual against issued baseline, planning bounds1..480',diagnostics=diag,
        limitation='Independent ordinary-Bayes finite-state likelihood experiment, not the cited diffusion-score-matching generalised Bayes method or infant accuracy claim; retrospective only',
        sourceURLs=['https://arxiv.org/abs/0710.3742','https://arxiv.org/abs/2302.04759','https://docs.scipy.org/doc/scipy/reference/generated/scipy.stats.laplace.html','https://docs.scipy.org/doc/scipy/reference/generated/scipy.stats.t.html']),models={},events={})
    for name,p in forecasts.items():
        assert np.isfinite(p).all()
        result['models'][name]=dict(all=metrics(data['y'],p,np.ones(len(p),dtype=bool)))
        result['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(data['indices'],data['y'],p)]
        print(name,json.dumps(result['models'][name]),flush=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')


if __name__=='__main__': main()
