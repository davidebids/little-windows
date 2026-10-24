#!/usr/bin/env python3
"""Neutral derivative and integration checks for the external ODE bridge."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
import time
import numpy as np
from scipy.integrate import solve_ivp
from scipy.special import expit

INITIAL=np.array([.6,-6.7,14.6,.35,-.86,-.59])


def derivative(t,y,p):
    chi,mu,circadian,bias=p
    Vm,Vv,H,n,x,xc=y
    C=.5*(1+.8*xc-.47*x)
    clock=t%24
    light=20+490*(np.tanh((clock*3600-28800)/6000)-np.tanh((clock*3600-61200)/6000))
    alpha=.16*((light if Vm>Vv else 0)/9500)**.6
    B=(1-bias*x)*(1-bias*xc)*19.9*alpha*(1-n)
    Qm,Qv=360000*expit((np.array([Vm,Vv])-10)/3)
    return np.array([360*(-Vm-1.8/3600*Qv+1.3),
        360*(-Vv-2.1/3600*Qm+H+circadian*C-10.2),(-H+mu/3600*Qm)/chi,
        60*(alpha*(1-n)-.013*n),math.pi/12*(.23*(x-4/3*x**3)-xc*((24/(.99669*24.2))**2+.55*B)),
        math.pi/12*(x+B)])


def native(binary,p,hours,step,lower=0):
    return json.loads(subprocess.check_output([str(binary),'simulate',*[str(v) for v in p],str(hours),str(step),str(lower)]))


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--binary',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    rng=np.random.default_rng(42);maximum=0
    cases=[(np.array([45,4.2,-3.37,.4]),INITIAL.copy()),(np.array([np.exp(3.5),7.8,-3.25,.9]),INITIAL.copy())]
    for _ in range(15):cases.append((np.array([rng.uniform(4.5,45),rng.uniform(2.1,15.9),rng.uniform(-7,0),rng.uniform(.4,1)]),np.array([rng.uniform(-8,2),rng.uniform(-8,2),rng.uniform(8,20),rng.uniform(.1,.9),rng.uniform(-1,1),rng.uniform(-1,1)])))
    for p,y in cases:
        t=float(rng.uniform(-5,50));expected=derivative(t,y,p)
        actual=json.loads(subprocess.check_output([str(args.binary),'derivative',*[str(v) for v in p],str(t),*[str(v) for v in y]]))
        maximum=max(maximum,float(np.max(np.abs(actual-expected))));np.testing.assert_allclose(actual,expected,rtol=1e-12,atol=1e-9)
    trajectories={};started=time.monotonic()
    for label,p in [('referenceAdult',[45,4.2,-3.37,.4]),('referenceChild',[float(np.exp(3.5)),7.8,-3.25,.9])]:
        def onset(t,y):return y[0]-y[1]
        onset.direction=-1
        solution=solve_ivp(lambda t,y:derivative(t,y,p),(0,48),INITIAL,method='Radau',rtol=1e-8,atol=1e-10,max_step=1/60,events=onset)
        assert solution.success
        one=native(args.binary,p,48,1);half=native(args.binary,p,48,.5)
        expected=solution.t_events[0];a=np.array(one['onsetsHours']);b=np.array(half['onsetsHours'])
        assert len(expected)==len(a)==len(b)
        difference=float(np.max(np.abs(a-expected))*60);convergence=float(np.max(np.abs(a-b))*60)
        assert difference<.2 and convergence<.1
        trajectories[label]=dict(onsets=len(a),radauMaximumOnsetDifferenceMinutes=difference,halfStepMaximumOnsetDifferenceMinutes=convergence)
    p=[float(np.exp(3.5)),7.8,-3.25,.9];t=time.monotonic();long=native(args.binary,p,64*24,1,49*24);elapsed=time.monotonic()-t
    assert long['onsetsHours'] and np.isfinite(long['finalState']).all()
    r=dict(passed=True,derivativeCases=len(cases),maximumDerivativeDifference=maximum,trajectories=trajectories,checkSeconds=time.monotonic()-started,longSimulationSeconds=elapsed,longSimulationOnsets=len(long['onsetsHours']),binarySHA256=hashlib.sha256(args.binary.read_bytes()).hexdigest(),sourceSHA256=hashlib.sha256((Path(__file__).parent/'SleepReplay/NeuralSleepCore.cpp').read_bytes()).hexdigest(),reference='Independent direct-equation SciPy Radau, not an executed MATLAB runtime')
    args.output.write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r))


if __name__=='__main__':main()
