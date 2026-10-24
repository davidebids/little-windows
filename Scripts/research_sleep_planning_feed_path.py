#!/usr/bin/env python3
"""Predict and marginalize an intermediate feeding completion before next sleep."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from sklearn.ensemble import ExtraTreesClassifier
from sklearn.impute import SimpleImputer
from research_sleep_care_signatures import read_marks,MARKS
from research_sleep_predictions import WakeAnalogs
from research_sleep_behavior_schedule import structure,weighted_median
from research_sleep_planning import eligible,planning_mask
from research_sleep_ensemble import metrics


def feed_targets(events,data):
    """Future feeding is a target, never a feature supplied for the current row."""
    ends=np.unique(events[events[:,2]==MARKS.index('Feed'),1]);n=len(data['y'])
    first=np.searchsorted(ends,data['wakes'],side='right');time=np.full(n,np.inf);valid=first<len(ends)
    time[valid]=ends[first[valid]];has=time<=data['available']
    delay=np.full(n,np.nan);post=np.full(n,np.nan)
    delay[has]=(time[has]-data['wakes'][has])/60;post[has]=(data['available'][has]-time[has])/60
    np.testing.assert_allclose(delay[has]+post[has],data['y'][has],rtol=0,atol=1e-6)
    return dict(hasFeed=has,delay=delay,post=post)


def distribution(model,x):
    """The existing forest's normalized leaf-neighborhood masses, batch queries."""
    X=model.imputer.transform(x);leaves=model.forest.apply(X);out=np.zeros((len(X),len(model.y)))
    for i,leaf in enumerate(leaves):
        same=model.leaves==leaf
        out[i]=np.sum(same/np.maximum(same.sum(axis=0),1),axis=1)/same.shape[1]
    np.testing.assert_allclose(out.sum(axis=1),1.,rtol=0,atol=1e-10)
    return out


def marginal(first,mass,outcomes,conditional,add_delay):
    first=np.asarray(first,float);mass=np.asarray(mass,float);outcomes=np.asarray(outcomes,float);conditional=np.asarray(conditional,float)
    if conditional.shape!=(len(first),len(outcomes)) or mass.shape!=first.shape:raise ValueError('Invalid conditional distribution')
    values=np.broadcast_to(outcomes,(len(first),len(outcomes))).copy()
    if add_delay:values+=first[:,None]
    return values.ravel(),(mass[:,None]*conditional).ravel()


def replay(data,context,base,targets,progress=None):
    C=np.column_stack([data['X'],context['X'][:,5:8]])
    names=['planningForestControl','feedBranchControl','predictedFeedDirect','predictedFeedDecomposed']
    out={name:base.copy() for name in names};models={};gate=None;imputer=None;fitted=-24;fit_labels=0;fits=[];mediated=0
    for i in range(len(base)):
        known=eligible(data,context,i,True)
        if len(known)<3:continue
        interval=1 if len(known)<40 else 24
        if not models or i-fitted>=interval or fit_labels<40<=len(known):
            models={'global':WakeAnalogs('forest',5).fit(C[known],data['y'][known])};gate=None
            feeding=known[targets['hasFeed'][known]];other=known[~targets['hasFeed'][known]]
            if len(feeding):
                imputer=SimpleImputer(keep_empty_features=True);X=imputer.fit_transform(C[known])
                gate=ExtraTreesClassifier(n_estimators=80,min_samples_leaf=5,max_features=.8,random_state=42,n_jobs=1).fit(X,targets['hasFeed'][known])
                conditional=np.column_stack([C[feeding],targets['delay'][feeding]])
                models.update(noFeed=WakeAnalogs('forest',5).fit(C[other],data['y'][other]) if len(other) else models['global'],
                    direct=WakeAnalogs('forest',5).fit(C[feeding],data['y'][feeding]),
                    delay=WakeAnalogs('forest',5).fit(C[feeding],targets['delay'][feeding]),
                    conditional=WakeAnalogs('forest',5).fit(conditional,data['y'][feeding]),
                    post=WakeAnalogs('forest',5).fit(conditional,targets['post'][feeding]))
            fitted=i;fit_labels=len(known);entry=dict(query=i,labels=len(known),feedingLabels=len(feeding),noFeedLabels=len(other),pathEnabled=gate is not None);fits.append(entry)
            if progress:progress(entry)
        point=np.clip(float(models['global'].predict(C[i:i+1])[0]),1,480)
        for name in names:out[name][i]=point
        if gate is None:continue
        # Nothing below reads targets[i] or any future care event.
        probability=float(gate.predict_proba(imputer.transform(C[i:i+1]))[0,list(gate.classes_).index(True)])
        no_values=models['noFeed'].y;no_mass=distribution(models['noFeed'],C[i:i+1])[0]*(1-probability)
        direct_mass=distribution(models['direct'],C[i:i+1])[0]*probability
        out['feedBranchControl'][i]=np.clip(weighted_median(np.r_[no_values,models['direct'].y],np.r_[no_mass,direct_mass]),1,480)
        raw=models['delay'].y;raw_mass=distribution(models['delay'],C[i:i+1])[0]
        first,inverse=np.unique(raw,return_inverse=True);mass=np.bincount(inverse,weights=raw_mass,minlength=len(first));keep=mass>0;first=first[keep];mass=mass[keep]
        queries=np.column_stack([np.repeat(C[i:i+1],len(first),axis=0),first])
        for name,model,add in [('predictedFeedDirect',models['conditional'],False),('predictedFeedDecomposed',models['post'],True)]:
            values,weights=marginal(first,mass,model.y,distribution(model,queries),add)
            out[name][i]=np.clip(weighted_median(np.r_[no_values,values],np.r_[no_mass,probability*weights]),1,480)
        mediated+=1
    return out,dict(refits=fits,mediatedQueries=mediated)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for key in ['source','features','baseline','control','output']:ap.add_argument('--'+key,type=Path,required=True)
    ap.add_argument('--limit',type=int);a=ap.parse_args();root=Path(__file__).resolve().parents[1]
    if a.output.resolve().is_relative_to(root):ap.error('Keep private targets and forecasts outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();app=json.loads(a.baseline.read_text());control=json.loads(a.control.read_text())
    assert app['audit']['sourceSHA256']==control['audit']['sourceSHA256']==sha(a.source)
    with np.load(a.features,allow_pickle=False) as f:d=dict(f)
    n=len(d['y'])
    if a.limit:d={k:v[:a.limit] if v.ndim and len(v)==n else v for k,v in d.items()}
    rows={e['index']:e for e in app['events']};c=structure(a.source,d,rows,'America/Los_Angeles')
    base=(np.array([rows[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60
    events,skipped=read_marks(a.source,'America/Los_Angeles');targets=feed_targets(events,d)
    cache=a.output.with_suffix('.targets.npz');np.savez_compressed(cache,**targets)
    out,diag=replay(d,c,base,targets,lambda row:print(json.dumps(row),flush=True))
    by={e['index']:e for e in control['events']['planningForestControl']}
    np.testing.assert_array_equal([by[int(i)]['actual'] for i in d['indices']],d['y'])
    np.testing.assert_array_equal(out['planningForestControl'],[by[int(i)]['prediction'] for i in d['indices']])
    m=planning_mask(d,c);masks=dict(planning=m,naps=m&(c['labels']==1),bedtime=m&(c['labels']==2),allTimers=np.ones(len(m),bool))
    r=dict(audit=dict(sourceSHA256=sha(a.source),scriptSHA256=sha(Path(__file__)),targetsSHA256=sha(cache),
        inputsSHA256={key:sha(getattr(a,key)) for key in ['features','baseline','control']},
        helperSHA256={key:sha(root/'Scripts'/key) for key in ['research_sleep_predictions.py','research_sleep_care_signatures.py','research_sleep_behavior_schedule.py','research_sleep_planning.py','research_sleep_ensemble.py']},
        strategy='Predict occurrence and first feeding completion before sleep. Predict feeding-delay distribution, then conditional full-gap or post-feed-gap distribution, integrating over predicted delays exactly. Shared branch-only distribution control isolates future-event gating. Never substitute actual future feeding at inference.',
        training='Same28wake-knownfeatures,60day mature planning history,min3,early refitsbelow40/forced40crossingthen24,allclocks. All forests80treesleaf5max_features.8seed42. Enable feeding path after first mature feeding example; sparse branches remain unsplit leaves. If no non-feeding example exists its gate mass is zero and its unused distribution is the global forest.',
        causalRule='Future feeding occurrence/timing only targets of END-mature historical planning examples. At query use gate and predicted feeding delays only; current targets never route or enter a feature. All original score cases retained.',
        diagnostics=diag,planningWithFeed=int((m&targets['hasFeed']).sum()),planningWithoutFeed=int((m&~targets['hasFeed']).sum()),skippedRecords=skipped,globalControlExact=True,
        limitation='Independent predictive intermediate-event decomposition, not causal mediation or a claim that feeding causes sleep. Empirical conditional distributions approximated by forests. All-clock planning is not overnight-return integration. Retrospective archive-selected comparison; app unchanged.'),models={},events={})
    for name,p in dict(appV8=base,**out).items():
        r['models'][name]={key:metrics(d['y'],p,mask) for key,mask in masks.items()}
        r['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(d['indices'],d['y'],p)]
        print(name,json.dumps(r['models'][name]['planning']),flush=True)
    a.output.write_text(json.dumps(r,indent=2,allow_nan=False)+'\n')


if __name__=='__main__':main()
