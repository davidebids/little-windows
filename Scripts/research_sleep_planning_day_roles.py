#!/usr/bin/env python3
"""Past-completed-day wake-window medians by start and end-relative nap roles."""
import argparse
from collections import Counter,defaultdict
import datetime as dt
import hashlib
import json
from pathlib import Path
from zoneinfo import ZoneInfo
import numpy as np
from research_sleep_behavior_schedule import structure,weighted_median
from research_sleep_planning import planning_mask
from research_sleep_ensemble import metrics


def model_at(data,context,index):
    now=data['wakes'][index];today=dt.date.fromisoformat(str(context['day'][index]))
    lower=(today-dt.timedelta(days=14)).isoformat();day=context['day']
    known=np.flatnonzero((np.arange(len(data['y']))<index)&planning_mask(data,context)&
        (context['knownAt']<=now)&(day>=lower)&(day<today.isoformat()))
    by_day=defaultdict(list)
    for j in known:by_day[str(day[j])].append(int(j))
    closed=[]
    for date,rows in sorted(by_day.items()):
        bed=[j for j in rows if context['labels'][j]==2]
        if not bed:continue
        count=int(max(context['ordinal'][bed]))
        if count>=1:closed.append((date,rows,bed,count))
    closed=closed[-7:]
    if len(closed)<3:return None
    counts=Counter(v[3] for v in closed);maximum=max(counts.values())
    mode=next(v[3] for v in reversed(closed) if counts[v[3]]==maximum)
    ordinal=defaultdict(list);start=defaultdict(list);penultimate=[];all_naps=[];bedtime=[];clocks=[]
    for date,rows,bed,count in closed:
        for j in rows:
            if context['labels'][j]!=1 or str(context['targetDay'][j])!=date:continue
            position=int(context['ordinal'][j])
            if not 0<=position<count:continue
            value=float(data['y'][j]);ordinal[position].append(value);all_naps.append(value)
            if position==count-1:penultimate.append(value)
            else:start[position].append(value)
        bedtime.extend(float(data['y'][j]) for j in bed)
        clocks.extend(float((context['targetClock'][j]-1080+720)%1440-720+1080) for j in bed)
    if not all_naps or not bedtime:return None
    return dict(mode=mode,counts=dict(counts),ordinal=dict(ordinal),start=dict(start),
        penultimate=penultimate,allNaps=all_naps,bedtime=bedtime,bedtimeClock=float(np.median(clocks)),days=len(closed))


def pool_for(model,position,count,end_relative):
    if position>=count:return model['bedtime']
    if end_relative and position==count-1 and model['penultimate']:return model['penultimate']
    group=model['start'] if end_relative else model['ordinal']
    return group.get(position,model['allNaps'])


def replay(data,context,base):
    output={name:base.copy() for name in ('ordinalMode','endRelativeMode','endRelativeCountMixture','endRelativeClockAnchor')}
    learned=warmup=0;counts_used=Counter()
    for i in range(len(base)):
        clock=context['wakeClock'][i]
        if not 360<=clock<1260:continue
        model=model_at(data,context,i)
        if model is None:continue
        position=int(context['ordinal'][i]);count=model['mode'];counts_used[count]+=1
        normal=float(np.median(pool_for(model,position,count,False)))
        end_relative=float(np.median(pool_for(model,position,count,True)))
        values=[];weights=[]
        for n,frequency in model['counts'].items():
            samples=pool_for(model,position,n,True);values.extend(samples)
            weights.extend([frequency/len(samples)]*len(samples))
        mixed=weighted_median(np.asarray(values),np.asarray(weights))
        anchor=end_relative
        if position>=count or clock+end_relative>=model['bedtimeClock']-30:
            anchor=model['bedtimeClock']-clock
        for name,value in zip(output,(normal,end_relative,mixed,anchor)):output[name][i]=np.clip(value,1,480)
        learned+=1
        known=np.flatnonzero((np.arange(len(base))<i)&planning_mask(data,context)&
            (context['knownAt']<=data['wakes'][i])&(data['wakes']>=data['wakes'][i]-60*86400))
        warmup+=int(len(known)<40)
    return output,dict(learnedQueries=learned,changedPolicyDuringSparsePlanningHistory=warmup,
        modeNapCounts={str(k):v for k,v in sorted(counts_used.items())})


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ('source','features','baseline','output'):ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--limit',type=int);args=ap.parse_args();root=Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root):ap.error('Keep private replay results outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    app=json.loads(args.baseline.read_text());assert app['audit']['sourceSHA256']==sha(args.source)
    with np.load(args.features,allow_pickle=False) as cache:data=dict(cache)
    n=len(data['y'])
    if args.limit:data={k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in data.items()}
    rows={e['index']:e for e in app['events']}
    np.testing.assert_allclose([rows[int(i)]['wakeMinutes'] for i in data['indices']],data['y'],rtol=0,atol=1e-6)
    np.testing.assert_allclose((data['available']-data['wakes'])/60,data['y'],rtol=0,atol=1e-6)
    context=structure(args.source,data,rows,'America/Los_Angeles')
    zone=ZoneInfo('America/Los_Angeles');context['targetDay']=np.array([dt.datetime.fromtimestamp(v,zone).date().isoformat() for v in data['available']])
    base=(np.array([rows[int(i)]['prediction'] for i in data['indices']])-data['wakes'])/60
    forecasts,diag=replay(data,context,base)
    masks=dict(planning=planning_mask(data,context),naps=planning_mask(data,context)&(context['labels']==1),bedtime=planning_mask(data,context)&(context['labels']==2),allTimers=np.ones(len(base),bool))
    result=dict(audit=dict(sourceSHA256=sha(args.source),scriptSHA256=sha(Path(__file__)),featureSHA256=sha(args.features),baselineSHA256=sha(args.baseline),
        helperSHA256={name:sha(root/'Scripts'/name) for name in ('research_sleep_behavior_schedule.py','research_sleep_planning.py','research_sleep_ensemble.py')},
        diagnostics=diag,training=dict(maximumCompletedDays=7,calendarLookbackDays=14,minimumCompletedDays=3),
        strategy='Closed historical days require a resolved bedtime planning transition and at least one known logical nap. Pool gaps by ordinal or relative-to-last-nap role. Forecast nap count from past modal count, or mix over the observed count distribution. A separate anchor variant uses only historical bedtime clocks.',
        causalRule='Only previous local calendar days, earlier rows and target-ended labels train the pools. Current/future nap count, target kind and clock never select the current forecast. Historical cross-date nap intervals do not train within-day roles. Every original evaluation case remains.',
        limitation='Independent adaptation of public schedule-pooling ideas, not another app reproduction or measured accuracy claim. Timing categories are importer-derived proxies. Retrospective archive-selected comparison, not prospective validation.'),models={},events={})
    for name,p in dict(appV8=base,**forecasts).items():
        result['models'][name]={key:metrics(data['y'],p,m) for key,m in masks.items()}
        result['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(data['indices'],data['y'],p)]
        print(name,json.dumps(result['models'][name]['planning']),flush=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')


if __name__=='__main__':main()
