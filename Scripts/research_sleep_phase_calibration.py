#!/usr/bin/env python3
"""Rolling zero-shrunk calibration by an issued forecast's clock phase."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from research_sleep_ensemble import combine,metrics,weighted_median
from research_sleep_minute_grid import snap


def calibrate(data,issued,bandwidth,cap):
    phase=np.remainder(data['wakes']/60+issued,5)
    output=issued.copy();updates=0;maximum=0.
    for i,now in enumerate(data['wakes']):
        known=np.flatnonzero((np.arange(len(issued))<i)&(data['available']<=now)
            &(data['wakes']>=now-60*86400))
        if len(known)<40:continue
        distance=np.abs(phase[known]-phase[i]);distance=np.minimum(distance,5-distance)
        weights=np.exp2(-(now-data['wakes'][known])/(14*86400))
        if bandwidth is not None:
            weights*=np.exp(-.5*(distance/bandwidth)**2)
        effective=weights.sum()**2/max(1e-12,np.sum(weights**2))
        if effective<8:continue
        # Ten recent-example equivalents at zero keep weak evidence close to
        # the original issued forecast. Outcomes enter only after availability.
        correction=weighted_median(np.r_[data['y'][known]-issued[known],0.],np.r_[weights,10.])
        correction=float(np.clip(correction,-cap,cap))
        output[i]=np.clip(issued[i]+correction,1,480)
        updates+=int(abs(output[i]-issued[i])>1e-9)
        maximum=max(maximum,abs(output[i]-issued[i]))
    return output,dict(changedForecasts=updates,maximumAbsoluteShiftMinutes=maximum,bandwidthMinutes=bandwidth,capMinutes=cap)


def replay(data,app):
    forecasts,diag={},{}
    for bandwidth in [.5,1.5]:
        for cap in [2.5,5.]:
            name=f'phase_bw{bandwidth:g}_cap{cap:g}'
            forecasts[name],diag[name]=calibrate(data,app,bandwidth,cap)
    for cap in [2.5,5.]:
        name=f'globalShrink_cap{cap:g}'
        forecasts[name],diag[name]=calibrate(data,app,None,cap)
    rounded=[snap(app,data['wakes'],r) for r in ['nearest','floor','ceil']]
    members=np.column_stack([app,*rounded])
    for name,local in [('rawGridBestLocal',True),('rawGridBestGlobal',False)]:
        forecasts[name]=combine(data,members,policy='best',calibrate=False,local=local)
    expanded=np.column_stack([app,*forecasts.values(),*rounded])
    for name,policy,cal,local in [('localCalibratedSoft','soft',True,True),('localCalibratedBest','best',True,True),
        ('localRawSoft','soft',False,True),('globalCalibratedSoft','soft',True,False),('calibratedMedian','median',True,True)]:
        forecasts['phaseCombination_'+name]=combine(data,expanded,policy,cal,local)
    return forecasts,diag


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','baseline','output']:parser.add_argument('--'+name,type=Path,required=True)
    args=parser.parse_args()
    if args.output.resolve().is_relative_to(Path(__file__).resolve().parents[1]):parser.error('Keep private forecasts outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    data=dict(np.load(args.features,allow_pickle=False));base=json.loads(args.baseline.read_text());assert sha(args.source)==base['audit']['sourceSHA256']
    by={r['index']:r for r in base['events']};indices=data['indices'].astype(int).tolist();assert set(by)==set(indices)
    np.testing.assert_allclose([by[i]['actual'] for i in indices],data['available'],rtol=0,atol=1e-6)
    np.testing.assert_allclose([by[i]['wakeMinutes'] for i in indices],data['y'],rtol=0,atol=1e-6)
    app=(np.array([by[i]['prediction'] for i in indices])-data['wakes'])/60
    forecasts,diag=replay(data,app)
    result=dict(audit=dict(sourceSHA256=sha(args.source),careExposure='completed',scriptSHA256=sha(Path(__file__)),
        featureCacheSHA256=sha(args.features),baselineResultSHA256=sha(args.baseline),
        helperFilesSHA256={n:sha(Path(__file__).parent/n) for n in ['research_sleep_ensemble.py','research_sleep_minute_grid.py']},
        lookbackDays=60,halfLifeDays=14,minimumLabels=40,minimumEffectiveSupport=8,zeroPriorMass=10,
        periodMinutes=5,diagnostics=diag,
        rule='Circular kernel of issued forecast phase; resolved past unrounded app residuals; zero-shrunk median; bounded shift; no current target minute',
        limitation='Retrospective archive-driven phase hypothesis, not independent future validation'),models={},events={})
    for name,p in forecasts.items():
        assert np.isfinite(p).all()
        result['models'][name]=dict(all=metrics(data['y'],p,np.ones(len(indices),dtype=bool)))
        result['events'][name]=[dict(index=i,actual=float(y),prediction=float(v)) for i,y,v in zip(indices,data['y'],p)]
        print(name,json.dumps(result['models'][name]),flush=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')


if __name__=='__main__':main()
