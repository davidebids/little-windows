#!/usr/bin/env python3
"""Causal forecast adaptation of neutral six-state model clock templates."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from threadpoolctl import threadpool_limits
from research_sleep_ensemble import combine,metrics


def template_forecasts(data,bank):
    names=list(data['names']);X=data['X']
    clock=np.mod(np.arctan2(X[:,names.index('clockSin1')],X[:,names.index('clockCos1')]),2*np.pi)*1440/(2*np.pi)
    clock=np.mod(np.round(clock,9),1440)
    outputs={k:[] for k in ['nextOnset','sleepOpportunity','awakeConditional']}
    for model in bank['models']:
        onset=np.asarray(model['onsetsHours']);wake=np.asarray(model['wakesHours'])
        assert len(onset) and np.all(np.diff(onset)>0) and np.all(np.diff(wake)>0)
        for shift in [-120.,0.,120.]:
            t=(np.arange(14)[None,:]*1440+np.mod(clock[:,None]+shift,1440))/60
            index=np.searchsorted(onset,t,side='right')
            future=np.r_[onset,np.inf][index]
            gaps=np.clip((future-t)*60,1,480)
            state=int(model['initialWake'])+np.searchsorted(wake,t,side='right')-np.searchsorted(onset,t,side='right')
            assert np.isin(state,[0,1]).all()
            awake=state==1
            # Use a lower median: it is an L1-optimal discrete sample decision,
            # including when simulated days split between two distinct modes.
            ordinary=np.partition(gaps,6,axis=1)[:,6]
            opportunity=np.partition(np.where(awake,gaps,1.),6,axis=1)[:,6]
            count=awake.sum(axis=1);conditional=ordinary.copy();valid=count>0
            values=np.sort(np.where(awake[valid],gaps[valid],np.inf),axis=1)
            conditional[valid]=values[np.arange(sum(valid)),(count[valid]-1)//2]
            for key,v in [('nextOnset',ordinary),('sleepOpportunity',opportunity),('awakeConditional',conditional)]:outputs[key].append(v)
    return {k:np.column_stack(v) for k,v in outputs.items()}


def select(data,bank,fallback,local,miss_penalty):
    output=fallback.copy();choice=np.full(len(fallback),-1,dtype=int)
    names=list(data['names']);X=data['X'];phase=np.arctan2(X[:,names.index('clockSin1')],X[:,names.index('clockCos1')])
    duration=X[:,names.index('lastDuration')];errors=np.abs(bank-data['y'][:,None])
    for i,now in enumerate(data['wakes']):
        known=np.flatnonzero((np.arange(len(fallback))<i)&(data['available']<=now)&(data['wakes']>=now-60*86400))
        if len(known)<40:continue
        weights=np.exp2(-(now-data['wakes'][known])/(14*86400))
        if local:
            angle=np.abs(phase[known]-phase[i]);clock_distance=np.minimum(angle,2*np.pi-angle)*1440/(2*np.pi)
            context=weights*np.exp(-clock_distance/120)*np.exp(-np.abs(np.log((duration[known]+10)/(duration[i]+10)))/.7)
            if context.sum()**2/max(1e-12,np.sum(context**2))>=8:weights=context
        risk=np.average(errors[known]+miss_penalty*(errors[known]>30),axis=0,weights=weights)
        choice[i]=int(np.argmin(risk));output[i]=bank[i,choice[i]]
    return output,dict(learnedQueries=int(sum(choice>=0)),fallbackQueries=int(sum(choice<0)),distinctSelectedTemplates=int(len(set(choice[choice>=0].tolist()))))


def replay(data,templates,fallback):
    outputs,diag={},{}
    with threadpool_limits(limits=2):
        for variant,bank in templates.items():
            for local in [False,True]:
                for penalty in [0,30]:
                    name=f'neural_{variant}_{"local" if local else "global"}_{"risk" if penalty else "mae"}'
                    outputs[name],diag[name]=select(data,bank,fallback,local,penalty)
        members=np.column_stack([fallback,*outputs.values()])
        for name,policy,cal,local in [('localCalibratedSoft','soft',True,True),('localCalibratedBest','best',True,True),
            ('localRawSoft','soft',False,True),('globalCalibratedSoft','soft',True,False),('calibratedMedian','median',True,True)]:
            outputs['neuralCombination_'+name]=combine(data,members,policy,cal,local)
    return outputs,diag


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','baseline','bank','bank-check','output']:parser.add_argument('--'+name,type=Path,required=True)
    args=parser.parse_args();root=Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root):parser.error('Keep private forecasts outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    bank=json.loads(args.bank.read_text());check=json.loads(args.bank_check.read_text());assert check['passed'] and check['bankSHA256']==sha(args.bank)
    assert bank['coreSourceSHA256']==sha(Path(__file__).parent/'SleepReplay/NeuralSleepCore.cpp')
    assert check['builderSHA256']==sha(Path(__file__).parent/'build_sleep_neural_bank.py')
    data=dict(np.load(args.features,allow_pickle=False));base=json.loads(args.baseline.read_text());assert sha(args.source)==base['audit']['sourceSHA256']
    by={r['index']:r for r in base['events']};indices=data['indices'].astype(int).tolist();assert set(by)==set(indices)
    np.testing.assert_allclose([by[i]['actual'] for i in indices],data['available'],rtol=0,atol=1e-6)
    np.testing.assert_allclose([by[i]['wakeMinutes'] for i in indices],data['y'],rtol=0,atol=1e-6)
    app=(np.array([by[i]['prediction'] for i in indices])-data['wakes'])/60
    templates=template_forecasts(data,bank);forecasts,diag=replay(data,templates,app)
    result=dict(audit=dict(sourceSHA256=sha(args.source),careExposure='completed',scriptSHA256=sha(Path(__file__)),featureCacheSHA256=sha(args.features),baselineResultSHA256=sha(args.baseline),bankSHA256=sha(args.bank),bankCheckSHA256=sha(args.bank_check),
        coreSourceSHA256=bank['coreSourceSHA256'],upstreamFilesSHA256=bank['upstreamFilesSHA256'],helperFilesSHA256={'research_sleep_ensemble.py':sha(Path(__file__).parent/'research_sleep_ensemble.py')},
        modelSettings=bank['assumedLight'],stableParameterSets=len(bank['models']),templatesPerVariant=next(iter(templates.values())).shape[1],
        phaseOffsetsMinutes=[-120,0,120],lookbackDays=60,halfLifeDays=14,minimumLabels=40,refitEvery=1,diagnostics=diag,
        adaptation='Free-running neutral trajectories; fourteen simulated-day lower medians; past-label template selection; no neuronal-state measurement or history forcing',
        variants='Next onset; sleep opportunity if modeled asleep; model-day conditioning on awake with next-onset fallback',
        limitation='Paper fits weekly half-hour sleep probabilities; this timer-start forecast adaptation and assumed light are not a paper replication or infant accuracy guarantee',
        sourceURLs=['https://github.com/brain-modelling-group/infant-sleep-trajectory','https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1012541']),models={},events={})
    for name,p in forecasts.items():
        assert np.isfinite(p).all()
        result['models'][name]=dict(all=metrics(data['y'],p,np.ones(len(indices),dtype=bool)))
        result['events'][name]=[dict(index=i,actual=float(y),prediction=float(v)) for i,y,v in zip(indices,data['y'],p)]
        print(name,json.dumps(result['models'][name]),flush=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')


if __name__=='__main__':main()
