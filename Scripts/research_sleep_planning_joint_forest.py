#!/usr/bin/env python3
"""Random-split planning forests with an absolute-error plus miss-cost objective."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from sklearn.impute import SimpleImputer
from research_sleep_behavior_schedule import structure
from research_sleep_planning import eligible,planning_mask
from research_sleep_ensemble import metrics


def centers(y):
    """All piecewise-linear minima, including inward floating-point boundaries."""
    y=np.asarray(y,float);low=y-30;high=y+30
    return np.unique(np.clip(np.concatenate([y,low,high,np.nextafter(low,y),np.nextafter(high,y)]),1,480))


def boundaries(y,points):
    """Prefix bounds agreeing with the scorer's floating-point abs(error)<=30."""
    n=len(y);lo=np.searchsorted(y,points-30,'left');hi=np.searchsorted(y,points+30,'right')
    for _ in range(2):
        lower=np.maximum(lo-1,0);upper=np.minimum(lo,n-1)
        lo=lo-((lo>0)&(abs(y[lower]-points)<=30)).astype(int)
        upper=np.minimum(lo,n-1)
        lo=lo+((lo<n)&(y[upper]<points)&(abs(y[upper]-points)>30)).astype(int)
        upper=np.minimum(hi,n-1)
        hi=hi+((hi<n)&(abs(y[upper]-points)<=30)).astype(int)
        lower=np.maximum(hi-1,0)
        hi=hi-((hi>0)&(y[lower]>points)&(abs(y[lower]-points)>30)).astype(int)
    return lo,hi


def risks(y,weights,points,penalty):
    """Unnormalized risks for multiple empirical distributions in one batch."""
    order=np.argsort(y,kind='stable');y=np.asarray(y,float)[order];w=np.atleast_2d(weights)[:,order]
    count=np.column_stack([np.zeros(len(w)),np.cumsum(w,axis=1)])
    total=np.column_stack([np.zeros(len(w)),np.cumsum(w*y,axis=1)])
    mid=np.searchsorted(y,points,'right');n=count[:,-1,None];s=total[:,-1,None]
    absolute=points[None,:]*(2*count[:,mid]-n)+s-2*total[:,mid]
    lo,hi=boundaries(y,points);miss=n-(count[:,hi]-count[:,lo])
    return np.maximum(0,absolute)+penalty*np.maximum(0,miss)


def decision(y,weights,penalty):
    y=np.asarray(y,float);w=np.asarray(weights,float)
    if len(y)!=len(w) or not len(y) or (w<0).any() or not np.isfinite(y).all() or not np.isfinite(w).all() or w.sum()<=0:
        raise ValueError('Invalid distribution')
    keep=w>0;y=y[keep];w=w[keep];order=np.argsort(y,kind='stable');sy=y[order];sw=w[order]
    median=float(np.clip(sy[np.searchsorted(np.cumsum(sw),sw.sum()/2)],1,480))
    if penalty==0:return median
    points=centers(y);cost=risks(y,w,points,penalty)[0]
    # Prefer the median, then the lower point, within numerical loss equality.
    best=np.flatnonzero(cost<=cost.min()+1e-9)
    return float(points[best[np.argmin(abs(points[best]-median))]])


class JointForest:
    def __init__(self,split_penalty,trees=80,minimum_leaf=5):
        if split_penalty<0 or trees<1 or minimum_leaf<1:raise ValueError('Invalid forest settings')
        self.penalty=split_penalty;self.tree_count=trees;self.minimum_leaf=minimum_leaf

    def fit(self,x,y):
        self.imputer=SimpleImputer(keep_empty_features=True);X=self.imputer.fit_transform(x);self.y=np.asarray(y,float).copy()
        if len(X)!=len(y) or not np.isfinite(X).all() or not np.isfinite(y).all():raise ValueError('Invalid forest data')
        self.trees=[]
        for tree in range(self.tree_count):
            nodes=[]
            def grow(members,path):
                index=len(nodes);nodes.append(dict(members=members.copy()));yy=self.y[members];n=len(yy)
                if n<2*self.minimum_leaf or np.ptp(yy)==0:return index
                # Node-keyed random draws keep the proposal budget matched across criteria.
                rng=np.random.default_rng(np.random.SeedSequence([42,tree,path]))
                features=rng.choice(X.shape[1],max(1,int(.8*X.shape[1])),replace=False)
                values=X[members][:,features];low=values.min(axis=0);high=values.max(axis=0)
                thresholds=low+rng.random(len(features))*(high-low)
                left=values.T<=thresholds[:,None];counts=left.sum(axis=1)
                valid=(high>low+1e-7)&(counts>=self.minimum_leaf)&(n-counts>=self.minimum_leaf)
                if not valid.any():return index
                features=features[valid];thresholds=thresholds[valid];left=left[valid]
                points=centers(yy)
                left_risk=risks(yy,left,points,self.penalty);right_risk=risks(yy,~left,points,self.penalty)
                score=left_risk.min(axis=1)+right_risk.min(axis=1);best=int(np.argmin(score))
                parent=float(risks(yy,np.ones(n),points,self.penalty).min())
                if score[best]>parent+1e-8:return index
                node=nodes[index];node.pop('members');node.update(feature=int(features[best]),threshold=float(thresholds[best]))
                node['left']=grow(members[left[best]],path*2);node['right']=grow(members[~left[best]],path*2+1)
                return index
            grow(np.arange(len(y)),1);self.trees.append(nodes)
        return self

    def weights(self,x):
        X=self.imputer.transform(x);out=np.zeros((len(X),len(self.y)))
        for i,row in enumerate(X):
            for nodes in self.trees:
                j=0
                while 'members' not in nodes[j]:
                    node=nodes[j];j=node['left'] if row[node['feature']]<=node['threshold'] else node['right']
                members=nodes[j]['members'];out[i,members]+=1/len(members)/len(self.trees)
        return out

    def predict(self,x,decision_penalty):
        return np.array([decision(self.y,w,decision_penalty) for w in self.weights(x)])


def replay(data,context,base,progress=None,trees=80):
    X=np.column_stack([data['X'],context['X'][:,5:8]]);names=['absoluteTreeMedian','absoluteTreeJointDecision','jointTreeJointDecision']
    out={name:base.copy() for name in names};models={};fitted=-24;fit_labels=0;fits=[]
    for i in range(len(base)):
        known=eligible(data,context,i,True)
        if len(known)<3:continue
        interval=1 if len(known)<40 else 24
        if not models or i-fitted>=interval or fit_labels<40<=len(known):
            models={p:JointForest(p,trees).fit(X[known],data['y'][known]) for p in [0,30]}
            fitted=i;fit_labels=len(known);entry=dict(query=i,labels=len(known));fits.append(entry)
            if progress:progress(entry)
        for name,split,rule in zip(names,[0,0,30],[0,30,30]):out[name][i]=np.clip(models[split].predict(X[i:i+1],rule)[0],1,480)
    return out,dict(refits=fits)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for key in ['source','features','baseline','output']:ap.add_argument('--'+key,type=Path,required=True)
    ap.add_argument('--limit',type=int);a=ap.parse_args();root=Path(__file__).resolve().parents[1]
    if a.output.resolve().is_relative_to(root):ap.error('Keep private results outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();app=json.loads(a.baseline.read_text())
    assert app['audit']['sourceSHA256']==sha(a.source)
    with np.load(a.features,allow_pickle=False) as f:d=dict(f)
    n=len(d['y'])
    if a.limit:d={k:v[:a.limit] if v.ndim and len(v)==n else v for k,v in d.items()}
    rows={e['index']:e for e in app['events']};c=structure(a.source,d,rows,'America/Los_Angeles')
    np.testing.assert_allclose([rows[int(i)]['wakeMinutes'] for i in d['indices']],d['y'],rtol=0,atol=1e-6)
    base=(np.array([rows[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60
    out,diag=replay(d,c,base,lambda entry:print(json.dumps(entry),flush=True))
    m=planning_mask(d,c);masks=dict(planning=m,naps=m&(c['labels']==1),bedtime=m&(c['labels']==2),allTimers=np.ones(len(m),bool))
    r=dict(audit=dict(sourceSHA256=sha(a.source),scriptSHA256=sha(Path(__file__)),
        inputsSHA256={key:sha(getattr(a,key)) for key in ['features','baseline']},
        helperSHA256={key:sha(root/'Scripts'/key) for key in ['research_sleep_behavior_schedule.py','research_sleep_planning.py','research_sleep_ensemble.py']},
        strategy='Custom80-tree random-split forests,leaf5,featurefraction.8,seed42 keyed bytree/node. Exact empirical absolute-error+30*miss30 risk for split impurity and final leaf-neighborhood decision. Controls: absolute split/median, same absolute trees/joint decision. All share28features/60day mature planning cohort/min3/early per-query refits below40/then24queries/allclocks.',
        causalRule='Current target gap/type never routes or trains. Planning labels mature at target END. All cases retained, including initial app fallback.',
        sourceURL='https://www.jmlr.org/papers/v7/meinshausen06a.html',diagnostics=diag,
        limitation='Independent decision-focused extension of forest-neighborhood distributions, not a reproduction or published infant result. Custom controls isolate split/decision effects; custom randomization differs from native/sklearn forests. All-clock distinct planning is not overnight-return prediction. Retrospective archive-selected research.'),models={},events={})
    for name,p in dict(appV8=base,**out).items():
        r['models'][name]={key:metrics(d['y'],p,mask) for key,mask in masks.items()}
        r['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(d['indices'],d['y'],p)]
        print(name,json.dumps(r['models'][name]['planning']),flush=True)
    a.output.write_text(json.dumps(r,indent=2,allow_nan=False)+'\n')


if __name__=='__main__':main()
