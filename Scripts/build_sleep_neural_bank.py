#!/usr/bin/env python3
"""Build a neutral, numerically checked bank of six-state model trajectories."""
import argparse
import hashlib
import itertools
import json
import math
from pathlib import Path
import subprocess
import tempfile
import time
import numpy as np


def parameter_grid():
    values=list(itertools.product([math.exp(1.5),15.,math.exp(3.5)],[6.,10.2,14.4],[0.,-2.,-4.],[.4,.9]))
    values.extend([(45.,4.2,-3.37,.4),(math.exp(3.5),7.8,-3.25,.9)])
    return values


def convergence(one,half,tolerance=.25):
    assert len(one)==len(half)
    accepted=[];diagnostics=[]
    for i,(a,b) in enumerate(zip(one,half)):
        assert a['parameters']==b['parameters']
        maximum=0.;same=a['initialWake']==b['initialWake']
        for key in ['onsetsHours','wakesHours']:
            if len(a[key])!=len(b[key]):same=False
            elif a[key]:maximum=max(maximum,float(np.max(np.abs(np.array(a[key])-b[key]))*60))
        good=same and maximum<=tolerance and bool(a['onsetsHours'])
        if good:accepted.append(b)
        diagnostics.append(dict(index=i,accepted=good,matchingTransitionCounts=same,maximumTransitionDifferenceMinutes=maximum))
    return accepted,diagnostics


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for n in ['binary','core-check','upstream','output','check-output']:parser.add_argument('--'+n,type=Path,required=True)
    args=parser.parse_args();root=Path(__file__).resolve().parents[1]
    if any(p.resolve().is_relative_to(root) for p in [args.output,args.check_output]):parser.error('Keep neutral simulation banks outside source')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();check=json.loads(args.core_check.read_text());assert check['passed'] and check['binarySHA256']==sha(args.binary)
    assert check['sourceSHA256']==sha(Path(__file__).parent/'SleepReplay/NeuralSleepCore.cpp')
    upstream=json.loads((args.upstream/'source-hashes.json').read_text());assert all(sha(args.upstream/n)==h for n,h in upstream.items())
    started=time.monotonic();values=parameter_grid()
    with tempfile.TemporaryDirectory(prefix='lw-neutral-ode-',dir='/tmp') as temp:
        path=Path(temp)/'parameters.tsv';path.write_text('\n'.join(' '.join(format(v,'.17g') for v in row) for row in values)+'\n')
        runs=[]
        for step in [1.,.5]:
            result=subprocess.run([str(args.binary),'bank',str(path),str(step)],check=True,capture_output=True,text=True)
            runs.append(json.loads(result.stdout));print(json.dumps(dict(stepSeconds=step,simulations=len(runs[-1]),seconds=time.monotonic()-started)),flush=True)
    accepted,diagnostics=convergence(*runs)
    assert accepted
    bank=dict(models=accepted,modelWindowHours=14*24,lookaheadHours=24,stepSeconds=.5,
        warmupDays=28,totalSimulationDays=64,referenceWindowStartDay=49,assumedLight=dict(dayLux=1000,eveningLux=20,dawnHour=8,duskHour=17),
        binarySHA256=sha(args.binary),coreSourceSHA256=check['sourceSHA256'],upstreamFilesSHA256=upstream)
    args.output.write_text(json.dumps(bank,indent=2)+'\n')
    report=dict(passed=True,requestedParameters=len(values),acceptedParameters=len(accepted),diagnostics=diagnostics,
        maximumAcceptedTransitionDifferenceMinutes=max(v['maximumTransitionDifferenceMinutes'] for v in diagnostics if v['accepted']),
        toleranceMinutes=.25,seconds=time.monotonic()-started,bankSHA256=sha(args.output),binarySHA256=sha(args.binary),
        builderSHA256=sha(Path(__file__)),upstreamFilesSHA256=upstream,
        scope='Neutral model convergence check, not infant forecast accuracy; parameters rejected only for numerical instability before private evaluation')
    args.check_output.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(dict(accepted=len(accepted),maximumDifference=report['maximumAcceptedTransitionDifferenceMinutes'],seconds=report['seconds'])))


if __name__=='__main__':main()
