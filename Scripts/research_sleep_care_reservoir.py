#!/usr/bin/env python3
"""Frozen finite-window reservoirs with regularized causal mean/median readouts."""
import argparse
import hashlib
import json
import time
import warnings
from pathlib import Path
import numpy as np
from scipy import sparse
from scipy.optimize import linprog,OptimizeWarning
from threadpoolctl import threadpool_limits
from research_sleep_care_alignment import care_patterns
from research_sleep_care_signatures import read_marks
from research_sleep_sequence_head import fit_ridge,predict_ridge
from research_sleep_ensemble import combine,metrics,weighted_median


def reservoir_weights(width=64,seed=42):
    rng=np.random.default_rng(seed)
    q,_=np.linalg.qr(rng.normal(size=(width,width)))
    recurrent=.9*q
    inputs=rng.normal(scale=.5/np.sqrt(11),size=(width,11))
    bias=rng.normal(scale=.1,size=width)
    return recurrent,inputs,bias


def encode_patterns(patterns,weights=None):
    W,U,b=reservoir_weights() if weights is None else weights
    valid=np.isfinite(patterns).all(axis=(1,2));u=patterns.copy()
    u[:,:,:8]/=np.sqrt(2);u[:,:,8:]/=4
    result={'context':np.zeros((len(u),1)), 'pooled':np.mean(u,axis=1)}
    for leak in [.3,1.]:
        # Query-local arithmetic also makes the numerical representation
        # independent of the number of future queries in an offline replay.
        output=np.full((len(u),len(b)),np.nan)
        for i in np.flatnonzero(valid):
            state=np.zeros(len(b))
            for value in u[i]:state=(1-leak)*state+leak*np.tanh(W@state+U@value+b)
            output[i]=state
        result[f'reservoir_l{leak:g}']=output
    for output in result.values():output[~valid]=np.nan
    return result


def scaled_blocks(latent,context,weights):
    blocks,scalers=[],[]
    for x in [latent,context]:
        finite=np.isfinite(x);den=np.sum(finite*weights[:,None],axis=0)
        mean=np.divide(np.sum(np.where(finite,x,0)*weights[:,None],axis=0),den,out=np.zeros(x.shape[1]),where=den>0)
        x=np.where(finite,x,mean);scale=np.maximum(np.sqrt(np.average((x-mean)**2,axis=0,weights=weights)),1e-3)*np.sqrt(x.shape[1])
        blocks.append((x-mean)/scale);scalers.append((mean,scale))
    return np.column_stack(blocks),scalers


def fit_lad(latent,context,target,weights,penalty):
    X,scalers=scaled_blocks(latent,context,weights);design=np.column_stack([np.ones(len(X)),X]);d=sparse.csr_matrix(design);identity=sparse.eye(len(X),format='csr')
    constraint=sparse.hstack([d,-d,identity,-identity],format='csr')
    regularization=np.r_[0.,np.full(X.shape[1],penalty)];objective=np.r_[regularization,regularization,weights/weights.sum(),weights/weights.sum()]
    centers=[];coefficients=[];residuals=[]
    for column in target.T:
        center=float(weighted_median(column,weights));y=(column-center)/60
        with warnings.catch_warnings():
            warnings.filterwarnings('ignore',message='Unrecognized options detected',category=OptimizeWarning)
            fit=linprog(objective,A_eq=constraint,b_eq=y,bounds=(0,None),method='highs-ds',options={'threads':2})
        if not fit.success or not np.isfinite(fit.x).all():raise RuntimeError('LAD readout solver failed: '+fit.message)
        residual=float(np.max(np.abs(constraint@fit.x-y)))
        if residual>1e-6:raise RuntimeError('LAD equality residual exceeds tolerance')
        centers.append(center);coefficients.append(fit.x[:design.shape[1]]-fit.x[design.shape[1]:2*design.shape[1]]);residuals.append(residual)
    return scalers,np.array(centers),np.column_stack(coefficients),max(residuals)


def predict_lad(fit,latent,context):
    scalers,centers,coefficient,_=fit
    q=np.r_[1.,*np.concatenate([(np.where(np.isfinite(x),x,mean)-mean)/scale for x,(mean,scale) in zip([latent,context],scalers)])]
    return centers+60*q@coefficient


def replay(data,encoded,fallback,progress=None):
    outputs,diagnostics={},{};context=np.column_stack([data['X'],fallback])
    with threadpool_limits(limits=2):
        for name,Z in encoded.items():
            valid=np.isfinite(Z).all(axis=1)
            for loss,penalty in [('ridge',1.),('lad',.001),('lad',.01)]:
                predictions=np.column_stack([fallback,fallback]).copy();fit=None;last=-24;fits=0;learned=0;residual=0.
                for i,now in enumerate(data['wakes']):
                    known=np.flatnonzero((np.arange(len(fallback))<i)&valid&(data['available']<=now)&(data['wakes']>=now-60*86400))
                    if not valid[i] or len(known)<40:continue
                    if fit is None or i-last>=24:
                        weights=np.exp2(-(now-data['wakes'][known])/(14*86400));target=np.column_stack([data['y'][known],data['y'][known]-fallback[known]])
                        if loss=='ridge':fit=fit_ridge(Z[known],context[known],target,weights,penalty)
                        else:
                            fit=fit_lad(Z[known],context[known],target,weights,penalty);residual=max(residual,fit[-1])
                        last=i;fits+=1
                    point=predict_ridge(fit,Z[i],context[i]) if loss=='ridge' else predict_lad(fit,Z[i],context[i])
                    predictions[i]=np.clip([point[0],point[1]+fallback[i]],1,480);learned+=1
                key=f'careReservoir_{name}_{loss}_p{penalty:g}'
                for j,target in enumerate(['direct','residual']):outputs[key+'_'+target]=predictions[:,j]
                diagnostics[key]=dict(refits=fits,learnedQueries=learned,fallbackQueries=len(fallback)-learned,latentWidth=Z.shape[1],validPatterns=int(sum(valid)),maximumLPEqualityResidual=residual)
                if progress:progress(key,diagnostics[key])
        members=np.column_stack([fallback,*outputs.values()])
        for name,policy,cal,local in [('localCalibratedSoft','soft',True,True),('localCalibratedBest','best',True,True),
            ('localRawSoft','soft',False,True),('globalCalibratedSoft','soft',True,False),('calibratedMedian','median',True,True)]:
            outputs['careReservoirCombination_'+name]=combine(data,members,policy,cal,local)
    return outputs,diagnostics


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','baseline','output']:ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--limit',type=int);args=ap.parse_args();root=Path(__file__).resolve().parents[1];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    if args.output.resolve().is_relative_to(root):ap.error('Keep private encodings and forecasts outside source')
    d=dict(np.load(args.features,allow_pickle=False));n=len(d['y'])
    if args.limit:d={k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in d.items()}
    base=json.loads(args.baseline.read_text());assert base['audit']['sourceSHA256']==sha(args.source);by={r['index']:r for r in base['events']}
    np.testing.assert_allclose([by[int(i)]['actual'] for i in d['indices']],d['available'],rtol=0,atol=1e-6)
    np.testing.assert_allclose([by[int(i)]['wakeMinutes'] for i in d['indices']],d['y'],rtol=0,atol=1e-6)
    fallback=(np.array([by[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60
    events,skipped=read_marks(args.source,'America/Los_Angeles');patterns=care_patterns(events,d['wakes'],16)
    with threadpool_limits(limits=2):weights=reservoir_weights();encoded=encode_patterns(patterns,weights)
    cache=args.output.with_suffix('.encodings.npz');np.savez_compressed(cache,**encoded)
    start=time.monotonic()
    def progress(name,diag):print(json.dumps(dict(candidate=name,**diag,seconds=time.monotonic()-start)),flush=True)
    forecasts,diag=replay(d,encoded,fallback,progress)
    r=dict(audit=dict(sourceSHA256=sha(args.source),featureCacheSHA256=sha(args.features),baselineResultSHA256=sha(args.baseline),encodingCacheSHA256=sha(cache),scriptSHA256=sha(Path(__file__)),
        helperFilesSHA256={name:sha(root/'Scripts'/name) for name in ['research_sleep_care_alignment.py','research_sleep_care_signatures.py','research_sleep_cycle_alignment.py','research_sleep_sequence_head.py','research_sleep_ensemble.py']},
        careExposure='completed',lookbackDays=60,halfLifeDays=14,minimumLabels=40,refitEvery=24,patternLength=16,skippedInputRecords=skipped,diagnostics=diag,
        reservoir=dict(width=64,seed=42,leaks=[.3,1.],initialState='zero at each query window',recurrentNorm=float(np.linalg.norm(weights[0],2)),weightsSHA256=hashlib.sha256(b''.join(x.tobytes() for x in weights)).hexdigest(),
        inputs='Eight mark fractions restored to unit sum; three log features divided by four; fixed Gaussian input weights and bias; orthogonal recurrent matrix scaled .9'),
        readouts='Joint direct/residual weighted ridge(alpha1); separate normalized weighted LAD with L1 slopes(lambda .001/.01), unpenalized intercept and training-only block scaling',
        controls='Known context with zero latent block, pooled group means, or fixed reservoir final states; only readouts learn from labels',
        limitation='Finite-window independent adaptation; small fixed reservoir/seed; no physiological interpretation or infant accuracy guarantee; not independent future validation',
        sourceURLs=['https://mantas.info/get-publication/?f=Practical_ESN.pdf']),models={},events={})
    for name,p in forecasts.items():
        assert np.isfinite(p).all()
        r['models'][name]=dict(all=metrics(d['y'],p,np.ones(len(p),dtype=bool)))
        r['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(d['indices'],d['y'],p)]
        print(name,json.dumps(r['models'][name]),flush=True)
    args.output.write_text(json.dumps(r,indent=2,allow_nan=False)+'\n')


if __name__=='__main__':main()
