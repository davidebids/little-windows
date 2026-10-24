#!/usr/bin/env python3
"""Matched squared-versus-absolute tree splits for personal sleep planning."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
import sklearn
from sklearn.ensemble import ExtraTreesRegressor
from sklearn.impute import SimpleImputer
from research_sleep_predictions import WakeAnalogs
from research_sleep_behavior_schedule import structure
from research_sleep_planning import eligible,planning_mask
from research_sleep_ensemble import metrics


class SplitForest(WakeAnalogs):
    def __init__(self,criterion):
        super().__init__('forest',5)
        if criterion not in ['squared_error','absolute_error']:raise ValueError('Unsupported split criterion')
        self.criterion=criterion

    def fit(self,x,y):
        self.imputer=SimpleImputer(keep_empty_features=True);X=self.imputer.fit_transform(x);self.y=y.copy()
        self.forest=ExtraTreesRegressor(n_estimators=80,min_samples_leaf=5,max_features=.8,
            random_state=42,n_jobs=1,criterion=self.criterion).fit(X,y)
        self.leaves=self.forest.apply(X)
        return self


def replay(data,context,base,progress=None):
    X=np.column_stack([data['X'],context['X'][:,5:8]])
    out={name:base.copy() for name in ['squaredSplitControl','absoluteSplitMedian']}
    names=dict(squaredSplitControl='squared_error',absoluteSplitMedian='absolute_error')
    models={};fitted=-24;fit_labels=0;fits=[]
    for i in range(len(base)):
        known=eligible(data,context,i,True)
        if len(known)<3:continue
        interval=1 if len(known)<40 else 24
        if not models or i-fitted>=interval or fit_labels<40<=len(known):
            models={name:SplitForest(criterion).fit(X[known],data['y'][known]) for name,criterion in names.items()}
            fitted=i;fit_labels=len(known);entry=dict(query=i,labels=len(known));fits.append(entry)
            if progress:progress(entry)
        for name,model in models.items():out[name][i]=np.clip(float(model.predict(X[i:i+1])[0]),1,480)
    return out,dict(refits=fits)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for key in ['source','features','baseline','control','output']:ap.add_argument('--'+key,type=Path,required=True)
    ap.add_argument('--limit',type=int);a=ap.parse_args();root=Path(__file__).resolve().parents[1]
    if a.output.resolve().is_relative_to(root):ap.error('Keep private results outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    app=json.loads(a.baseline.read_text());control=json.loads(a.control.read_text())
    assert app['audit']['sourceSHA256']==control['audit']['sourceSHA256']==sha(a.source)
    with np.load(a.features,allow_pickle=False) as f:d=dict(f)
    n=len(d['y'])
    if a.limit:d={k:v[:a.limit] if v.ndim and len(v)==n else v for k,v in d.items()}
    rows={e['index']:e for e in app['events']};c=structure(a.source,d,rows,'America/Los_Angeles')
    base=(np.array([rows[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60
    out,diag=replay(d,c,base,lambda entry:print(json.dumps(entry),flush=True))
    by={e['index']:e for e in control['events']['planningForestControl']}
    np.testing.assert_array_equal([by[int(i)]['actual'] for i in d['indices']],d['y'])
    np.testing.assert_array_equal(out['squaredSplitControl'],[by[int(i)]['prediction'] for i in d['indices']])
    m=planning_mask(d,c);masks=dict(planning=m,naps=m&(c['labels']==1),bedtime=m&(c['labels']==2),allTimers=np.ones(len(m),bool))
    r=dict(audit=dict(sourceSHA256=sha(a.source),scriptSHA256=sha(Path(__file__)),
        inputsSHA256={k:sha(getattr(a,k)) for k in ['features','baseline','control']},
        helperSHA256={k:sha(root/'Scripts'/k) for k in ['research_sleep_predictions.py','research_sleep_behavior_schedule.py','research_sleep_planning.py','research_sleep_ensemble.py']},
        strategy='Only tree split criterion changes: squared-error versus absolute-error. Both use original leaf-neighborhood weighted median,80trees,leaf5,max_features.8,seed42. Same28features,60day mature planning history,minimum3labels,early per-query fits below40 then24query cadence,allwakeclocks.',
        causalRule='Current/future target type and gap never route. Training target/type mature at target END. No records dropped, including early fallback queries.',
        sourceURL='https://scikit-learn.org/stable/modules/generated/sklearn.ensemble.ExtraTreesRegressor.html',
        sklearnVersion=sklearn.__version__,squaredControlExact=True,diagnostics=diag,
        limitation='Retrospective archive-selected comparison. Earlier MAE boosting and ExtraTrees mean-of-tree-output trials are distinct. All-clock distinct planning is not an overnight resettling model. App unchanged.'),models={},events={})
    for name,p in dict(appV8=base,**out).items():
        r['models'][name]={key:metrics(d['y'],p,mask) for key,mask in masks.items()}
        r['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(d['indices'],d['y'],p)]
        print(name,json.dumps(r['models'][name]['planning']),flush=True)
    a.output.write_text(json.dumps(r,indent=2,allow_nan=False)+'\n')


if __name__=='__main__':main()
