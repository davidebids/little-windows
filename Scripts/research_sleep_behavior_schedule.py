#!/usr/bin/env python3
"""Interpretable recent-pattern return/nap/bedtime schedule experiment."""
import argparse
import csv
import datetime as dt
import hashlib
import json
from pathlib import Path
from zoneinfo import ZoneInfo
import numpy as np
from sklearn.tree import DecisionTreeClassifier
from research_sleep_ensemble import metrics


def structure(source,data,rows,zone):
    tz=ZoneInfo(zone); sleeps=[]
    def stamp(value): return dt.datetime.strptime(value,'%Y-%m-%d %H:%M').replace(tzinfo=tz).timestamp()
    for row in csv.DictReader(source.open(encoding='utf-8-sig')):
        if row['Type']!='Sleep' or not row.get('Start') or not row.get('End'): continue
        start,end=stamp(row['Start']),stamp(row['End'])
        if end>start: sleeps.append([start,end,False])
    sleeps.sort(key=lambda s:s[0])
    for i,s in enumerate(sleeps):
        local=dt.datetime.fromtimestamp(s[0],tz); end=dt.datetime.fromtimestamp(s[1],tz)
        s[2]=local.hour>=19 or local.hour<6 or end.date()>local.date()
        if not s[2] and local.hour<9 and i:
            s[2]=sleeps[i-1][2] and s[0]-sleeps[i-1][1]<=90*60
    X=[]; labels=[]; known_at=[]; target_clock=[]; wake_clock=[]; day=[]; ordinal=[]
    names=list(data['names'])
    for k,index in enumerate(data['indices'].astype(int)):
        current,target=sleeps[index],sleeps[index+1]; now=float(data['wakes'][k])
        assert abs(current[1]-now)<1e-6 and abs(target[0]-float(data['available'][k]))<1e-6
        assert ('night' if target[2] else 'nap')==rows[int(index)]['actualKind']
        history=[s for s in sleeps[:index+1] if s[1]<=now]
        local=dt.datetime.fromtimestamp(now,tz); midnight=local.replace(hour=0,minute=0,second=0,microsecond=0).timestamp()
        minute=local.hour*60+local.minute+local.second/60
        count=0; previous=None
        for s in history:
            if s[0]>=midnight and not s[2]:
                joined=previous is not None and not previous[2] and 0<=s[0]-previous[1]<=20*60
                if not joined: count+=1
            previous=s
        begin=len(history)-1
        while begin and 0<=history[begin][0]-history[begin-1][1]<=20*60: begin-=1
        duration=(current[1]-current[0])/60
        total=sum((s[1]-s[0])/60 for s in history[begin:])
        values=[data['X'][k,names.index(name)] for name in ['ageDays','wakeLag1','sleepMinutes6h','sleepMinutes24h']]
        X.append([values[0],np.sin(minute*2*np.pi/1440),np.cos(minute*2*np.pi/1440),float(current[2]),duration,total,len(history)-begin,count,*values[1:]])
        labels.append(0 if data['y'][k]<=20 or (current[2] and target[2]) else (2 if target[2] else 1))
        known_at.append(target[1]) # Clock/continuity type may depend on completed target sleep.
        nextlocal=dt.datetime.fromtimestamp(target[0],tz)
        target_clock.append(nextlocal.hour*60+nextlocal.minute+nextlocal.second/60)
        wake_clock.append(minute); day.append(local.date().isoformat()); ordinal.append(count)
    X=np.asarray(X,dtype=float)
    return dict(X=np.where(np.isfinite(X),X,0.),labels=np.asarray(labels),knownAt=np.asarray(known_at),targetClock=np.asarray(target_clock),wakeClock=np.asarray(wake_clock),day=np.asarray(day),ordinal=np.asarray(ordinal),
        featureNames=['ageDays','clockSin','clockCos','precedingNight','lastSegmentMinutes','completedEpisodeSleepMinutes','completedEpisodeSegments','completedNapEpisodesToday','wakeLag1','sleepMinutes6h','sleepMinutes24h'])


def weighted_median(values,weights):
    order=np.argsort(values,kind='stable'); values=np.asarray(values)[order]; weights=np.asarray(weights)[order]
    return float(values[min(len(values)-1,np.searchsorted(np.cumsum(weights),weights.sum()/2))])


def replay(data,context,base):
    X=context['X']; labels=context['labels']; n=len(base); outputs={}; diagnostics={}
    for days in [5,14]:
        predictions={key:base.copy() for key in ['pooled','routedGap','routedBedtimeClock','softBedtimeClock']}
        gate_correct=learned=0; class_counts=np.zeros(3,dtype=int); confusion=np.zeros((3,3),dtype=int)
        for i,now in enumerate(data['wakes']):
            known=np.flatnonzero((np.arange(n)<i)&(data['available']<=now)&(context['knownAt']<=now)&(data['wakes']>=now-28*86400))
            if len(known)<20 or len(set(context['day'][known]))<5: continue
            gate_weights=np.exp2(-(now-data['wakes'][known])/(7*86400))
            tree=DecisionTreeClassifier(criterion='log_loss',max_depth=3,min_samples_leaf=8,random_state=42)
            tree.fit(X[known],labels[known],sample_weight=gate_weights)
            probabilities=np.zeros(3); probabilities[tree.classes_.astype(int)]=tree.predict_proba(X[i:i+1])[0]
            predicted=int(np.argmax(probabilities)); confusion[labels[i],predicted]+=1; gate_correct+=int(predicted==labels[i]); class_counts[predicted]+=1
            recent=known[data['wakes'][known]>=now-days*86400]
            if len(recent)<10: recent=known
            def weights(indices):
                delta=np.mod(context['wakeClock'][indices]-context['wakeClock'][i]+720,1440)-720
                w=np.exp2(-(now-data['wakes'][indices])/(days*86400))
                w*=.1+.9*np.exp(-.5*(delta/180)**2)
                w*=np.where(context['ordinal'][indices]==context['ordinal'][i],1.,.2)
                w*=np.where(X[indices,3]==X[i,3],1.,.1)
                w*=.1+.9*np.exp(-.5*(np.log1p(X[indices,5])-np.log1p(X[i,5]))**2/.7**2)
                return w
            predictions['pooled'][i]=weighted_median(data['y'][recent],weights(recent))
            distributions=[]; masses=[]; gap_points=[]; clock_points=[]
            for branch in range(3):
                indices=recent[labels[recent]==branch]
                if len(indices)<3: indices=known[labels[known]==branch]
                if not len(indices):
                    gap_points.append(base[i]); clock_points.append(base[i]); distributions.append(np.array([base[i]])); masses.append(np.array([probabilities[branch]])); continue
                w=weights(indices); w/=w.sum(); gaps=data['y'][indices]
                gap_points.append(weighted_median(gaps,w))
                values=gaps if branch!=2 else np.clip(np.mod(context['targetClock'][indices]-context['wakeClock'][i]+720,1440)-720,1,480)
                clock_points.append(weighted_median(values,w)); distributions.append(values); masses.append(w*probabilities[branch])
            predictions['routedGap'][i]=gap_points[predicted]
            predictions['routedBedtimeClock'][i]=clock_points[predicted]
            predictions['softBedtimeClock'][i]=weighted_median(np.concatenate(distributions),np.concatenate(masses))
            learned+=1
        for key,p in predictions.items(): outputs[f'behaviorSchedule_d{days}_{key}']=np.clip(p,1,480)
        diagnostics[str(days)]=dict(learnedQueries=learned,fallbackQueries=n-learned,gateAccuracyPercent=100*gate_correct/learned if learned else None,predictedBranchCounts=class_counts.tolist(),actualByPredictedConfusion=confusion.tolist())
    return outputs,diagnostics


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','baseline','output']: ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--zone',default='America/Los_Angeles'); ap.add_argument('--limit',type=int)
    args=ap.parse_args(); root=Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root): ap.error('Keep personal forecasts outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    baseline=json.loads(args.baseline.read_text()); assert baseline['audit']['sourceSHA256']==sha(args.source)
    rows={e['index']:e for e in baseline['events']}; data=dict(np.load(args.features,allow_pickle=False)); n=len(data['y'])
    if args.limit: data={k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in data.items()}
    base=(np.array([rows[int(i)]['prediction'] for i in data['indices']])-data['wakes'])/60
    np.testing.assert_allclose([rows[int(i)]['wakeMinutes'] for i in data['indices']],data['y'],rtol=0,atol=1e-6)
    context=structure(args.source,data,rows,args.zone); forecasts,diag=replay(data,context,base)
    result=dict(audit=dict(sourceSHA256=sha(args.source),featureCacheSHA256=sha(args.features),baselineResultSHA256=sha(args.baseline),scriptSHA256=sha(Path(__file__)),helperFilesSHA256={'research_sleep_ensemble.py':sha(root/'Scripts/research_sleep_ensemble.py')},careExposure='completed',
        strategy='Learned return/nap/bedtime gate, recent empirical wake windows by logical nap ordinal, bedtime clock distribution; same timer-start targets retained',
        gate=dict(historyDays=28,halfLifeDays=7,maximumDepth=3,minimumLeaf=8,minimumLabels=20,minimumDistinctDays=5),componentHistoryDays=[5,14],
        featureNames=context['featureNames'],labels='Return: gap<=20 or night-to-night; nap: remaining daytime; bedtime: remaining night. Training label is delayed until target sleep ends because clock/continuity proxy may depend on it.',
        napEpisodes='Completed history only; successive daytime timer segments within20 minutes count as one prior episode for ordinal, without merging or removing forecast targets',diagnostics=diag,
        limitation='Independent transparent schedule experiment, not a proprietary algorithm replication. Nap/night labels are importer-derived proxies; retrospective only.'),models={},events={})
    for name,p in forecasts.items():
        result['models'][name]=dict(all=metrics(data['y'],p,np.ones(len(p),dtype=bool)))
        result['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(data['indices'],data['y'],p)]
        print(name,json.dumps(result['models'][name]),flush=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')


if __name__=='__main__': main()
