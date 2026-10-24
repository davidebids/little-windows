#!/usr/bin/env python3
"""Clock-grid forecast controls and past-only expert adaptation."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from research_sleep_ensemble import combine,metrics


def snap(prediction,wakes,rule):
    # Three-microsecond tolerance handles floating reconstruction of an exact
    # boundary; the source timer history has whole-minute resolution.
    ticks=(wakes+prediction*60)/300
    if rule=='nearest':rounded=np.floor(ticks+.5+1e-8)
    elif rule=='floor':rounded=np.floor(ticks+1e-8)
    elif rule=='ceil':rounded=np.ceil(ticks-1e-8)
    else:raise ValueError('Unknown grid rule')
    return np.clip((rounded*300-wakes)/60,1,480)


def replay(data,app,parent):
    raw={}
    for prefix,values in [('app',app),('research',parent)]:
        for rule in ['nearest','floor','ceil']:raw[prefix+'_grid5_'+rule]=snap(values,data['wakes'],rule)
    forecasts=dict(raw)
    for group,members in [('app',np.column_stack([app,*[raw['app_grid5_'+r] for r in ['nearest','floor','ceil']]])),
        ('expanded',np.column_stack([app,parent,*raw.values()]))]:
        for name,policy,cal,local in [('localCalibratedSoft','soft',True,True),('localCalibratedBest','best',True,True),
            ('localRawSoft','soft',False,True),('globalCalibratedSoft','soft',True,False),('calibratedMedian','median',True,True)]:
            forecasts['grid_'+group+'_'+name]=combine(data,members,policy,cal,local)
    return forecasts


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','baseline','parent','output']:
        parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--parent-model',default='convex_d30_global_r1')
    args=parser.parse_args()
    if args.output.resolve().is_relative_to(Path(__file__).resolve().parents[1]):parser.error('Keep private forecasts outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    data=dict(np.load(args.features,allow_pickle=False));base=json.loads(args.baseline.read_text());parent=json.loads(args.parent.read_text())
    source=sha(args.source);assert base['audit']['sourceSHA256']==parent['audit']['sourceSHA256']==source
    assert parent['audit'].get('careExposure','completed')=='completed'
    by={r['index']:r for r in base['events']};other={r['index']:r for r in parent['events'][args.parent_model]};indices=data['indices'].astype(int).tolist();assert set(indices)==set(by)==set(other)
    np.testing.assert_allclose([by[i]['actual'] for i in indices],data['available'],rtol=0,atol=1e-6)
    np.testing.assert_allclose([by[i]['wakeMinutes'] for i in indices],data['y'],rtol=0,atol=1e-6)
    np.testing.assert_allclose([other[i]['actual'] for i in indices],data['y'],rtol=0,atol=1e-6)
    app=(np.array([by[i]['prediction'] for i in indices])-data['wakes'])/60
    research=np.array([other[i]['prediction'] for i in indices])
    forecasts=replay(data,app,research)
    result=dict(audit=dict(sourceSHA256=source,careExposure='completed',scriptSHA256=sha(Path(__file__)),
        featureCacheSHA256=sha(args.features),baselineResultSHA256=sha(args.baseline),parentResultSHA256=sha(args.parent),parentModel=args.parent_model,
        helperFilesSHA256={'research_sleep_ensemble.py':sha(Path(__file__).parent/'research_sleep_ensemble.py')},
        gridMinutes=5,roundingTie='half up',boundaryToleranceSeconds=.000003,planningBoundsMinutes=[1,480],
        rule='Static known-forecast clock rounding; adaptive policies use resolved past issued errors; no current target-minute input',
        limitation='Grid and parent chosen after archive inspection; retrospective model selection, not independent future validation'),models={},events={})
    for name,p in forecasts.items():
        assert np.isfinite(p).all()
        result['models'][name]=dict(all=metrics(data['y'],p,np.ones(len(indices),dtype=bool)))
        result['events'][name]=[dict(index=i,actual=float(y),prediction=float(v)) for i,y,v in zip(indices,data['y'],p)]
        print(name,json.dumps(result['models'][name]),flush=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')


if __name__=='__main__':main()
