#!/usr/bin/env python3
"""Neutral local-clock initialization before completed-history neuronal forcing."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import numpy as np
from research_sleep_predictions import load_history
from research_sleep_neural_observer import make_input
from research_sleep_behavior_schedule import structure
from research_sleep_planning import planning_mask
from research_sleep_planning_mechanistic import select_planning,blend_planning
from research_sleep_ensemble import metrics


def replay(data,context,base,bank):
    output={};diag={}
    for local in (False,True):
        name='entrainedObserver'+('Local' if local else 'Global')
        output[name],diag[name]=select_planning(data,context,bank,base,local)
    for local in (False,True):
        name='entrainedBlend'+('Local' if local else 'Global')
        output[name],diag[name]=blend_planning(data,context,output['entrainedObserverLocal'],base,local)
    return output,diag


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ('source','features','baseline','binary','output'):ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--limit',type=int);args=ap.parse_args();root=Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root):ap.error('Keep private states and forecasts outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    app=json.loads(args.baseline.read_text());assert app['audit']['sourceSHA256']==sha(args.source)
    with np.load(args.features,allow_pickle=False) as cache:data=dict(cache)
    n=len(data['y'])
    if args.limit:data={k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in data.items()}
    rows={e['index']:e for e in app['events']};context=structure(args.source,data,rows,'America/Los_Angeles')
    base=(np.array([rows[int(i)]['prediction'] for i in data['indices']])-data['wakes'])/60
    sleeps,_,_,_=load_history(args.source,'1970-01-01','America/Los_Angeles')
    np.testing.assert_array_equal(sleeps[data['indices'].astype(int),1],data['wakes'])
    inputPath=args.output.with_suffix('.input.tsv');inputPath.write_text(make_input(sleeps,data['wakes'],'America/Los_Angeles'))
    statesPath=args.output.with_suffix('.states.json')
    with statesPath.open('w') as handle:subprocess.run([str(args.binary),str(inputPath),'1','60','56'],stdout=handle,check=True)
    raw=np.asarray(json.loads(statesPath.read_text()));assert raw.shape==(len(base),14,5) and np.isfinite(raw).all()
    predictions,diag=replay(data,context,base,raw[:,:,0])
    masks=dict(planning=planning_mask(data,context),naps=planning_mask(data,context)&(context['labels']==1),bedtime=planning_mask(data,context)&(context['labels']==2),allTimers=np.ones(len(base),bool))
    result=dict(audit=dict(sourceSHA256=sha(args.source),scriptSHA256=sha(Path(__file__)),featureSHA256=sha(args.features),baselineSHA256=sha(args.baseline),binarySHA256=sha(args.binary),coreSHA256=sha(root/'Scripts/SleepReplay/NeuralSleepCore.cpp'),initializationSHA256=sha(root/'Scripts/SleepReplay/NeuralSleepEntrainedObserver.cpp'),inputSHA256=sha(inputPath),statesSHA256=sha(statesPath),
        helperSHA256={name:sha(root/'Scripts'/name) for name in ('research_sleep_predictions.py','research_sleep_neural_observer.py','research_sleep_neural_dynamics.py','research_sleep_behavior_schedule.py','research_sleep_planning.py','research_sleep_planning_mechanistic.py','research_sleep_ensemble.py')},
        diagnostics=diag,training=dict(days=60,halfLifeDays=14,minimumResolvedPlanningLabels=40),
        initialization=dict(neutralDays=56,assumedWakeStartHour=7,assumedWakeEndHour=19,clockTraceStepMinutes=1,forcingStepSeconds=60,forecastStepSeconds=1,completedHistoryDays=7),
        strategy='Initialize slow states from a neutral fixed-schedule simulation sampled at the known local clock at the start of each completed-history window. Force the same completed sleep union and release the unchanged full six-state equations. Select members on past planning errors; optionally blend originally issued local forecasts with app points.',
        limitation='Assumed light and neutral schedule, not measured physiology, estimated latent phase, or a reproduction of the published weekly probability fit. Retrospective archive-selected research only.'),models={},events={})
    for name,p in dict(appV8=base,**predictions).items():
        result['models'][name]={key:metrics(data['y'],p,m) for key,m in masks.items()}
        result['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(data['indices'],data['y'],p)]
        print(name,json.dumps(result['models'][name]['planning']),flush=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')


if __name__=='__main__':main()
