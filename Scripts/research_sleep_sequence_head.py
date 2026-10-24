#!/usr/bin/env python3
"""Past-only supervised heads over frozen sequence representations; local research."""
import argparse
import hashlib
import json
from pathlib import Path
import time
import numpy as np
from research_sleep_sequence_prior import CONTEXT_NAMES
from research_sleep_ensemble import combine, metrics


def embedding_query(data, i, multivariate):
    known = np.flatnonzero((np.arange(len(data['y'])) < i) & (data['available'] <= data['wakes'][i])
                          & (data['wakes'] >= data['wakes'][i] - 60 * 86400))[-128:]
    if len(known) < 8:
        return None
    target = data['y'][known]
    if not multivariate:
        return target.astype(np.float32)
    columns = [list(data['names']).index(n) for n in CONTEXT_NAMES]
    return np.vstack([target, data['X'][known][:, columns].T]).astype(np.float32)


def representations(data, encode, progress=None):
    result = {}
    for name, multi in [('gap128', False), ('context128', True)]:
        rows = []
        for i in range(len(data['y'])):
            query = embedding_query(data, i, multi)
            value = None if query is None else np.asarray(encode(query), dtype=float)
            if value is not None and (value.shape != (768,) or not np.isfinite(value).all()):
                raise ValueError('Expected a finite target-channel masked-token representation')
            rows.append(value)
            if progress and (i + 1) % 200 == 0:
                progress(name, i + 1)
        result[name] = np.array([np.full(768, np.nan) if v is None else v for v in rows])
    return result


def fit_ridge(train_latent, train_context, target, weights, alpha):
    # Training-only block scaling gives equal total weight to encoder and
    # current-wake features regardless of their different widths.
    blocks, scalers = [], []
    for train in [train_latent, train_context]:
        finite = np.isfinite(train)
        denominator = np.sum(finite * weights[:, None], axis=0)
        mean = np.divide(np.sum(np.where(finite, train, 0.) * weights[:, None], axis=0),
                         denominator, out=np.zeros(train.shape[1]), where=denominator > 0)
        train = np.where(finite, train, mean)
        scale = np.maximum(np.sqrt(np.average((train - mean) ** 2, axis=0, weights=weights)), 1e-3)
        scale = scale * np.sqrt(train.shape[1])
        blocks.append((train - mean) / scale)
        scalers.append((mean, scale))
    X = np.column_stack(blocks)
    center = np.average(target, axis=0, weights=weights)
    sw = np.sqrt(weights / np.mean(weights))
    A = X * sw[:, None]
    dual = np.linalg.solve(A @ A.T + alpha * np.eye(len(A)), (target - center) * sw[:, None])
    return scalers, center, A.T @ dual


def predict_ridge(fit, query_latent, query_context):
    scalers, center, coefficient = fit
    q = np.concatenate([(np.where(np.isfinite(q), q, mean) - mean) / scale for q, (mean, scale)
                        in zip([query_latent, query_context], scalers)])
    return center + q @ coefficient


def heads(data, latent, fallback):
    outputs, counts = {}, {}
    for name, Z in latent.items():
        valid = np.isfinite(Z).all(axis=1)
        for alpha in [.1, 1.]:
            points = np.column_stack([fallback, fallback]).copy()
            fit, last, fits = None, -100, 0
            for i in range(len(fallback)):
                eligible = np.flatnonzero((np.arange(len(fallback)) < i) & valid
                    & (data['available'] <= data['wakes'][i])
                    & (data['wakes'] >= data['wakes'][i] - 60 * 86400))
                if not valid[i] or len(eligible) < 40:
                    continue
                if fit is None or i - last >= 24:
                    train, last, fits = eligible, i, fits + 1
                    weights = np.exp2(-(data['wakes'][i] - data['wakes'][train]) / (14 * 86400))
                    targets = np.column_stack([data['y'][train], data['y'][train] - fallback[train]])
                    fit = fit_ridge(Z[train], data['X'][train], targets, weights, alpha)
                prediction = predict_ridge(fit, Z[i], data['X'][i])
                points[i] = np.clip([prediction[0], fallback[i] + prediction[1]], 1, 480)
            for j, kind in enumerate(['direct', 'residual']):
                key = f'{name}_{kind}_a{alpha:g}'
                outputs[key], counts[key] = points[:, j], fits
    return outputs, counts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['source', 'features', 'baseline', 'bootstrap', 'model', 'cache', 'output']:
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if any(p.resolve().is_relative_to(root) for p in [args.cache, args.output]):
        parser.error('Keep personal numeric caches and results outside the repository')
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    boot = json.loads(args.bootstrap.read_text());assert boot['passed']
    for n, digest in boot['modelFiles'].items():
        assert sha(args.model / n) == digest
    data = dict(np.load(args.features, allow_pickle=False))
    base = json.loads(args.baseline.read_text());assert sha(args.source) == base['audit']['sourceSHA256']
    by = {r['index']: r for r in base['events']};indices = data['indices'].astype(int).tolist();assert set(by) == set(indices)
    np.testing.assert_allclose([by[i]['actual'] for i in indices], data['available'], rtol=0, atol=1e-6)
    np.testing.assert_allclose([by[i]['wakeMinutes'] for i in indices], data['y'], rtol=0, atol=1e-6)
    fallback = (np.array([by[i]['prediction'] for i in indices]) - data['wakes']) / 60
    import torch
    import chronos
    from chronos import Chronos2Pipeline
    torch.set_num_threads(2);torch.manual_seed(42)
    pipeline = Chronos2Pipeline.from_pretrained(args.model, device_map='cpu', dtype=torch.float32);pipeline.model.eval()
    def encode(query):
        embeddings, _ = pipeline.embed([query], context_length=128)
        # Upstream documents the final token as the masked output patch.
        return embeddings[0][0, -1].detach().cpu().numpy()
    started = time.monotonic()
    def progress(name, cases):
        print(json.dumps(dict(configuration=name, cases=cases, seconds=time.monotonic() - started)), flush=True)
    Z = representations(data, encode, progress)
    np.savez_compressed(args.cache, **Z)
    forecasts, fits = heads(data, Z, fallback)
    result = dict(audit=dict(sourceSHA256=sha(args.source), careExposure='completed',
        scriptSHA256=sha(Path(__file__)), featureCacheSHA256=sha(args.features), baselineResultSHA256=sha(args.baseline),
        representationCacheSHA256=sha(args.cache), modelFiles=boot['modelFiles'], library='chronos-forecasting',
        version=chronos.__version__, torchVersion=torch.__version__, threads=2, contextLimit=128,
        contextNames=CONTEXT_NAMES, minimumEncoderLabels=8, minimumHeadLabels=40, refitEvery=24,
        lookbackDays=60, weightHalfLifeDays=14, alpha=[.1, 1.], frozenEncoder=True,
        method='Single-query causal masked target-token embeddings plus known wake context; training-only block scaling; direct/residual weighted ridge',
        sourceURLs=['https://github.com/amazon-science/chronos-forecasting', 'https://arxiv.org/abs/2510.15821']), models={}, events={})
    def save(name, prediction, refits=None):
        assert np.isfinite(prediction).all()
        result['models'][name] = dict(all=metrics(data['y'], prediction, np.ones(len(indices), dtype=bool)))
        if refits is not None:
            result['models'][name]['refits'] = refits
        result['events'][name] = [dict(index=i, actual=float(y), prediction=float(p)) for i,y,p in zip(indices,data['y'],prediction)]
        args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + '\n')
        print(name, json.dumps(result['models'][name]), flush=True)
    for name, prediction in forecasts.items():
        save(name, prediction, fits[name])
    members = np.column_stack([fallback, *forecasts.values()])
    for name, policy, cal, local in [('localCalibratedSoft','soft',True,True),('localCalibratedBest','best',True,True),
        ('localRawSoft','soft',False,True),('globalCalibratedSoft','soft',True,False),('calibratedMedian','median',True,True)]:
        save('sequenceHead_' + name, combine(data, members, policy, cal, local))


if __name__ == '__main__':
    main()
