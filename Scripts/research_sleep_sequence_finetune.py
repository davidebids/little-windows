#!/usr/bin/env python3
"""Local chronological full-weight adaptation of a sequence forecaster."""
import argparse
import hashlib
import json
from pathlib import Path
import time
import numpy as np
from research_sleep_sequence_prior import query_at, decision_points
from research_sleep_ensemble import combine, metrics

CONFIGS = [('context10steps', 10), ('context30steps', 30)]


def training_query(query):
    # Only identify known-future channels for training. Its supervised slices
    # come entirely from the resolved historical target and covariates.
    return dict(target=query['target'].copy(),
        past_covariates={k:v.copy() for k,v in query['past_covariates'].items()},
        future_covariates={k:None for k in query['future_covariates']})


def replay(data, fallback, fit, predict, levels, configs=CONFIGS, progress=None):
    outputs, diagnostics = {}, {}
    for name, steps in configs:
        points = {key:fallback.copy() for key in ['median','risk']}
        model, last, refits, issued, crossing = None, -100, 0, 0, 0
        for i in range(len(fallback)):
            query = query_at(data, i, 128, True)
            if query is None:
                continue
            if model is None or i-last>=48:
                model = fit(training_query(query), steps)
                last, refits = i, refits+1
                if progress:
                    progress(name, i, refits)
            values, crossed = decision_points(predict(model, query), levels)
            for key in points:
                points[key][i] = values[key]
            issued, crossing = issued+1, crossing+crossed
        outputs.update({name+'_'+k:v for k,v in points.items()})
        diagnostics[name] = dict(refits=refits, issuedQueries=issued, crossedQuantileQueries=crossing, stepsPerRefit=steps)
    return outputs, diagnostics


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','baseline','bootstrap','fit-bootstrap','context-bootstrap','model','work','output']:
        parser.add_argument('--'+name,type=Path,required=True)
    args=parser.parse_args();root=Path(__file__).resolve().parents[1]
    if any(p.resolve().is_relative_to(root) for p in [args.work,args.output]):
        parser.error('Keep weights and private results outside the repository')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    boot=json.loads(args.bootstrap.read_text());fit_boot=json.loads(args.fit_bootstrap.read_text())
    assert boot['passed'] and fit_boot['passed'] and fit_boot['repeatMaxDifference']<=1e-6
    context_boot=json.loads(args.context_bootstrap.read_text())
    assert context_boot['passed'] and context_boot['repeatedFitDifference']<=1e-6 and context_boot['channels']==8
    for n,h in boot['modelFiles'].items():assert sha(args.model/n)==h
    assert fit_boot['weightsSHA256']==boot['modelFiles']['model.safetensors']
    data=dict(np.load(args.features,allow_pickle=False));base=json.loads(args.baseline.read_text())
    assert sha(args.source)==base['audit']['sourceSHA256']
    rows={r['index']:r for r in base['events']};indices=data['indices'].astype(int).tolist();assert set(rows)==set(indices)
    np.testing.assert_allclose([rows[i]['actual'] for i in indices],data['available'],rtol=0,atol=1e-6)
    np.testing.assert_allclose([rows[i]['wakeMinutes'] for i in indices],data['y'],rtol=0,atol=1e-6)
    fallback=(np.array([rows[i]['prediction'] for i in indices])-data['wakes'])/60
    import torch
    import chronos
    from chronos import Chronos2Pipeline
    torch.set_num_threads(2);torch.manual_seed(42)
    pipeline=Chronos2Pipeline.from_pretrained(args.model,device_map='cpu',dtype=torch.float32);pipeline.model.eval()
    started=time.monotonic()
    def fit(query,steps):
        # A fresh copy of the public base is fitted at every origin. Never
        # warm-start from weights that could have seen a later label.
        adapted=pipeline.fit([query],prediction_length=1,context_length=128,num_steps=steps,
            batch_size=8,min_past=8,learning_rate=1e-5,output_dir=args.work,
            report_to='none',disable_tqdm=True,seed=42,optim='adamw_torch',
            logging_strategy='no',remove_printer_callback=True)
        adapted.model.eval()
        return adapted
    def predict(model,query):
        v=model.predict([query],prediction_length=1,context_length=128,cross_learning=False)[0]
        assert tuple(v.shape)==(1,len(pipeline.quantiles),1)
        return v[0,:,0].detach().cpu().numpy()
    def progress(name,index,refits):
        print(json.dumps(dict(configuration=name,case=index,refits=refits,seconds=time.monotonic()-started)),flush=True)
    forecasts,diag=replay(data,fallback,fit,predict,pipeline.quantiles,progress=progress)
    result=dict(audit=dict(sourceSHA256=sha(args.source),careExposure='completed',library='chronos-forecasting',
        version=chronos.__version__,torchVersion=torch.__version__,modelFiles=boot['modelFiles'],
        scriptSHA256=sha(Path(__file__)),featureCacheSHA256=sha(args.features),baselineResultSHA256=sha(args.baseline),
        contextLength=128,lookbackDays=60,minimumLabels=40,refitEvery=48,learningRate=1e-5,batchSize=8,
        minPast=8,optimizer='adamw_torch',seed=42,device='cpu',threads=2,fullWeightFit=True,
        freshBaseEachRefit=True,modelEvalBeforePrediction=True,diagnostics=diag,
        rule='Training slices use resolved history only; single-query current-wake prediction; original fallback warmup',
        sourceURLs=['https://github.com/amazon-science/chronos-forecasting','https://arxiv.org/abs/2510.15821']),models={},events={})
    def save(name,p):
        assert np.isfinite(p).all()
        result['models'][name]=dict(all=metrics(data['y'],p,np.ones(len(indices),dtype=bool)))
        result['events'][name]=[dict(index=i,actual=float(y),prediction=float(v)) for i,y,v in zip(indices,data['y'],p)]
        args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')
        print(name,json.dumps(result['models'][name]),flush=True)
    for name,p in forecasts.items():save(name,p)
    members=np.column_stack([fallback,*forecasts.values()])
    for name,policy,cal,local in [('localCalibratedSoft','soft',True,True),('localCalibratedBest','best',True,True),
        ('localRawSoft','soft',False,True),('globalCalibratedSoft','soft',True,False),('calibratedMedian','median',True,True)]:
        save('finetune_'+name,combine(data,members,policy,cal,local))


if __name__=='__main__':main()
