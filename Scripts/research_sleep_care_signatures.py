#!/usr/bin/env python3
"""Past-only level-two path signatures of completed marked care events."""
import argparse
import csv
import datetime as dt
import hashlib
import json
import time
from pathlib import Path
from zoneinfo import ZoneInfo
import numpy as np
from sklearn.ensemble import HistGradientBoostingRegressor
from threadpoolctl import threadpool_limits
from research_sleep_ensemble import combine,metrics
from sleep_weighted_bins import fast_weighted_bins

MARKS=['Sleep','Feed','Diaper','Solids','Meds','Bath','Tummy time','Other']
WINDOWS=[6,24,48]


def signature2(increments):
    """Chen concatenation for piecewise-linear increments, truncated at two."""
    increments=np.asarray(increments,dtype=float)
    assert increments.ndim==2 and np.isfinite(increments).all()
    first=np.zeros(increments.shape[1]);second=np.zeros((len(first),len(first)))
    for delta in increments:
        second+=np.outer(first,delta)+.5*np.outer(delta,delta)
        first+=delta
    return first,second


def read_marks(path,zone):
    tz=ZoneInfo(zone);events=[];skipped=0
    parse=lambda text:dt.datetime.strptime(text,'%Y-%m-%d %H:%M').replace(tzinfo=tz).timestamp()
    with path.open(encoding='utf-8-sig') as f:
        for row in csv.DictReader(f):
            if not row.get('Start'):continue
            kind=row['Type'];start=parse(row['Start']);end=parse(row['End']) if row.get('End') else start
            if end<start or (kind in ['Sleep','Feed'] and (not row.get('End') or end<=start)):
                skipped+=1;continue
            mark=MARKS.index(kind) if kind in MARKS else MARKS.index('Other')
            events.append([start,end,mark])
    return np.asarray(events,dtype=float).reshape(-1,3),skipped


def event_features(events,wakes):
    """Calendar-free elapsed-time paths; simultaneous completions share a jump."""
    result={k:[] for k in ['counts','timing','order']}
    dim=1+len(MARKS);upper=np.triu_indices(dim,1)
    for now in wakes:
        rows={k:[] for k in result}
        for hours in WINDOWS:
            lower=now-hours*3600
            known=events[(events[:,0]<=now)&(events[:,1]<=now)&(events[:,1]>=lower)]
            times=np.unique(known[:,1]);cursor=lower;increments=[]
            for end in times:
                advance=np.zeros(dim);advance[0]=(end-cursor)/(hours*3600);increments.append(advance)
                jump=np.zeros(dim)
                for mark in known[known[:,1]==end,2].astype(int):jump[mark+1]+=1
                increments.append(jump);cursor=end
            advance=np.zeros(dim);advance[0]=(now-cursor)/(hours*3600);increments.append(advance)
            first,second=signature2(np.asarray(increments));areas=.5*(second-second.T)
            rows['counts'].extend(first)
            rows['timing'].extend(np.r_[first,areas[0,1:]])
            rows['order'].extend(np.r_[first,areas[upper]])
        for key in result:result[key].append(rows[key])
    return {key:np.asarray(value) for key,value in result.items()}


def replay(data,blocks,fallback,progress=None,fast_bins=True):
    forecasts,diagnostics={},{}
    with threadpool_limits(limits=2),fast_weighted_bins(fast_bins):
        for kind,Z in blocks.items():
            assert len(Z)==len(fallback) and np.isfinite(Z).all()
            X=np.column_stack([data['X'],fallback,Z])
            for residual in [False,True]:
                for half in [14,60]:
                    name=f'careSignature_{kind}_{"residual" if residual else "direct"}_h{half}'
                    pred=fallback.copy();fit=None;last=-24;fits=0;learned=0
                    for i,now in enumerate(data['wakes']):
                        known=np.flatnonzero((np.arange(len(pred))<i)&(data['available']<=now)&(data['wakes']>=now-60*86400))
                        if len(known)<40:continue
                        if fit is None or i-last>=24:
                            fit=HistGradientBoostingRegressor(loss='absolute_error',max_iter=150,max_leaf_nodes=7,min_samples_leaf=15,
                                l2_regularization=10,learning_rate=.05,early_stopping=False,random_state=42)
                            weights=np.exp2(-(now-data['wakes'][known])/(half*86400))
                            target=data['y'][known]-(fallback[known] if residual else 0)
                            fit.fit(X[known],target,sample_weight=weights);last=i;fits+=1
                        value=fit.predict(X[i:i+1])[0]+(fallback[i] if residual else 0)
                        pred[i]=np.clip(value,1,480);learned+=1
                    forecasts[name]=pred;diagnostics[name]=dict(refits=fits,learnedQueries=learned,fallbackQueries=len(pred)-learned,featureCount=X.shape[1])
                    if progress:progress(name,diagnostics[name])
        members=np.column_stack([fallback,*forecasts.values()])
        for name,policy,cal,local in [('localCalibratedSoft','soft',True,True),('localCalibratedBest','best',True,True),
            ('localRawSoft','soft',False,True),('globalCalibratedSoft','soft',True,False),('calibratedMedian','median',True,True)]:
            forecasts['careSignatureCombination_'+name]=combine(data,members,policy,cal,local)
    return forecasts,diagnostics


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','baseline','fast-bin-check','output']:ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--limit',type=int);args=ap.parse_args();root=Path(__file__).resolve().parents[1];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    if args.output.resolve().is_relative_to(root):ap.error('Keep private event paths and predictions outside source')
    d=dict(np.load(args.features,allow_pickle=False));n=len(d['y'])
    if args.limit:d={k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in d.items()}
    base=json.loads(args.baseline.read_text());assert base['audit']['sourceSHA256']==sha(args.source)
    by={r['index']:r for r in base['events']}
    np.testing.assert_allclose([by[int(i)]['actual'] for i in d['indices']],d['available'],rtol=0,atol=1e-6)
    np.testing.assert_allclose([by[int(i)]['wakeMinutes'] for i in d['indices']],d['y'],rtol=0,atol=1e-6)
    fallback=(np.array([by[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60
    fast=json.loads(args.fast_bin_check.read_text());assert fast['passed'] and fast['predictionMaximumDifference']==0
    from sklearn.ensemble._hist_gradient_boosting import binning
    from sklearn.utils import stats
    assert sha(Path(binning.__file__))==fast['nativeBinningSHA256'] and sha(Path(stats.__file__))==fast['nativeStatsSHA256']
    assert sha(root/'Scripts/sleep_weighted_bins.py')==fast['helperSHA256']
    events,skipped=read_marks(args.source,'America/Los_Angeles');blocks=event_features(events,d['wakes'])
    feature_path=args.output.with_suffix('.features.npz');np.savez_compressed(feature_path,**blocks)
    start=time.monotonic()
    def progress(name,diag):print(json.dumps(dict(candidate=name,**diag,seconds=time.monotonic()-start)),flush=True)
    forecasts,diag=replay(d,blocks,fallback,progress)
    r=dict(audit=dict(sourceSHA256=sha(args.source),featureCacheSHA256=sha(args.features),baselineResultSHA256=sha(args.baseline),
        derivedFeatureCacheSHA256=sha(feature_path),fastBinCheckSHA256=sha(args.fast_bin_check),scriptSHA256=sha(Path(__file__)),
        helperFilesSHA256={n:sha(root/'Scripts'/n) for n in ['research_sleep_ensemble.py','sleep_weighted_bins.py']},careExposure='completed',
        timeZone='America/Los_Angeles',marks=MARKS,windowHours=WINDOWS,lookbackDays=60,trainingHalfLifeDays=[14,60],refitEvery=24,minimumLabels=40,
        skippedInputRecords=skipped,diagnostics=diag,path='Normalized elapsed-time advance, then grouped cumulative one-hot completion jump; simultaneous completions have no invented internal order',
        signatures='Level one controls; level one plus time/mark signed areas; level one plus all level-two signed areas',
        availability='Only completed records with start/end <= wake; missing sleep/feed ends omitted as uncertain timer completion, other missing ends treated as instantaneous export records',
        limitations='Finite second-order summaries are lossy, rare event types share Other; no notes or fitted vocabulary; general sequence strategy, not a published infant accuracy guarantee',
        sourceURLs=['https://arxiv.org/html/1603.03788v2']),models={},events={})
    for name,p in forecasts.items():
        r['models'][name]=dict(all=metrics(d['y'],p,np.ones(len(p),dtype=bool)))
        r['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(d['indices'],d['y'],p)]
        print(name,json.dumps(r['models'][name]),flush=True)
    args.output.write_text(json.dumps(r,indent=2,allow_nan=False)+'\n')


if __name__=='__main__':main()
