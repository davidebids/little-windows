#!/usr/bin/env python3
"""Test one external age-grid diary as a weak distinct-sleep planning prior.

Accepts an independently obtained CSV with clock hours down rows, age days in
columns, S=sleep, E=awake/feed, empty=awake. Unrecognized annotations break
history. No downloaded data or fitted parameters belong in the repository.
"""
import argparse
import csv
import datetime as dt
import hashlib
import json
from pathlib import Path
import numpy as np
from sklearn.ensemble import ExtraTreesRegressor
from sklearn.impute import SimpleImputer
from threadpoolctl import threadpool_limits
from research_sleep_predictions import feature_rows
from research_sleep_behavior_schedule import structure
from research_sleep_planning import eligible, planning_mask
from research_sleep_ensemble import metrics


def read_grid(path):
    with path.open(encoding='utf-8-sig') as handle:rows=list(csv.reader(handle))
    hours=np.array([float(row[0]) for row in rows[1:]])
    if len(hours)!=96 or not np.allclose(hours,np.arange(96)/4):
        raise ValueError('Expected 96 quarter-hour clock rows')
    ages=[];states=[]
    for column,header in enumerate(rows[0][1:],1):
        if not header.strip():
            if any(row[column].strip() for row in rows[1:]):raise ValueError('Unlabeled age column')
            continue
        age=int(header)
        if ages and age!=ages[-1]+1:raise ValueError('Noncontiguous age columns')
        ages.append(age)
        states.extend(1 if row[column].strip().upper()=='S' else
                      0 if row[column].strip().upper() in ('','E') else -1 for row in rows[1:])
    if not ages:raise ValueError('Empty diary')
    return ages[0],np.asarray(states,dtype=int)


def diary_blocks(first_age,states):
    """Exact grid boundaries; discard sleep runs censored by unknown states."""
    blocks=[];cursor=0
    while cursor<len(states):
        if states[cursor]<0:cursor+=1;continue
        stop=cursor
        while stop<len(states) and states[stop]>=0:stop+=1
        sleeps=[];i=cursor
        while i<stop:
            if states[i]!=1:i+=1;continue
            begin=i
            while i<stop and states[i]==1:i+=1
            if begin>cursor and i<stop:
                a=(first_age*96+begin)*900.;b=(first_age*96+i)*900.
                start_day=int(a//86400);end_day=int(b//86400);hour=int(a%86400//3600)
                night=hour>=19 or hour<6 or end_day>start_day
                if not night and hour<9 and sleeps:night=bool(sleeps[-1][2] and a-sleeps[-1][1]<=90*60)
                sleeps.append([a,b,float(night)])
        if len(sleeps)>=2:blocks.append((cursor,np.asarray(sleeps,float)))
        cursor=stop
    return blocks


def external_features(path,names):
    first,states=read_grid(path);all_x=[];all_y=[];total=0
    for offset,sleeps in diary_blocks(first,states):
        data=feature_rows(sleeps,[],0.,dt.timezone.utc)
        ix=np.asarray(data['indices'],int)
        # Two complete days of known states precede every external example.
        mask=(data['wakes']>=(first*96+offset)*900+2*86400)&(data['y']>20)
        mask&=(sleeps[ix,2]==0)|(sleeps[ix+1,2]==0)
        total+=len(ix)
        selected=[data['names'].index(str(name)) for name in names]
        compact=data['X'][:,selected]
        extra=[]
        for k,index in enumerate(ix):
            history=sleeps[:index+1];now=data['wakes'][k];begin=index
            while begin and 0<=sleeps[begin,0]-sleeps[begin-1,1]<=1200:begin-=1
            ordinal=0;previous=None;midnight=np.floor(now/86400)*86400
            for sleep in history:
                if sleep[0]>=midnight and not sleep[2]:
                    joined=previous is not None and not previous[2] and 0<=sleep[0]-previous[1]<=1200
                    if not joined:ordinal+=1
                previous=sleep
            extra.append([sum((s[1]-s[0])/60 for s in sleeps[begin:index+1]),index-begin+1,ordinal])
        if mask.any():
            all_x.append(np.column_stack([compact,np.asarray(extra)])[mask]);all_y.append(data['y'][mask])
    if not all_x:raise ValueError('No uncensored planning examples')
    X=np.concatenate(all_x);y=np.concatenate(all_y)
    return X,y,dict(firstAgeDay=first,lastAgeDay=first+len(states)//96-1,
        intervalMinutes=15,unknownCells=int((states<0).sum()),rawTransitions=total,
        planningExamples=len(y),warmupKnownHours=48,blocks=len(diary_blocks(first,states)))


class WeightedForest:
    """Weighted leaf distributions, with a median rather than mean action."""
    def fit(self,X,y,weights):
        self.imputer=SimpleImputer(keep_empty_features=True)
        x=self.imputer.fit_transform(X);self.y=y.copy();self.weights=weights.copy()
        self.model=ExtraTreesRegressor(n_estimators=80,min_samples_leaf=5,max_features=.8,random_state=42,n_jobs=1).fit(x,y,sample_weight=weights)
        self.leaves=self.model.apply(x)
        return self

    def predict(self,X):
        leaves=self.model.apply(self.imputer.transform(X));out=[]
        order=np.argsort(self.y,kind='stable')
        for query in leaves:
            same=(self.leaves==query)*self.weights[:,None]
            mass=(same/np.maximum(same.sum(axis=0),1e-300)).mean(axis=1)
            out.append(self.y[order[min(len(order)-1,np.searchsorted(np.cumsum(mass[order]),mass.sum()/2))]])
        return np.asarray(out)


def replay(data,context,base,donorX,donorY,progress=None):
    # Sleep-only inputs avoid treating different feeding logging conventions as equivalent.
    keep=[i for i,name in enumerate(data['names']) if name not in ('lastFeedMinutes','FeedCount3h')]
    columns=keep+list(range(len(data['names']),len(data['names'])+3))
    X=np.column_stack([data['X'],context['X'][:,5:8]])[:,columns];D=donorX[:,columns]
    lower,upper=float(D[:,0].min()),float(D[:,0].max())
    scope=(X[:,0]>=lower)&(X[:,0]<=upper)&(context['wakeClock']>=360)&(context['wakeClock']<1260)
    donor=WeightedForest().fit(D,donorY,np.ones(len(donorY)))
    prior=donor.predict(X)
    outputs={name:base.copy() for name in ('externalOnly','personalSleepOnly','externalResidual','externalMass20')}
    outputs['externalOnly'][scope]=np.clip(prior[scope],1,480)
    diagnostics={};models={};fitted={};fits={name:0 for name in outputs};counts={name:0 for name in outputs}
    with threadpool_limits(limits=1):
        for i,now in enumerate(data['wakes']):
            known=eligible(data,context,i,True)
            if len(known)<40:continue
            for name in ('personalSleepOnly','externalResidual','externalMass20'):
                if name not in models or i-fitted[name]>=24:
                    xx=X[known];yy=data['y'][known];weights=np.exp2(-(now-data['wakes'][known])/(14*86400))
                    if name=='externalResidual':yy=yy-prior[known]
                    if name=='externalMass20':
                        age=np.abs(D[:,0]-X[i,0])<=21
                        if age.any():
                            xx=np.concatenate([xx,D[age]]);yy=np.concatenate([yy,donorY[age]])
                            weights=np.concatenate([weights,np.full(int(age.sum()),20/age.sum())])
                    models[name]=WeightedForest().fit(xx,yy,weights);fitted[name]=i;fits[name]+=1
                if scope[i]:
                    point=models[name].predict(X[i:i+1])[0]
                    if name=='externalResidual':point+=prior[i]
                    outputs[name][i]=np.clip(point,1,480);counts[name]+=1
        for name in outputs:
            diagnostics[name]=dict(refits=fits[name],changedEligibleQueries=int(scope.sum()) if name=='externalOnly' else counts[name])
            if progress:progress(name,diagnostics[name])
    return outputs,diagnostics


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ('source','features','baseline','donor','license','output'):ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--limit',type=int);args=ap.parse_args();root=Path(__file__).resolve().parents[1]
    for path in (args.source,args.features,args.baseline,args.donor,args.output):
        if path.resolve().is_relative_to(root):ap.error('Keep data and reports outside source')
    if 'MIT License' not in args.license.read_text():ap.error('Review donor permissions before using this runner')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    app=json.loads(args.baseline.read_text());assert app['audit']['sourceSHA256']==sha(args.source)
    data=dict(np.load(args.features,allow_pickle=False));n=len(data['y'])
    if args.limit:data={k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in data.items()}
    rows={e['index']:e for e in app['events']}
    np.testing.assert_allclose([rows[int(i)]['wakeMinutes'] for i in data['indices']],data['y'],rtol=0,atol=1e-6)
    context=structure(args.source,data,rows,'America/Los_Angeles')
    base=(np.array([rows[int(i)]['prediction'] for i in data['indices']])-data['wakes'])/60
    dx,dy,info=external_features(args.donor,data['names']);print('donor',json.dumps(info),flush=True)
    forecasts,diagnostics=replay(data,context,base,dx,dy,lambda name,d:print(name,json.dumps(d),flush=True))
    masks=dict(planning=planning_mask(data,context),naps=planning_mask(data,context)&(context['labels']==1),bedtime=planning_mask(data,context)&(context['labels']==2),allTimers=np.ones(len(base),bool))
    result=dict(audit=dict(sourceSHA256=sha(args.source),donorSHA256=sha(args.donor),licenseSHA256=sha(args.license),scriptSHA256=sha(Path(__file__)),featureSHA256=sha(args.features),baselineSHA256=sha(args.baseline),donor=info,diagnostics=diagnostics,
        helperSHA256={name:sha(root/'Scripts'/name) for name in ('research_sleep_predictions.py','research_sleep_behavior_schedule.py','research_sleep_planning.py','research_sleep_ensemble.py')},
        training=dict(days=60,halfLifeDays=14,minimumResolvedLabels=40,refitQueries=24,donorPseudoCount=20,donorAgeRadiusDays=21),
        scope='Known daytime wakes within donor age range; preserve supplied app points otherwise. Every original evaluation row retained.',
        limitation='One independent 15-minute diary, not a population prior or two-minute ground truth. Exploratory archive-selected replay only.'),models={},events={})
    for name,p in dict(appV8=base,**forecasts).items():
        result['models'][name]={key:metrics(data['y'],p,m) for key,m in masks.items()}
        result['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(data['indices'],data['y'],p)]
        print(name,json.dumps(result['models'][name]['planning']),flush=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')


if __name__=='__main__':main()
