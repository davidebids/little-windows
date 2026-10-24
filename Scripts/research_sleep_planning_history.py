#!/usr/bin/env python3
"""Add causal planning-only recent interval and clock summaries to forests."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from research_sleep_behavior_schedule import structure, weighted_median
from research_sleep_planning import planning_mask, eligible
from research_sleep_predictions import WakeAnalogs
from research_sleep_ensemble import metrics


def summaries(data,context):
    n=len(data['y']); out=np.full((n,20),np.nan); planning=planning_mask(data,context)
    for i,now in enumerate(data['wakes']):
        known=np.flatnonzero((np.arange(n)<i)&planning&(context['knownAt']<=now)&(data['wakes']>=now-14*86400))
        same_night=context['X'][known,3]==context['X'][i,3]
        same_order=context['ordinal'][known]==context['ordinal'][i]
        clockdelta=(context['wakeClock'][known]-context['wakeClock'][i]+720)%1440-720
        selections=[np.ones(len(known),bool),same_night&same_order,abs(clockdelta)<=120,context['labels'][known]==2]
        for group,mask in enumerate(selections):
            chosen=known[mask]; offset=5*group;out[i,offset]=len(chosen)
            if not len(chosen):continue
            weights=np.exp2(-(now-data['wakes'][chosen])/(7*86400))
            out[i,offset+1]=weighted_median(data['y'][chosen],weights)
            # Clocks are unwrapped around current wake +180min, a known anchor.
            relative=(context['targetClock'][chosen]-context['wakeClock'][i]-180+720)%1440-720+180
            out[i,offset+2]=weighted_median(relative,weights)
            out[i,offset+3]=data['y'][chosen[-1]]
            out[i,offset+4]=np.median(data['y'][chosen[-3:]])
    return out


def replay(data,context,forest,extra,progress=None):
    history=summaries(data,context); outputs={}; diagnostics={}
    compact=np.column_stack([data['X'],context['X'][:,5:8]])
    for name,X in [('planningRecentHistory',np.column_stack([compact,history])),('planningCompleteHistory',np.column_stack([extra,context['X'][:,5:8],history]))]:
        p=forest.copy();model=None;fitted=-24;fits=learned=0
        for i in range(len(p)):
            known=eligible(data,context,i,True)
            if len(known)>=40 and i-fitted>=24:
                model=WakeAnalogs('forest',5).fit(X[known],data['y'][known]);fitted=i;fits+=1
            if model is not None:p[i]=np.clip(model.predict(X[i:i+1])[0],1,480);learned+=1
        outputs[name]=p;diagnostics[name]=dict(refits=fits,learnedQueries=learned,featureCount=X.shape[1])
        if progress:progress(name,diagnostics[name])
    return outputs,diagnostics


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','complete','baseline','planning','output']:ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--limit',type=int);args=ap.parse_args();root=Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root):ap.error('Keep private results outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    app=json.loads(args.baseline.read_text());prior=json.loads(args.planning.read_text());digest=sha(args.source)
    assert app['audit']['sourceSHA256']==prior['audit']['sourceSHA256']==digest
    d=dict(np.load(args.features,allow_pickle=False));extra=dict(np.load(args.complete,allow_pickle=False));n=len(d['y'])
    np.testing.assert_array_equal(extra['indices'],d['indices']);np.testing.assert_allclose(extra['y'],d['y'],rtol=0,atol=1e-6)
    if args.limit:d={k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in d.items()}
    extraX=extra['X'][:len(d['y'])];rows={e['index']:e for e in app['events']};saved={e['index']:e for e in prior['events']['pooled_planning']}
    np.testing.assert_allclose([saved[int(i)]['actual'] for i in d['indices']],d['y'],rtol=0,atol=1e-6)
    forest=np.array([saved[int(i)]['prediction'] for i in d['indices']]);context=structure(args.source,d,rows,'America/Los_Angeles')
    predictions,diagnostics=replay(d,context,forest,extraX,lambda name,diag:print(name,json.dumps(diag),flush=True))
    mask=planning_mask(d,context);masks=dict(planning=mask,naps=mask&(context['labels']==1),bedtime=mask&(context['labels']==2),allTimers=np.ones(len(mask),bool))
    result=dict(audit=dict(sourceSHA256=digest,scriptSHA256=sha(Path(__file__)),featureSHA256=sha(args.features),completeFeatureSHA256=sha(args.complete),planningSHA256=sha(args.planning),baselineSHA256=sha(args.baseline),
        history='20 fixed summaries over resolved planning labels in14days; four groups (all, same prior kind and logical nap order, wake clock within120min, bedtime); counts, half7day median gaps/clocks, last and last3 median intervals.',
        causalRule='All history summaries frozen at their own wake; current target/gap/kind never inputs. Inferred type matures at target sleep end.',
        training=dict(historyDays=60,minimumLabels=40,refitQueries=24,trees=80,minimumLeaf=5),
        limitation='Retrospective selected-history comparison, not prospective validation.',diagnostics=diagnostics,
        helperFilesSHA256={name:sha(root/'Scripts'/name) for name in ['research_sleep_behavior_schedule.py','research_sleep_planning.py','research_sleep_predictions.py','research_sleep_ensemble.py']}),models={},events={})
    for name,p in {'planningForest':forest,**predictions}.items():
        result['models'][name]={key:metrics(d['y'],p,m) for key,m in masks.items()}
        result['events'][name]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(d['indices'],d['y'],p)]
        print(name,json.dumps(result['models'][name]['planning']),flush=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')

if __name__=='__main__':main()
