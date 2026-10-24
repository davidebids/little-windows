"""Learn wake-known scenario buckets and choose separate local algorithms.
Every algorithm's routing loss comes from forecasts actually issued earlier,
not from fitted training predictions or the current realized sleep type.
"""
import argparse,json,hashlib,time
from pathlib import Path
import numpy as np
from sklearn.tree import DecisionTreeRegressor,export_text
from sklearn.impute import SimpleImputer
from sklearn.ensemble import ExtraTreesRegressor
from research_sleep_behavior_schedule import structure
from research_sleep_planning import eligible,planning_mask
from research_sleep_planning_mixture import mixture_point
from research_sleep_ensemble import metrics
ROOT=Path(__file__).resolve().parents[1]
ALGORITHMS=['app','pooledForest','bucketWindow','bucketClock','bucketForest']
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def design(data,context,base,complete):
 C=context['X'];names=list(complete['names']);lags=complete['X'][:,[names.index('durationLag'+str(k)) for k in range(2,7)]]
 typical=np.array([np.median(row[np.isfinite(row)&(row>0)]) if np.any(np.isfinite(row)&(row>0)) else np.nan for row in lags]);relative=np.minimum(C[:,5]/np.maximum(typical,1),5)
 sleepRatio=np.full(len(base),np.nan)
 for i,now in enumerate(data['wakes']):
  j=np.flatnonzero((np.arange(len(base))<i)&(data['wakes']>=now-7*86400))
  if len(j):sleepRatio[i]=C[i,10]/max(float(np.median(C[j,10])),1)
 D=np.column_stack([C[:,0],context['wakeClock'],C[:,3:11],relative,sleepRatio,base])
 dn=['ageDays','wakeClock','precedingNight','lastSegmentMinutes','episodeSleepMinutes','episodeSegments','napOrdinal','previousWakeMinutes','sleep6h','sleep24h','episodeRelativeToPreviousDurations','sleep24RelativeToWeek','appIssuedWakeMinutes']
 assert D.shape[1]==len(dn)
 X=np.column_stack([data['X'],C[:,5:8],base])
 return D,X,dn
class Forest:
 def fit(self,X,y,weight):
  self.imputer=SimpleImputer(keep_empty_features=True).fit(X);xx=self.imputer.transform(X);self.y=y.copy();self.weight=weight.copy()
  self.model=ExtraTreesRegressor(n_estimators=80,min_samples_leaf=5,max_features=.8,random_state=42,n_jobs=1).fit(xx,y,sample_weight=weight);self.leaves=self.model.apply(xx);return self
 def distribution(self,X):
  q=self.model.apply(self.imputer.transform(X))[0];mass=(self.leaves==q)*self.weight[:,None];mass=(mass/np.maximum(mass.sum(axis=0),1e-300)).mean(axis=1);selected=mass>0
  return self.y[selected],mass[selected]/mass[selected].sum()
def replay(data,context,base,D,X,dnames,factory=Forest,progress=None):
 n=len(base);tape=np.tile(base[:,None],(1,len(ALGORITHMS)));out={name:base.copy() for name in ['pooledForest','bucketWindow','bucketClock','bucketForest','globalAlgorithmChoice','bucketAlgorithmChoice']}
 model=None;fit_at=-24;fit_labels=0;records=[];routes=[];local_models={};local_fits=0
 for i,now in enumerate(data['wakes']):
  known=eligible(data,context,i,True)
  if len(known)<3:continue
  interval=1 if len(known)<40 else 24
  if model is None or i-fit_at>=interval or fit_labels<40<=len(known):
   fitKnown=known.copy();weight=np.exp2(-(now-data['wakes'][known])/(14*86400));imp=SimpleImputer(keep_empty_features=True).fit(D[known]);DD=imp.transform(D[known]);tree=None
   if len(known)>=40:tree=DecisionTreeRegressor(criterion='absolute_error',max_leaf_nodes=8,min_samples_leaf=20,random_state=42).fit(DD,data['y'][known],sample_weight=weight)
   labels=tree.apply(DD) if tree is not None else np.zeros(len(known),int);model=factory().fit(X[known],data['y'][known],weight);local_models={};fit_at=i;fit_labels=len(known)
   record=dict(query=i,labels=len(known),bucketSizes={str(k):int(np.sum(labels==k)) for k in np.unique(labels)},tree=export_text(tree,feature_names=dnames) if tree is not None else 'shared sparse-history bucket')
   records.append(record)
   if progress:progress(dict(query=i,labels=len(known),buckets=len(record['bucketSizes'])))
  leaf=int(tree.apply(imp.transform(D[i:i+1]))[0]) if tree is not None else 0
  subset=fitKnown[labels==leaf];w=np.exp2(-(now-data['wakes'][subset])/(14*86400));w/=w.sum();rootY,rootW=model.distribution(X[i:i+1]);rootPoint=mixture_point([(rootY,rootW,1.)],30);out['pooledForest'][i]=rootPoint;tape[i,1]=rootPoint
  effective=1/float(np.sum(w*w));localMass=effective/(effective+20.)
  window=(data['y'][subset],w)
  # Historical target clocks are training outcomes only. Current routing uses
  # the known wake clock, never the next recorded sleep clock or type.
  clock=((context['targetClock'][subset]-context['wakeClock'][i])%1440);clock=np.clip(clock,1,480)
  if len(subset)==len(fitKnown):localY,localW=rootY,rootW
  else:
   if leaf not in local_models:
    sw=np.exp2(-(data['wakes'][fit_at]-data['wakes'][subset])/(14*86400));local_models[leaf]=factory().fit(X[subset],data['y'][subset],sw);local_fits+=1
   localY,localW=local_models[leaf].distribution(X[i:i+1])
  for name,part in zip(ALGORITHMS[2:],[window,(clock,w),(localY,localW)]):
   point=mixture_point([(part[0],part[1],localMass),(rootY,rootW,1-localMass)],30);tape[i,ALGORITHMS.index(name)]=point;out[name][i]=point
  if len(known)<8:continue
  # Evaluate previously ISSUED forecasts. All these outcomes have ended.
  error=abs(tape[known]-data['y'][known,None]);loss=error+30*(error>30);ww=np.exp2(-(now-data['wakes'][known])/(14*86400));globalRisk=np.average(loss,axis=0,weights=ww)
  globalChoice=int(np.argmin(globalRisk));out['globalAlgorithmChoice'][i]=tape[i,globalChoice]
  historicalLeaves=tree.apply(imp.transform(D[known])) if tree is not None else np.zeros(len(known),int);inside=historicalLeaves==leaf
  if np.any(inside):
   localRisk=np.average(loss[inside],axis=0,weights=ww[inside]);eff=float(ww[inside].sum()**2/np.sum(ww[inside]**2));alpha=eff/(eff+20.);risk=alpha*localRisk+(1-alpha)*globalRisk
  else:risk=globalRisk
  choice=int(np.argmin(risk));out['bucketAlgorithmChoice'][i]=tape[i,choice]
  routes.append(dict(query=i,bucket=leaf,algorithm=ALGORITHMS[choice],globalAlgorithm=ALGORITHMS[globalChoice],feedbackCount=len(known),bucketFeedbackCount=int(inside.sum())))
 return out,dict(refits=records,localForestFits=local_fits,routes=routes,algorithmChoices={name:sum(v['algorithm']==name for v in routes) for name in ALGORITHMS}),tape

def main():
 ap=argparse.ArgumentParser()
 for key in ['source','features','complete','baseline','output']:ap.add_argument('--'+key,type=Path,required=True)
 ap.add_argument('--limit',type=int);a=ap.parse_args();assert not a.output.resolve().is_relative_to(ROOT)
 app=json.loads(a.baseline.read_text());assert app['audit']['sourceSHA256']==sha(a.source)
 data=dict(np.load(a.features,allow_pickle=False));complete=dict(np.load(a.complete,allow_pickle=False));n=len(data['y'])
 if a.limit:data={k:v[:a.limit] if v.ndim and len(v)==n else v for k,v in data.items()}
 complete={k:v[:len(data['y'])] if v.ndim and len(v)==n else v for k,v in complete.items()}
 for key in ['indices','wakes','y','available']:np.testing.assert_array_equal(complete[key],data[key])
 rows={e['index']:e for e in app['events']};np.testing.assert_array_equal([rows[int(i)]['wakeMinutes'] for i in data['indices']],data['y']);c=structure(a.source,data,rows,'America/Los_Angeles');base=(np.array([rows[int(i)]['prediction'] for i in data['indices']])-data['wakes'])/60
 D,X,dnames=design(data,c,base,complete);started=time.monotonic();out,diag,tape=replay(data,c,base,D,X,dnames,progress=lambda v:print(json.dumps(dict(**v,seconds=time.monotonic()-started)),flush=True));tp=a.output.with_suffix('.tape.npy');dp=a.output.with_suffix('.design.npy');np.save(tp,tape);np.save(dp,D)
 m=planning_mask(data,c);masks=dict(planning=m,naps=m&(c['labels']==1),bedtime=m&(c['labels']==2),allTimers=np.ones(len(m),bool))
 r=dict(audit=dict(primary='bucketAlgorithmChoice',scriptSHA256=sha(__file__),sourceSHA256=sha(a.source),inputsSHA256={k:sha(getattr(a,k)) for k in ['features','complete','baseline']},helperSHA256={name:sha(ROOT/'Scripts'/name) for name in ['research_sleep_behavior_schedule.py','research_sleep_planning.py','research_sleep_planning_mixture.py','research_sleep_ensemble.py']},tapeSHA256=sha(tp),designSHA256=sha(dp),designNames=dnames,diagnostics=diag,training=dict(historyDays=60,halfLifeDays=14,maxBuckets=8,minTreeLeaf=20,minLearning=3,minRoutingFeedback=8,treesPerForest=80,forestMinLeaf=5,refitAfter40EveryQueries=24,sparseRefitEveryQuery=True,shrinkPseudoCount=20,missPenalty=30),rule='Past-only wake-scenario tree; separate local window/clock/forest algorithms shrunk toward pooled conditional distribution. Router chooses algorithm by previously issued end-mature forecasts in current bucket, shrunk to global past risk. No current realized sleep kind/gap selects a route. All original outcomes retained.',limitation='Exploratory archive-selected hierarchical experts; temporal walk-forward validation, not prospective performance or a guaranteed gain.'),models={},events={})
 for name,p in dict(appV8=base,**out).items():
  r['models'][name]={k:metrics(data['y'],p,mask) for k,mask in masks.items()};r['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(data['indices'],data['y'],p)];print(name,json.dumps(r['models'][name]['planning']),flush=True)
 a.output.write_text(json.dumps(r,indent=2,allow_nan=False)+'\n')
if __name__=='__main__':main()
