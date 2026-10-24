#!/usr/bin/env python3
"""Past-only continuous fitting of a reduced pressure/clock sleep-onset model."""
import argparse
import ctypes
import hashlib
import json
from pathlib import Path
import numpy as np
from scipy.optimize import minimize
from research_sleep_predictions import load_history
from research_sleep_behavior_schedule import structure
from research_sleep_planning import eligible,planning_mask
from research_sleep_planning_mechanistic import blend_planning
from research_sleep_ensemble import metrics

INITIAL=np.array([np.log(240.),np.log(120.),.7,.1,0.])
BOUNDS=[(np.log(30),np.log(960)),(np.log(15),np.log(480)),(.1,.95),(-.35,.35),(-.35,.35)]


class PressureModel:
    def __init__(self,binary,sleeps,indices,clocks):
        self.library=ctypes.CDLL(str(binary));dp=ctypes.POINTER(ctypes.c_double);ip=ctypes.POINTER(ctypes.c_int32)
        self.library.pressure_create.argtypes=[dp,dp,ctypes.c_int,ip,dp,ctypes.c_int];self.library.pressure_create.restype=ctypes.c_void_p
        self.library.pressure_destroy.argtypes=[ctypes.c_void_p]
        self.library.pressure_evaluate.argtypes=[ctypes.c_void_p,ip,ctypes.c_int,dp,dp,dp,ctypes.c_double,dp,dp]
        self.library.pressure_evaluate.restype=ctypes.c_double
        self.dp=dp;self.ip=ip
        starts=np.ascontiguousarray(sleeps[:,0],dtype=np.float64);ends=np.ascontiguousarray(sleeps[:,1],dtype=np.float64)
        indices=np.ascontiguousarray(indices,dtype=np.int32);clocks=np.ascontiguousarray(clocks,dtype=np.float64)
        self.handle=self.library.pressure_create(starts.ctypes.data_as(dp),ends.ctypes.data_as(dp),len(starts),indices.ctypes.data_as(ip),clocks.ctypes.data_as(dp),len(indices))
        if not self.handle:raise ValueError('Invalid pressure history')

    def close(self):
        if self.handle:self.library.pressure_destroy(self.handle);self.handle=None

    def evaluate(self,positions,params,targets=None,weights=None,penalty=0):
        ix=np.ascontiguousarray(positions,dtype=np.int32);p=np.ascontiguousarray(params,dtype=np.float64)
        if p.shape!=(5,):raise ValueError('Expected five model parameters')
        y=None if targets is None else np.ascontiguousarray(targets,dtype=np.float64)
        w=None if weights is None else np.ascontiguousarray(weights,dtype=np.float64)
        if y is not None and (len(y)!=len(ix) or not np.isfinite(y).all()):raise ValueError('Invalid targets')
        if w is not None and (len(w)!=len(ix) or not np.isfinite(w).all() or np.any(w<0)):raise ValueError('Invalid weights')
        predictions=np.empty(len(ix));states=np.empty(len(ix))
        dp=lambda a:None if a is None else a.ctypes.data_as(self.dp)
        loss=self.library.pressure_evaluate(self.handle,ix.ctypes.data_as(self.ip),len(ix),dp(y),dp(w),dp(p),penalty,dp(predictions),dp(states))
        if not np.isfinite(loss) or not np.isfinite(predictions).all():raise ValueError('Nonfinite pressure evaluation')
        return loss,predictions,states


def replay(data,context,base,native,progress=None,maxfev=400):
    outputs={};diagnostics={}
    for penalty in (0,30):
        name='continuousPressure'+('Risk30' if penalty else 'MAE')
        p=base.copy();params=INITIAL.copy();fitted=-24;ready=False;fits=learned=limited=evals=0
        for i,now in enumerate(data['wakes']):
            known=eligible(data,context,i,True)
            if len(known)<40:continue
            if not ready or i-fitted>=24:
                weights=np.exp2(-(now-data['wakes'][known])/(14*86400))
                def objective(values):return native.evaluate(known,values,data['y'][known],weights,penalty)[0]
                # Always retain the best evaluated point, including the neutral
                # and previous fit. A budget stop is not claimed as convergence.
                best=params.copy();score=objective(best)
                if objective(INITIAL)<score:best=INITIAL.copy();score=objective(best)
                def tracked(values):
                    nonlocal best,score
                    value=objective(values)
                    if value<score:best=values.copy();score=value
                    return value
                result=minimize(tracked,best.copy(),method='Powell',bounds=BOUNDS,
                    options=dict(maxfev=maxfev,xtol=.002,ftol=.0005))
                params=best;ready=True;fitted=i;fits+=1;evals+=result.nfev;limited+=int(not result.success)
                if progress and fits%20==0:progress(name,dict(refits=fits,queries=i+1))
            if 360<=context['wakeClock'][i]<1260:
                p[i]=native.evaluate([i],params)[1][0];learned+=1
        outputs[name]=p;diagnostics[name]=dict(refits=fits,learnedQueries=learned,optimizerNonconvergedFits=limited,optimizerEvaluations=evals)
        if progress:progress(name,diagnostics[name])
    # Fit a weight only on the new MAE model's originally issued predictions.
    for local in (False,True):
        name='continuousPressureBlend'+('Local' if local else 'Global')
        outputs[name],diagnostics[name]=blend_planning(data,context,outputs['continuousPressureMAE'],base,local)
    return outputs,diagnostics


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ('source','features','baseline','binary','output'):ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--limit',type=int);args=ap.parse_args();root=Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root):ap.error('Keep private results outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    app=json.loads(args.baseline.read_text());assert app['audit']['sourceSHA256']==sha(args.source)
    with np.load(args.features,allow_pickle=False) as cache:data=dict(cache)
    n=len(data['y'])
    if args.limit:data={k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in data.items()}
    rows={e['index']:e for e in app['events']};context=structure(args.source,data,rows,'America/Los_Angeles')
    base=(np.array([rows[int(i)]['prediction'] for i in data['indices']])-data['wakes'])/60
    sleeps,_,_,_=load_history(args.source,'1970-01-01','America/Los_Angeles')
    np.testing.assert_array_equal(sleeps[data['indices'].astype(int),1],data['wakes'])
    native=PressureModel(args.binary,sleeps,data['indices'],context['wakeClock'])
    try:forecasts,diag=replay(data,context,base,native,lambda name,d:print(name,json.dumps(d),flush=True))
    finally:native.close()
    masks=dict(planning=planning_mask(data,context),naps=planning_mask(data,context)&(context['labels']==1),bedtime=planning_mask(data,context)&(context['labels']==2),allTimers=np.ones(len(base),bool))
    result=dict(audit=dict(sourceSHA256=sha(args.source),scriptSHA256=sha(Path(__file__)),featureSHA256=sha(args.features),baselineSHA256=sha(args.baseline),binarySHA256=sha(args.binary),coreSHA256=sha(root/'Scripts/SleepReplay/PlanningPressureFit.cpp'),
        helperSHA256={name:sha(root/'Scripts'/name) for name in ('research_sleep_predictions.py','research_sleep_behavior_schedule.py','research_sleep_planning.py','research_sleep_planning_mechanistic.py','research_sleep_ensemble.py')},
        diagnostics=diag,initialParameters=INITIAL.tolist(),parameterBounds=BOUNDS,
        training=dict(days=60,halfLifeDays=14,minimumResolvedPlanningLabels=40,refitQueries=24,optimizerMaxEvaluations=400),
        strategy='Fit two continuous exponential time constants and threshold intercept/sine/cosine coefficients to resolved planning onset errors. Pressure states integrate completed raw sleep unions before each historical wake only. First crossing on one-minute brackets with interpolation; MAE or MAE+30*miss30 loss.',
        limitation='Independent reduced model, not full neuronal-state fitting, measured physiology, or the published weekly likelihood fit. Bounded local optimization may not converge; best evaluated points retained. Clock phase advances by elapsed time from known wake clock. Retrospective archive-selected replay only.'),models={},events={})
    for name,p in dict(appV8=base,**forecasts).items():
        result['models'][name]={key:metrics(data['y'],p,m) for key,m in masks.items()}
        result['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(data['indices'],data['y'],p)]
        print(name,json.dumps(result['models'][name]['planning']),flush=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')


if __name__=='__main__':main()
