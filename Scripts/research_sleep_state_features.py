#!/usr/bin/env python3
"""Matched causal learners with and without completed-history model states."""
import argparse
import hashlib
import json
import time
from pathlib import Path
import numpy as np
from sklearn.ensemble import HistGradientBoostingRegressor
from threadpoolctl import threadpool_limits,threadpool_info
from research_sleep_ensemble import combine,metrics
from sleep_weighted_bins import fast_weighted_bins


def state_features(raw):
    assert raw.ndim==3 and raw.shape[1:]==(14,5) and np.isfinite(raw).all()
    # Each model contributes its forward switch prediction plus four slow
    # states at the wake. No actual next sleep starts enter these columns.
    return raw.reshape(len(raw),-1)


def replay(data,states,fallback,progress=None,fast_bins=True,refit_every=24):
    outputs,diag={},{}
    assert len(states)==len(fallback)==len(data['y'])
    context=np.column_stack([data['X'],fallback])
    with threadpool_limits(limits=2),fast_weighted_bins(fast_bins):
        pools=threadpool_info();assert all(p.get('num_threads',0)<=2 for p in pools)
        for augmented in [False,True]:
            X=np.column_stack([context,state_features(states)]) if augmented else context
            for residual in [False,True]:
                for half_life in [14,60]:
                    name=f'stateFeatures_{"augmented" if augmented else "control"}_{"residual" if residual else "direct"}_h{half_life}'
                    pred=fallback.copy();fit=None;last=-refit_every;count=0;learned=0
                    for i,now in enumerate(data['wakes']):
                        known=np.flatnonzero((np.arange(len(pred))<i)&(data['available']<=now)&(data['wakes']>=now-60*86400))
                        if len(known)<40:continue
                        if fit is None or i-last>=refit_every:
                            fit=HistGradientBoostingRegressor(loss='absolute_error',max_iter=150,max_leaf_nodes=7,
                                min_samples_leaf=15,l2_regularization=10,learning_rate=.05,early_stopping=False,random_state=42)
                            target=data['y'][known]-(fallback[known] if residual else 0)
                            weights=np.exp2(-(now-data['wakes'][known])/(half_life*86400))
                            fit.fit(X[known],target,sample_weight=weights);last=i;count+=1
                        value=fit.predict(X[i:i+1])[0]+(fallback[i] if residual else 0)
                        pred[i]=np.clip(value,1,480);learned+=1
                    outputs[name]=pred;diag[name]=dict(refits=count,learnedQueries=learned,fallbackQueries=len(pred)-learned,featureCount=X.shape[1])
                    if progress:progress(name,diag[name])
        # Include the paired controls in the causal combination pool. Its
        # results do not isolate the added states; the matched heads do.
        members=np.column_stack([fallback,*outputs.values()])
        for name,policy,cal,local in [('localCalibratedSoft','soft',True,True),('localCalibratedBest','best',True,True),
            ('localRawSoft','soft',False,True),('globalCalibratedSoft','soft',True,False),('calibratedMedian','median',True,True)]:
            outputs['stateFeatureCombination_'+name]=combine(data,members,policy,cal,local)
    return outputs,diag


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','baseline','observer-result','observer-check','fast-bin-check','output']:ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--limit',type=int);args=ap.parse_args();root=Path(__file__).resolve().parents[1];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    if args.output.resolve().is_relative_to(root):ap.error('Keep private forecasts outside source')
    check=json.loads(args.observer_check.read_text());observer=json.loads(args.observer_result.read_text())
    assert check['passed'] and check['resultSHA256']==sha(args.observer_result)
    assert observer['audit']['sourceSHA256']==sha(args.source) and observer['audit']['featureCacheSHA256']==sha(args.features)
    assert observer['audit']['baselineResultSHA256']==sha(args.baseline)
    raw_path=args.observer_result.with_suffix('.states.json');assert observer['audit']['statesSHA256']==sha(raw_path)
    raw=np.asarray(json.loads(raw_path.read_text()));d=dict(np.load(args.features,allow_pickle=False));n=len(d['y']);assert raw.shape==(n,14,5)
    base=json.loads(args.baseline.read_text());by={r['index']:r for r in base['events']};assert set(by)==set(d['indices'].astype(int).tolist())
    np.testing.assert_allclose([by[int(i)]['actual'] for i in d['indices']],d['available'],rtol=0,atol=1e-6)
    np.testing.assert_allclose([by[int(i)]['wakeMinutes'] for i in d['indices']],d['y'],rtol=0,atol=1e-6)
    fallback=(np.array([by[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60
    if args.limit:
        d={k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in d.items()};raw=raw[:args.limit];fallback=fallback[:args.limit]
    fast=json.loads(args.fast_bin_check.read_text());assert fast['passed'] and fast['predictionMaximumDifference']==0
    from sklearn.ensemble._hist_gradient_boosting import binning
    from sklearn.utils import stats
    assert sha(Path(binning.__file__))==fast['nativeBinningSHA256'] and sha(Path(stats.__file__))==fast['nativeStatsSHA256']
    assert sha(root/'Scripts/sleep_weighted_bins.py')==fast['helperSHA256']
    start=time.monotonic()
    def progress(name,diag):print(json.dumps(dict(candidate=name,**diag,seconds=time.monotonic()-start)),flush=True)
    predictions,diag=replay(d,raw,fallback,progress)
    r=dict(audit=dict(sourceSHA256=sha(args.source),featureCacheSHA256=sha(args.features),baselineResultSHA256=sha(args.baseline),
        observerResultSHA256=sha(args.observer_result),observerCheckSHA256=sha(args.observer_check),statesSHA256=sha(raw_path),fastBinCheckSHA256=sha(args.fast_bin_check),
        scriptSHA256=sha(Path(__file__)),helperFilesSHA256={name:sha(root/'Scripts'/name) for name in ['research_sleep_ensemble.py','sleep_weighted_bins.py']},
        careExposure='completed',lookbackDays=60,halfLifeDays=[14,60],minimumLabels=40,refitEvery=24,diagnostics=diag,
        features='Identical compact context and issued app forecast in every head; augmented heads append 14x5 completed-history observer values',
        targets=['direct next-start interval','residual against originally issued app forecast'],
        caveat='Matched retrospective feature ablation, not physiological interpretation or independent future validation'),models={},events={})
    for name,p in predictions.items():
        r['models'][name]=dict(all=metrics(d['y'],p,np.ones(len(p),dtype=bool)))
        r['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(d['indices'],d['y'],p)]
        print(name,json.dumps(r['models'][name]),flush=True)
    args.output.write_text(json.dumps(r,indent=2,allow_nan=False)+'\n')


if __name__=='__main__':main()
