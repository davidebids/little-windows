#!/usr/bin/env python3
"""Planning-only boosting with a fixed five-day diary representation."""
import argparse
import csv
import datetime as dt
import hashlib
import json
from pathlib import Path
from zoneinfo import ZoneInfo
import numpy as np
from sklearn.ensemble import HistGradientBoostingRegressor
from threadpoolctl import threadpool_limits
from research_sleep_behavior_schedule import structure
from research_sleep_planning import eligible, planning_mask
from research_sleep_ensemble import metrics


def sleep_observations(source, zone):
    tz=ZoneInfo(zone); result=[]
    def stamp(v):return dt.datetime.strptime(v,'%Y-%m-%d %H:%M').replace(tzinfo=tz).timestamp()
    with source.open(encoding='utf-8-sig') as handle:
        for row in csv.DictReader(handle):
            if row['Type']!='Sleep' or not row.get('Start') or not row.get('End'):continue
            a,b=stamp(row['Start']),stamp(row['End'])
            if b>a:result.append([a,b,False])
    result.sort(key=lambda v:v[0])
    for i,row in enumerate(result):
        a=dt.datetime.fromtimestamp(row[0],tz);b=dt.datetime.fromtimestamp(row[1],tz)
        row[2]=a.hour>=19 or a.hour<6 or a.date()<b.date()
        if not row[2] and a.hour<9 and i:row[2]=bool(result[i-1][2] and row[0]-result[i-1][1]<=90*60)
    return np.asarray(result,dtype=float)


def night_summary(history, day, tz):
    midnight=dt.datetime.combine(day,dt.time(),tzinfo=tz).timestamp()
    lower=dt.datetime.combine(day-dt.timedelta(days=1),dt.time(12),tzinfo=tz).timestamp()
    upper=dt.datetime.combine(day,dt.time(12),tzinfo=tz).timestamp()
    night=history[history[:,2]>0]
    minutes=float(np.maximum(0,np.minimum(night[:,1],upper)-np.maximum(night[:,0],lower)).sum()/60)
    ends=night[(night[:,1]>=midnight)&(night[:,1]<=upper),1]
    end=float(ends.max()) if len(ends) else np.nan
    clock=(dt.datetime.fromtimestamp(end,tz).hour*60+dt.datetime.fromtimestamp(end,tz).minute) if np.isfinite(end) else np.nan
    return end,clock,minutes


def diary_features(data, context, sleeps, zone='America/Los_Angeles'):
    tz=ZoneInfo(zone); n=len(data['y']); out=np.full((n,69),np.nan)
    planning=planning_mask(data,context); dates=np.array([dt.date.fromisoformat(v) for v in context['day']],dtype=object)
    positions=np.minimum(context['ordinal'].astype(int),5)
    clocks=(context['targetClock']-1080+720)%1440-720+1080
    values=np.column_stack([data['y'],context['X'][:,5],context['wakeClock'],clocks])
    for i,now in enumerate(data['wakes']):
        today=dates[i]; first=today-dt.timedelta(days=5)
        known=np.flatnonzero((np.arange(n)<i)&planning&(context['knownAt']<=now)&(dates>=first)&(dates<today))
        for block,chosen in enumerate([known,known[dates[known]==today-dt.timedelta(days=1)]]):
            for position in range(6):
                selected=chosen[positions[chosen]==position]; offset=block*30+position*5
                out[i,offset+4]=len(selected)
                if len(selected):out[i,offset:offset+4]=values[selected].mean(axis=0)
        history=sleeps[(sleeps[:,0]<=now)&(sleeps[:,1]<=now)]
        end,clock,night=night_summary(history,today,tz)
        if np.isfinite(end):
            nap=history[history[:,2]==0]
            day_nap=np.maximum(0,np.minimum(nap[:,1],now)-np.maximum(nap[:,0],end)).sum()/60
            out[i,60:64]=[clock,(now-end)/60,night,day_nap]
        else:out[i,62]=night
        summaries=[night_summary(history,today-dt.timedelta(days=k),tz) for k in range(1,6)]
        out[i,64:67]=[summaries[0][1],summaries[0][2],np.mean([v[2] for v in summaries])]
        totals=[]
        for k in range(1,6):
            selected=known[dates[known]==today-dt.timedelta(days=k)]
            if len(selected):totals.append(float(data['y'][selected].sum()))
        if len(totals):out[i,67]=np.mean(totals)
        yesterday=known[dates[known]==today-dt.timedelta(days=1)]
        if len(yesterday):out[i,68]=data['y'][yesterday].sum()
    return out


def factory(kind):
    if kind=='histogram':
        return HistGradientBoostingRegressor(loss='absolute_error',max_iter=200,learning_rate=.05,
            max_leaf_nodes=7,min_samples_leaf=8,l2_regularization=10,early_stopping=False,random_state=42)
    if kind=='lightgbm':
        from lightgbm import LGBMRegressor
        return LGBMRegressor(objective='regression_l1',n_estimators=200,learning_rate=.05,num_leaves=7,
            min_child_samples=8,reg_lambda=10,random_state=42,n_jobs=1,verbosity=-1,deterministic=True,force_col_wise=True)
    raise ValueError('Unknown learner')


def replay(data,context,base,diary,progress=None,iterations=None):
    compact=np.column_stack([data['X'],context['X'][:,5:8]]);outputs={};diagnostics={}
    daytime=(context['wakeClock']>=360)&(context['wakeClock']<1260)
    with threadpool_limits(limits=1):
        for kind in ['histogram','lightgbm']:
            for design,X in [('compact',compact),('diary',np.column_stack([compact,diary]))]:
                p=base.copy(); model=None; fitted=-24;fits=learned=0;maximum_dropped=0
                for i,now in enumerate(data['wakes']):
                    known=eligible(data,context,i,True)
                    if len(known)<40:continue
                    if model is None or i-fitted>=24:
                        model=factory(kind)
                        if iterations is not None:model.set_params(**({'max_iter':iterations} if kind=='histogram' else {'n_estimators':iterations}))
                        weights=np.exp2(-(now-data['wakes'][known])/(14*86400))
                        columns=np.flatnonzero(np.isfinite(X[known]).any(axis=0))
                        maximum_dropped=max(maximum_dropped,X.shape[1]-len(columns))
                        model.fit(X[known][:,columns],data['y'][known],sample_weight=weights)
                        fitted=i;fits+=1
                    if daytime[i]:
                        query=X[i:i+1,columns]
                        point=float(model.booster_.predict(query,num_threads=1)[0] if kind=='lightgbm' else model.predict(query)[0])
                        if not np.isfinite(point):raise ValueError('Nonfinite forecast')
                        p[i]=np.clip(point,1,480);learned+=1
                name=f'{kind}_{design}';outputs[name]=p;diagnostics[name]=dict(refits=fits,learnedQueries=learned,fallbackQueries=len(p)-learned,features=X.shape[1],maximumDroppedAllMissingColumns=maximum_dropped)
                if progress:progress(name,diagnostics[name])
    return outputs,diagnostics



def positioned_replay(data,context,base,diary,iterations=None):
    X=np.column_stack([data['X'],context['X'][:,5:8]])
    groups=np.minimum(context['ordinal'].astype(int),5)
    positions=base.copy();recent=base.copy();models={};columns={};fitted={};fits=0;learned=means=0
    day=(context['wakeClock']>=360)&(context['wakeClock']<1260)
    with threadpool_limits(limits=1):
        for i,now in enumerate(data['wakes']):
            known=eligible(data,context,i,True)
            if len(known)<40:continue
            group=int(groups[i]);offset=group*5
            if day[i] and diary[i,offset+4]>=3 and np.isfinite(diary[i,offset]):
                recent[i]=np.clip(diary[i,offset],1,480);means+=1
            local=known[groups[known]==group]
            if len(local)<20:continue
            if group not in models or i-fitted[group]>=24:
                columns[group]=np.flatnonzero(np.isfinite(X[local]).any(axis=0))
                model=factory('lightgbm')
                if iterations is not None:model.set_params(n_estimators=iterations)
                weights=np.exp2(-(now-data['wakes'][local])/(14*86400))
                models[group]=model.fit(X[local][:,columns[group]],data['y'][local],sample_weight=weights)
                fitted[group]=i;fits+=1
            if day[i]:
                point=float(models[group].booster_.predict(X[i:i+1,columns[group]],num_threads=1)[0])
                if not np.isfinite(point):raise ValueError('Nonfinite positioned forecast')
                positions[i]=np.clip(point,1,480);learned+=1
    return dict(lightgbm_byPosition=positions,recentMean5_byPosition=recent),dict(lightgbm_byPosition=dict(refits=fits,learnedQueries=learned),recentMean5_byPosition=dict(learnedQueries=means))


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','baseline','output']:ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--limit',type=int);args=ap.parse_args();root=Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root):ap.error('Keep private results outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    app=json.loads(args.baseline.read_text());assert app['audit']['sourceSHA256']==sha(args.source)
    d=dict(np.load(args.features,allow_pickle=False));n=len(d['y'])
    if args.limit:d={k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in d.items()}
    rows={e['index']:e for e in app['events']}
    np.testing.assert_allclose([rows[int(i)]['wakeMinutes'] for i in d['indices']],d['y'],rtol=0,atol=1e-6)
    np.testing.assert_allclose([rows[int(i)]['actual'] for i in d['indices']],d['available'],rtol=0,atol=1e-6)
    context=structure(args.source,d,rows,'America/Los_Angeles')
    base=(np.array([rows[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60
    sleeps=sleep_observations(args.source,'America/Los_Angeles');diary=diary_features(d,context,sleeps)
    predictions,diag=replay(d,context,base,diary,lambda name,v:print(name,json.dumps(v),flush=True))
    extra_predictions,extra_diag=positioned_replay(d,context,base,diary)
    predictions.update(extra_predictions);diag.update(extra_diag)
    import sklearn,lightgbm
    mask=planning_mask(d,context);masks=dict(planning=mask,naps=mask&(context['labels']==1),bedtime=mask&(context['labels']==2),allTimers=np.ones(len(mask),bool))
    result=dict(audit=dict(sourceSHA256=sha(args.source),scriptSHA256=sha(Path(__file__)),featuresSHA256=sha(args.features),baselineSHA256=sha(args.baseline),
        libraryVersions=dict(sklearn=sklearn.__version__,lightgbm=lightgbm.__version__),modelParameters={kind:factory(kind).get_params() for kind in ['histogram','lightgbm']},
        strategy='Two fixed absolute-loss boosting learners plus separate LightGBM models by known logical nap order and a direct five-day same-position mean control; compact28 versus additional69 previous-five-calendar-day/nap-position/night-anchor diary features.',
        training=dict(days=60,halfLifeDays=14,minimumResolvedPlanningLabels=40,refitQueries=24,iterations=200,positionModelMinimumLabels=20,positionMeanMinimumLabels=3),
        missingValues='Drop only columns all-missing in the current training set; freeze that column selection until refit. Remaining missing values use each learner native handling. Single-thread training/prediction.',
        forecastRule='Emit at every wake; learned points only06..21. Preserve actual app overnight and sparse-history forecasts. Current target never selects model or features.',
        diary='Six logical positions (5+ pooled): five-day and yesterday means of resolved planning intervals, prior episode duration, wake clock and unwrapped target clock, with counts; completed night/day anchors and previous-day totals.',
        limitation='Independent adaptation of public modeling ideas, not proprietary pretrained population models or expert tables; no comparable product accuracy established; retrospective one-archive exploration.',
        sourceURLs=['https://patents.justia.com/patent/20250292903','https://lightgbm.readthedocs.io/en/stable/Parameters.html','https://scikit-learn.org/stable/modules/generated/sklearn.ensemble.HistGradientBoostingRegressor.html'],
        helperSHA256={name:sha(root/'Scripts'/name) for name in ['research_sleep_behavior_schedule.py','research_sleep_planning.py','research_sleep_ensemble.py']},diagnostics=diag),models={},events={})
    for name,p in {'appV8':base,**predictions}.items():
        result['models'][name]={key:metrics(d['y'],p,m) for key,m in masks.items()}
        result['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(d['indices'],d['y'],p)]
        print(name,json.dumps(result['models'][name]['planning']),flush=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')

if __name__=='__main__':main()
