#!/usr/bin/env python3
"""Past-only training-duration selection for the completed-care recurrent model."""
import argparse
import hashlib
import json
import time
from pathlib import Path
import numpy as np
import torch
from research_sleep_care_recurrent import fit_model,predict_model,replay
from research_sleep_care_alignment import care_patterns
from research_sleep_care_signatures import read_marks
from research_sleep_ensemble import metrics


def choose_epochs(sequence,context,target,weights,candidates=(16,64,128),fit=fit_model,predict=predict_model):
    # All these labels have already resolved at the outer prediction origin.
    # The inner split remains chronological and its scaling is train-only.
    n=len(target);validation=max(16,n//5);cut=n-validation
    if cut<40:raise ValueError('Need enough resolved history for nested validation')
    losses=[]
    for epochs in candidates:
        model=fit(sequence[:cut],context[:cut],target[:cut],weights[:cut],epochs)
        errors=np.abs(predict(model,sequence[cut:],context[cut:])-target[cut:])
        losses.append(float(np.average(errors,weights=weights[cut:])))
    chosen=min(range(len(candidates)),key=lambda i:(losses[i],candidates[i]))
    return candidates[chosen],dict(trainingRows=cut,validationRows=validation,selectedEpochs=candidates[chosen],validationErrors=losses)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','baseline','output']:ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--limit',type=int);args=ap.parse_args();root=Path(__file__).resolve().parents[1];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    if args.output.resolve().is_relative_to(root):ap.error('Keep private paths and forecasts outside source')
    d=dict(np.load(args.features,allow_pickle=False));n=len(d['y'])
    if args.limit:d={k:(v[:args.limit] if v.ndim and len(v)==n else v) for k,v in d.items()}
    base=json.loads(args.baseline.read_text());assert base['audit']['sourceSHA256']==sha(args.source);by={r['index']:r for r in base['events']}
    np.testing.assert_allclose([by[int(i)]['actual'] for i in d['indices']],d['available'],rtol=0,atol=1e-6)
    np.testing.assert_allclose([by[int(i)]['wakeMinutes'] for i in d['indices']],d['y'],rtol=0,atol=1e-6)
    fallback=(np.array([by[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60
    events,skipped=read_marks(args.source,'America/Los_Angeles');P=care_patterns(events,d['wakes'],16);cache=args.output.with_suffix('.patterns.npy');np.save(cache,P,allow_pickle=False)
    choices=[]
    def adaptive_fit(sequence,context,target,weights,unused_epochs):
        selected,info=choose_epochs(sequence,context,target,weights);choices.append(info)
        return fit_model(sequence,context,target,weights,selected)
    start=time.monotonic()
    def progress(name,diag):print(json.dumps(dict(candidate=name,**diag,seconds=time.monotonic()-start)),flush=True)
    forecasts,diag=replay(d,P,fallback,progress,fit_function=adaptive_fit)
    counts={str(e):sum(v['selectedEpochs']==e for v in choices) for e in [16,64,128]}
    r=dict(audit=dict(sourceSHA256=sha(args.source),featureCacheSHA256=sha(args.features),baselineResultSHA256=sha(args.baseline),patternCacheSHA256=sha(cache),scriptSHA256=sha(Path(__file__)),
        helperFilesSHA256={name:sha(root/'Scripts'/name) for name in ['research_sleep_care_recurrent.py','research_sleep_care_alignment.py','research_sleep_care_signatures.py','research_sleep_cycle_alignment.py','research_sleep_ensemble.py']},
        careExposure='completed',torchVersion=torch.__version__,numpyVersion=np.__version__,epochCandidates=[16,64,128],epochSelectionCounts=counts,selectionFits=len(choices),
        lookbackDays=60,halfLifeDays=14,minimumLabels=80,refitEvery=48,patternLength=16,diagnostics=diag,skippedInputRecords=skipped,
        rule='Latest max(16,floor(n/5)) resolved training rows validate each cold-fit duration; select weighted validation L1 then cold-refit all available rows at selected duration',
        architecture='Same 2513-parameter recurrent network and zero/mean/ordered controls as fixed-budget study; direct/residual targets; AdamW .01lr/.01decay, gradient norm1',
        normalization='Train-only inside validation; separate full-known refit normalization; fixed60minute target scale; +-10 input z clipping',
        limitations='Retrospective single archive and small fixed architecture; nested choices use past labels only but do not supply independent future validation',
        sourceURLs=['https://docs.pytorch.org/docs/2.14/generated/torch.nn.GRU.html']),models={},events={})
    for name,p in forecasts.items():
        key=name.replace('careRecurrent','validatedCareRecurrent')
        r['models'][key]=dict(all=metrics(d['y'],p,np.ones(len(p),dtype=bool)))
        r['events'][key]=[dict(index=int(i),actual=float(y),prediction=float(v)) for i,y,v in zip(d['indices'],d['y'],p)]
        print(key,json.dumps(r['models'][key]),flush=True)
    args.output.write_text(json.dumps(r,indent=2,allow_nan=False)+'\n')


if __name__=='__main__':main()
