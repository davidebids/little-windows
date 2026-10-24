#!/usr/bin/env python3
"""Compare a native chronological planning replay with its research forecasts."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import numpy as np
from research_sleep_behavior_schedule import structure
from research_sleep_planning import planning_mask


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['source','features','baseline','research','executable','output']: ap.add_argument('--'+name,type=Path,required=True)
    args=ap.parse_args(); root=Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root): ap.error('Keep private results outside source')
    import tempfile
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    d=dict(np.load(args.features,allow_pickle=False)); app=json.loads(args.baseline.read_text()); research=json.loads(args.research.read_text())
    assert app['audit']['sourceSHA256']==research['audit']['sourceSHA256']==sha(args.source)
    rows={r['index']:r for r in app['events']}; c=structure(args.source,d,rows,'America/Los_Angeles')
    x=np.column_stack([d['X'],c['X'][:,5:8]]); base=(np.array([rows[int(i)]['prediction'] for i in d['indices']])-d['wakes'])/60
    payload=dict(x=[[float(v) if np.isfinite(v) else None for v in row] for row in x],y=d['y'].tolist(),wakes=d['wakes'].tolist(),knownAt=c['knownAt'].tolist(),eligible=planning_mask(d,c).tolist(),fallback=base.tolist())
    with tempfile.TemporaryDirectory(prefix='lw-planning-parity-') as folder:
        a,b=Path(folder)/'input.json',Path(folder)/'output.json'; a.write_text(json.dumps(payload,allow_nan=False))
        subprocess.run([str(args.executable),str(a),str(b)],check=True)
        native=json.loads(b.read_text())
    expected=np.array([r['prediction'] for r in research['events']['pooled_planning']]); error=float(np.max(abs(expected-native['predictions'])))
    assert error<=1e-6,error
    result=dict(passed=True,queryCount=len(expected),maximumPredictionDifference=error,nativeRefits=native['refits'],sourceSHA256=sha(args.source),
        scope='Full chronological native parity for the selected research planning forest; not app integration or device validation.',
        sourceFilesSHA256={str(p.relative_to(root)):sha(p) for p in [root/'LittleWindows/Services/ReferenceSleepForest.swift',root/'Scripts/SleepReplay/PlanningReplay.swift',Path(__file__)]},researchSHA256=sha(args.research))
    args.output.write_text(json.dumps(result,indent=2)+'\n'); print(json.dumps(result),flush=True)

if __name__=='__main__': main()
