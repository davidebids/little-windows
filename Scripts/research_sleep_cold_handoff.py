#!/usr/bin/env python3
"""Compose issued cold-history and mature forecasts using resolved sample count."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from research_sleep_ensemble import metrics


def handoff(data,cold,mature):
    count=np.array([np.sum((np.arange(len(cold))<i)&(data['available']<=now)&(data['wakes']>=now-60*86400)) for i,now in enumerate(data['wakes'])])
    return np.where(count<40,cold,mature),count


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','cold-result','cold-model','mature-result','mature-model','output']:
        ap.add_argument('--'+name,type=Path if name in ['source','features','cold-result','mature-result','output'] else str,required=True)
    ap.add_argument('--limit',type=int);args=ap.parse_args();root=Path(__file__).resolve().parents[1];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    if args.output.resolve().is_relative_to(root):ap.error('Keep private forecast results outside source')
    d=dict(np.load(args.features,allow_pickle=False));n=len(d['y'])
    if args.limit:d={k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in d.items()}
    vectors=[]
    for path,key in [(args.cold_result,args.cold_model),(args.mature_result,args.mature_model)]:
        r=json.loads(path.read_text());assert r['audit']['sourceSHA256']==sha(args.source)
        rows={e['index']:e for e in r['events'][key]}
        np.testing.assert_allclose([rows[int(i)]['actual'] for i in d['indices']],d['y'],rtol=0,atol=1e-6)
        vectors.append(np.array([rows[int(i)]['prediction'] for i in d['indices']]))
    p,count=handoff(d,*vectors);key='coldLocalRatio2_matureResearch'
    result=dict(audit=dict(sourceSHA256=sha(args.source),featureCacheSHA256=sha(args.features),scriptSHA256=sha(Path(__file__)),helperFilesSHA256={'research_sleep_ensemble.py':sha(root/'Scripts/research_sleep_ensemble.py')},
        coldResultSHA256=sha(args.cold_result),coldModel=args.cold_model,matureResultSHA256=sha(args.mature_result),matureModel=args.mature_model,careExposure='completed',
        handoffResolvedCount=40,coldQueries=int(sum(count<40)),matureQueries=int(sum(count>=40)),
        rule='Use supplied issued cold forecast until forty resolved labels in sixty days; then supplied issued mature forecast',
        limitation='Both component choices selected retrospectively on this archive; composition is causal but not independent future validation or a production-ready dependency claim'),
        models={key:{group:metrics(d['y'],p,mask) for group,mask in [('all',np.ones(len(p),dtype=bool)),('coldUnder40',count<40),('mature40Plus',count>=40)]}},
        events={key:[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(d['indices'],d['y'],p)]})
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n');print(json.dumps(result['models']))


if __name__=='__main__':main()
