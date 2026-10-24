#!/usr/bin/env python3
"""Neutral independent slow-state and next-onset checks for diary forcing."""
import argparse
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path
import numpy as np
from scipy.integrate import solve_ivp
from scipy.special import expit
from check_sleep_neural_core import derivative,INITIAL


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--binary',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);args=ap.parse_args()
    pp=[[45.,4.2,-3.37,.4],[float(np.exp(3.5)),7.8,-3.25,.9]]
    queries=[[[-36.,-28.],[-8.,0.]],[[-36.,-28.],[-12.,-4.]]]
    lines=['2 2 1']+[' '.join(map(str,p)) for p in pp]+['-100 0']
    for intervals in queries:lines.append(' '.join(map(str,[0,-48,len(intervals),*[v for pair in intervals for v in pair]])))
    with tempfile.TemporaryDirectory(prefix='sleep-observer-neutral-') as tmp:
        path=Path(tmp)/'input.tsv';path.write_text('\n'.join(lines)+'\n')
        one=np.asarray(json.loads(subprocess.check_output([str(args.binary),str(path),'1','60'])))
        half=np.asarray(json.loads(subprocess.check_output([str(args.binary),str(path),'.5','30'])))
    errors=[];pressure_errors=[]
    for i,intervals in enumerate(queries):
        for j,p in enumerate(pp):
            y=INITIAL.copy();cursor=-48;H=y[2]
            segments=[]
            for start,end in intervals:segments.extend([(cursor,start,True),(start,end,False)]);cursor=end
            segments.append((cursor,0,True))
            for start,end,awake in segments:
                if end<=start:continue
                vm,vv=(1.3,-6.7) if awake else (-15,1.3)
                def forced(t,z):
                    z=z.copy();z[0]=vm;z[1]=vv;d=derivative(t,z,p);d[:2]=0;return d
                solution=solve_ivp(forced,(start,end),y,method='Radau',rtol=1e-9,atol=1e-11,max_step=1/30)
                assert solution.success;y=solution.y[:,-1]
                equilibrium=p[1]*100*expit((vm-10)/3)
                H=equilibrium+(H-equilibrium)*np.exp(-(end-start)/p[0])
            pressure_errors.append(abs(one[i,j,1]-H))
            slow=float(np.max(np.abs(one[i,j,1:]-y[2:])));assert slow<1e-6
            y[0]=1.3;y[1]=-6.7
            def onset(t,z):return z[0]-z[1]
            onset.direction=-1;onset.terminal=True
            solution=solve_ivp(lambda t,z:derivative(t,z,p),(0,8),y,method='Radau',rtol=1e-9,atol=1e-11,max_step=1/60,events=onset)
            assert solution.success
            expected=float(np.clip(solution.t_events[0][0]*60,1,480)) if len(solution.t_events[0]) else 480.
            onset_error=abs(one[i,j,0]-expected);assert onset_error<.01
            errors.append(dict(query=i,parameter=j,slowStateMaximumDifference=slow,onsetDifferenceMinutes=onset_error,predictionMinutes=float(one[i,j,0])))
    assert max(pressure_errors)<1e-7
    convergence=float(np.max(np.abs(one[:,:,0]-half[:,:,0])));assert convergence<.01
    r=dict(passed=True,cases=errors,maximumAnalyticPressureDifference=max(pressure_errors),halfStepMaximumOnsetDifferenceMinutes=convergence,
           sourceSHA256=hashlib.sha256((Path(__file__).parent/'SleepReplay/NeuralSleepObserver.cpp').read_bytes()).hexdigest(),binarySHA256=hashlib.sha256(args.binary.read_bytes()).hexdigest(),
           reference='Independent Radau forcing and release plus analytic forced pressure; observation rule is assumed, not physiological validation')
    args.output.write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r))


if __name__=='__main__':main()
