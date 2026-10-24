#!/usr/bin/env python3
"""Matched action-loss decision with three preceding completed sleep/wake cycles."""
import argparse
import csv
import datetime as dt
import hashlib
import json
from pathlib import Path
from zoneinfo import ZoneInfo
import numpy as np
from research_sleep_behavior_schedule import structure
from research_sleep_return_decision import replay
from research_sleep_ensemble import metrics


def cycle_features(source,data,zone,depth=3):
    tz=ZoneInfo(zone); sleeps=[]
    def parse(value): return dt.datetime.strptime(value,'%Y-%m-%d %H:%M').replace(tzinfo=tz).timestamp()
    for row in csv.DictReader(source.open(encoding='utf-8-sig')):
        if row['Type']!='Sleep' or not row.get('Start') or not row.get('End'): continue
        start,end=parse(row['Start']),parse(row['End'])
        if end>start: sleeps.append((start,end))
    sleeps.sort(key=lambda pair:pair[0]); values=[]
    for index,now in zip(data['indices'].astype(int),data['wakes']):
        assert abs(sleeps[index][1]-now)<1e-6
        history=[s for s in sleeps[:index+1] if s[1]<=now and s[0]>=now-7*86400]
        row=[]; broken=False
        for lag in range(1,depth+1):
            valid=not broken and len(history)>lag
            if valid:
                previous,following=history[-lag-1],history[-lag]
                valid=following[0]>=previous[1]
            if not valid:
                broken=True; row.extend([0.,0.,0.,0.,0.,1.]); continue
            local=dt.datetime.fromtimestamp(previous[1],tz); start_local=dt.datetime.fromtimestamp(previous[0],tz)
            minute=local.hour*60+local.minute+local.second/60
            night=start_local.hour>=19 or start_local.hour<6 or local.date()>start_local.date()
            row.extend([(previous[1]-previous[0])/60,(following[0]-previous[1])/60,np.sin(minute*2*np.pi/1440),np.cos(minute*2*np.pi/1440),float(night),0.])
        values.append(row)
    names=[f'cycleLag{lag}_{kind}' for lag in range(1,depth+1) for kind in ['sleepMinutes','followingAwakeMinutes','wakeSin','wakeCos','clockNight','missing']]
    return np.asarray(values,dtype=float),names


def compare(data,context,base,cycles):
    controls,control_diag,eligible,returned=replay(data,context,base)
    augmented=dict(context,X=np.column_stack([context['X'],cycles]))
    forecasts,diagnostics,new_eligible,new_returned=replay(data,augmented,base)
    np.testing.assert_array_equal(eligible,new_eligible)
    np.testing.assert_array_equal(returned,new_returned)
    forecasts={k.replace('returnDecision_','returnCycles_'):p for k,p in forecasts.items()}
    diagnostics={k.replace('returnDecision_','returnCycles_'):v for k,v in diagnostics.items()}
    return forecasts,diagnostics,controls,control_diag,eligible,returned


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','baseline','control-result','output']: ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--zone',default='America/Los_Angeles'); ap.add_argument('--limit',type=int); args=ap.parse_args(); root=Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root): ap.error('Keep private forecasts outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    baseline=json.loads(args.baseline.read_text()); old=json.loads(args.control_result.read_text())
    assert old['audit']['sourceSHA256']==baseline['audit']['sourceSHA256']==sha(args.source)
    assert old['audit']['scriptSHA256']==sha(root/'Scripts/research_sleep_return_decision.py')
    assert all(sha(root/'Scripts'/name)==h for name,h in old['audit']['helperFilesSHA256'].items())
    rows={e['index']:e for e in baseline['events']}; data=dict(np.load(args.features,allow_pickle=False)); n=len(data['y'])
    assert old['audit']['featureCacheSHA256']==sha(args.features) and old['audit']['baselineResultSHA256']==sha(args.baseline)
    if args.limit: data={k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in data.items()}
    np.testing.assert_allclose([rows[int(i)]['wakeMinutes'] for i in data['indices']],data['y'],rtol=0,atol=1e-6)
    base=(np.array([rows[int(i)]['prediction'] for i in data['indices']])-data['wakes'])/60
    context=structure(args.source,data,rows,args.zone); cycles,names=cycle_features(args.source,data,args.zone)
    forecasts,diag,controls,control_diag,eligible,returned=compare(data,context,base,cycles)
    for name,p in controls.items(): np.testing.assert_array_equal(p,[e['prediction'] for e in old['events'][name][:len(p)]])
    result=dict(audit=dict(sourceSHA256=sha(args.source),featureCacheSHA256=sha(args.features),baselineResultSHA256=sha(args.baseline),controlResultSHA256=sha(args.control_result),scriptSHA256=sha(Path(__file__)),
        helperFilesSHA256={name:sha(root/'Scripts'/name) for name in ['research_sleep_return_decision.py','research_sleep_behavior_schedule.py','research_sleep_ensemble.py']},careExposure='completed',
        strategy='Same frozen app-versus-short-return loss decision, adding three preceding completed sleep/wake cycles; eight matched original controls reproduced exactly',
        cycleFeatureNames=names,cycleRules='Three previous completed sleeps and their following already-finished awake gaps, within7days. Current completed segment remains in original context. A negative gap stops older cycle links and supplies missing indicators. No target merging or exclusion.',
        controlsReproducedExactly=True,eligibleAndReturnPointsUnchanged=True,controlDiagnostics=control_diag,diagnostics=diag,
        limitation='Exploratory post-selected cycle inputs motivated by prior matched-case audit; retrospective only, not independent future accuracy or a commercial method'),models={},events={})
    for name,p in forecasts.items():
        result['models'][name]=dict(all=metrics(data['y'],p,np.ones(len(p),dtype=bool)))
        result['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v),eligible=bool(e),shortReturnPoint=float(q)) for i,y,v,e,q in zip(data['indices'],data['y'],p,eligible,returned)]
        print(name,json.dumps(result['models'][name]),flush=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')


if __name__=='__main__': main()
