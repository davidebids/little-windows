#!/usr/bin/env python3
"""Supervised heads on current-wake-conditioned frozen sequence states."""
import argparse
import hashlib
import json
from pathlib import Path
import time
import numpy as np
from threadpoolctl import threadpool_limits, threadpool_info
from research_sleep_sequence_prior import query_at, decision_points
from research_sleep_sequence_head import heads, fit_ridge, predict_ridge
from research_sleep_ensemble import combine, metrics
from sleep_weighted_bins import fast_weighted_bins


def capture_state(pipeline, query):
    """Capture one public forecast without modifying its model or outputs."""
    state = {}
    def norm_hook(module, args, output):
        if 'norm' not in state:
            state['norm'] = tuple(t.detach().clone() for t in output[1])
    def input_hook(module, args):
        assert 'embedding' not in state
        state['embedding'] = args[0].detach().clone()
    def output_hook(module, args, output):
        state['raw'] = output.detach().clone()
    handles = [pipeline.model.instance_norm.register_forward_hook(norm_hook),
        pipeline.model.output_patch_embedding.register_forward_pre_hook(input_hook),
        pipeline.model.output_patch_embedding.register_forward_hook(output_hook)]
    try:
        public = pipeline.predict([query], prediction_length=1, context_length=128, cross_learning=False)[0]
    finally:
        for handle in handles:
            handle.remove()
    z, raw, (loc, scale) = state['embedding'], state['raw'], state['norm']
    assert tuple(z.shape) == (8, 1, 768)
    recovered = pipeline.model.instance_norm.inverse(raw.reshape(8, -1), (loc, scale))
    recovered = recovered.reshape(8, len(pipeline.quantiles), pipeline.model_output_patch_size)[0, :, 0]
    quantiles = public[0, :, 0]
    difference = float((recovered - quantiles).abs().max())
    if difference > 1e-5:
        raise ValueError('Captured output does not reconstruct the public forecast')
    values = (z[0, 0].cpu().numpy(), np.array([loc[0].item(), scale[0].item()]), quantiles.cpu().numpy())
    if not all(np.isfinite(v).all() for v in values) or values[1][1] <= 0:
        raise ValueError('Invalid captured model state')
    return (*values, difference)


def features(data, capture, progress=None):
    n = len(data['y'])
    Z, scales, Q = np.full((n,768),np.nan), np.full((n,2),np.nan), np.full((n,21),np.nan)
    maximum, issued = 0., 0
    for i in range(n):
        query = query_at(data,i,128,True)
        if query is None:
            continue
        Z[i], scales[i], Q[i], difference = capture(query)
        maximum, issued = max(maximum,difference), issued+1
        if progress and issued%200==0:
            progress(issued)
    return Z, scales, Q, dict(issuedQueries=issued, maximumReconstructionDifference=maximum)


def learned_heads(data,Z,scales,fallback,diagnostics=None,fast_bins=False):
    # Import before discovering native runtimes: a decorator created at module
    # load misses OpenMP libraries loaded later by the boosting implementation.
    from sklearn.ensemble import HistGradientBoostingRegressor
    with threadpool_limits(limits=2), fast_weighted_bins(fast_bins):
        pools = [{k:p.get(k) for k in ['user_api','internal_api','prefix','num_threads','version']}
                 for p in threadpool_info()]
        assert all(p['num_threads'] is None or p['num_threads'] <= 2 for p in pools)
        if diagnostics is not None:
            diagnostics['nativeThreadPools'] = pools
        return _learned_heads(data,Z,scales,fallback)


def _learned_heads(data,Z,scales,fallback):
    context = np.column_stack([data['X'],scales])
    d = dict(data,X=context)
    outputs, counts = heads(d,{'conditioned128':Z},fallback)
    valid = np.isfinite(Z).all(axis=1)
    normalized = np.full(len(fallback),np.nan)
    normalized[valid] = np.arcsinh((data['y'][valid]-scales[valid,0])/scales[valid,1])
    for alpha in [.1,1.]:
        prediction = fallback.copy();fit,last,refits = None,-100,0
        for i in range(len(fallback)):
            known = np.flatnonzero((np.arange(len(fallback))<i)&valid
                &(data['available']<=data['wakes'][i])&(data['wakes']>=data['wakes'][i]-60*86400))
            if not valid[i] or len(known)<40:
                continue
            if fit is None or i-last>=24:
                weight = np.exp2(-(data['wakes'][i]-data['wakes'][known])/(14*86400))
                fit=fit_ridge(Z[known],context[known],normalized[known,None],weight,alpha)
                last,refits=i,refits+1
            z=float(predict_ridge(fit,Z[i],context[i])[0])
            # Invert the model's arcsinh normalization within planning bounds.
            low=np.arcsinh((1-scales[i,0])/scales[i,1]);high=np.arcsinh((480-scales[i,0])/scales[i,1])
            prediction[i]=np.clip(scales[i,0]+scales[i,1]*np.sinh(np.clip(z,low,high)),1,480)
        name=f'conditioned128_normalized_a{alpha:g}'
        outputs[name],counts[name]=prediction,refits
    from sklearn.ensemble import HistGradientBoostingRegressor
    for residual in [False,True]:
        prediction=fallback.copy();model,last,refits=None,-100,0
        for i in range(len(fallback)):
            known=np.flatnonzero((np.arange(len(fallback))<i)&valid
                &(data['available']<=data['wakes'][i])&(data['wakes']>=data['wakes'][i]-60*86400))
            if not valid[i] or len(known)<40:continue
            if model is None or i-last>=24:
                # No validation split or stopping decision can see future rows.
                model=HistGradientBoostingRegressor(loss='absolute_error',max_iter=150,max_leaf_nodes=7,
                    min_samples_leaf=15,l2_regularization=10,learning_rate=.05,early_stopping=False,random_state=42)
                target=data['y'][known]-(fallback[known] if residual else 0)
                weight=np.exp2(-(data['wakes'][i]-data['wakes'][known])/(14*86400))
                model.fit(np.column_stack([Z[known],context[known]]),target,sample_weight=weight)
                last,refits=i,refits+1
            value=model.predict(np.r_[Z[i],context[i]][None])[0]
            prediction[i]=np.clip(value+(fallback[i] if residual else 0),1,480)
        name='conditioned128_boosted_'+('residual' if residual else 'direct')
        outputs[name],counts[name]=prediction,refits
    return outputs,counts


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','baseline','bootstrap','model','cache','output']:
        parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--fast-bin-certificate',type=Path)
    parser.add_argument('--reuse-cache-certificate',type=Path)
    parser.add_argument('--reuse-extraction-source',type=Path)
    args=parser.parse_args();root=Path(__file__).resolve().parents[1]
    if any(p.resolve().is_relative_to(root) for p in [args.cache,args.output]):
        parser.error('Keep private numeric caches and forecasts outside the repository')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    boot=json.loads(args.bootstrap.read_text());assert boot['passed']
    assert boot['latentWidth']==768 and boot['passiveHooksPreservePublicForecast'] and boot['currentKnownCovariateSensitivity']>1e-5
    for n,h in boot['modelFiles'].items():assert sha(args.model/n)==h
    data=dict(np.load(args.features,allow_pickle=False));base=json.loads(args.baseline.read_text());assert sha(args.source)==base['audit']['sourceSHA256']
    rows={r['index']:r for r in base['events']};indices=data['indices'].astype(int).tolist();assert set(rows)==set(indices)
    np.testing.assert_allclose([rows[i]['actual'] for i in indices],data['available'],rtol=0,atol=1e-6)
    np.testing.assert_allclose([rows[i]['wakeMinutes'] for i in indices],data['y'],rtol=0,atol=1e-6)
    fallback=(np.array([rows[i]['prediction'] for i in indices])-data['wakes'])/60
    import torch,chronos,sklearn
    from chronos import Chronos2Pipeline
    torch.set_num_threads(2);torch.manual_seed(42)
    pipeline=Chronos2Pipeline.from_pretrained(args.model,device_map='cpu',dtype=torch.float32);pipeline.model.eval()
    assert pipeline.model.chronos_config.use_arcsinh
    started=time.monotonic()
    def progress(issued):print(json.dumps(dict(issuedQueries=issued,seconds=time.monotonic()-started)),flush=True)
    extraction_sha=sha(Path(__file__))
    if args.reuse_cache_certificate:
        import ast
        assert args.reuse_extraction_source is not None
        certificate=json.loads(args.reuse_cache_certificate.read_text())
        assert certificate['cacheChecks']['passed'] and certificate['cacheSHA256']==sha(args.cache)
        assert certificate['scriptSHA256']==sha(args.reuse_extraction_source)
        assert certificate['sourceSHA256']==sha(args.source) and certificate['featureCacheSHA256']==sha(args.features)
        assert certificate['modelFiles']==boot['modelFiles']
        assert all(sha(Path(__file__).parent/n)==h for n,h in certificate['helperFilesSHA256'].items())
        def extraction_nodes(path):
            return {n.name:ast.dump(n,include_attributes=False) for n in ast.parse(path.read_text()).body
                    if isinstance(n,ast.FunctionDef) and n.name in ['features','capture_state']}
        assert extraction_nodes(args.reuse_extraction_source)==extraction_nodes(Path(__file__))
        cache=np.load(args.cache,allow_pickle=False);Z,scales,Q=[cache[k] for k in ['Z','scales','quantiles']]
        expected=np.array([query_at(data,i,128,True) is not None for i in range(len(fallback))])
        assert Z.shape==(len(fallback),768) and scales.shape==(len(fallback),2) and Q.shape==(len(fallback),21)
        assert np.array_equal(np.isfinite(Z).all(axis=1),expected)
        assert np.isfinite(scales[expected]).all() and np.isfinite(Q[expected]).all() and (scales[expected,1]>0).all()
        # The completed extraction saved its cache only after every call passed
        # the unchanged capture function's reconstruction guard. The measured
        # maximum was in the interrupted process; report its certified bound.
        diag=dict(issuedQueries=int(sum(expected)),maximumReconstructionDifference=1e-5,
                  reconstructionDifferenceIsUpperBound=True,validatedCacheReused=True)
        extraction_sha=certificate['scriptSHA256']
    else:
        assert args.reuse_extraction_source is None
        Z,scales,Q,diag=features(data,lambda q:capture_state(pipeline,q),progress)
        np.savez_compressed(args.cache,Z=Z,scales=scales,quantiles=Q)
    fast_certificate=None
    if args.fast_bin_certificate:
        from sklearn.ensemble._hist_gradient_boosting import binning
        from sklearn.utils import stats
        fast_certificate=json.loads(args.fast_bin_certificate.read_text())
        assert fast_certificate['passed'] and fast_certificate['predictionMaximumDifference']==0
        assert sha(Path(__file__).parent/'sleep_weighted_bins.py')==fast_certificate['helperSHA256']
        assert sha(Path(binning.__file__))==fast_certificate['nativeBinningSHA256']
        assert sha(Path(stats.__file__))==fast_certificate['nativeStatsSHA256']
    forecasts,counts=learned_heads(data,Z,scales,fallback,diagnostics=diag,fast_bins=fast_certificate is not None)
    for key in ['median','risk']:forecasts['conditioned128_native_'+key]=fallback.copy()
    for i in np.flatnonzero(np.isfinite(Z).all(axis=1)):
        points,_=decision_points(Q[i],pipeline.quantiles)
        for key in points:forecasts['conditioned128_native_'+key][i]=points[key]
    result=dict(audit=dict(sourceSHA256=sha(args.source),careExposure='completed',scriptSHA256=sha(Path(__file__)),
        featureCacheSHA256=sha(args.features),baselineResultSHA256=sha(args.baseline),representationCacheSHA256=sha(args.cache),
        extractionSourceSHA256=extraction_sha,cacheReuse=bool(args.reuse_cache_certificate),fastBinningCertificate=fast_certificate,
        modelFiles=boot['modelFiles'],chronosVersion=chronos.__version__,torchVersion=torch.__version__,sklearnVersion=sklearn.__version__,
        lookbackDays=60,minimumEncoderLabels=40,minimumHeadLabels=40,refitEvery=24,weightHalfLifeDays=14,
        diagnostics=diag,frozenEncoder=True,currentWakeConditioned=True,normalization='arcsinh with captured per-query location and scale',
        rule='One causal public query captures target forecast token; reconstructed quantiles checked on every case; training-only head fits',
        helperFilesSHA256={n:sha(Path(__file__).parent/n) for n in ['research_sleep_sequence_head.py','research_sleep_sequence_prior.py','research_sleep_ensemble.py','sleep_weighted_bins.py']},
        sourceURLs=['https://github.com/amazon-science/chronos-forecasting']),models={},events={})
    def save(name,p):
        assert np.isfinite(p).all()
        result['models'][name]=dict(all=metrics(data['y'],p,np.ones(len(indices),dtype=bool)))
        if name in counts:result['models'][name]['refits']=counts[name]
        result['events'][name]=[dict(index=i,actual=float(y),prediction=float(v)) for i,y,v in zip(indices,data['y'],p)]
        args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n');print(name,json.dumps(result['models'][name]),flush=True)
    for name,p in forecasts.items():save(name,p)
    members=np.column_stack([fallback,*forecasts.values()])
    for name,policy,cal,local in [('localCalibratedSoft','soft',True,True),('localCalibratedBest','best',True,True),
        ('localRawSoft','soft',False,True),('globalCalibratedSoft','soft',True,False),('calibratedMedian','median',True,True)]:
        save('conditionedHead_'+name,combine(data,members,policy,cal,local))


if __name__=='__main__':main()
