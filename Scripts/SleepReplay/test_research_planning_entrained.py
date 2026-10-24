from pathlib import Path
import json
import subprocess
import sys
import tempfile
import unittest
import numpy as np
from scipy.integrate import solve_ivp
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from check_sleep_neural_core import derivative,INITIAL
from research_sleep_planning_entrained import replay


class PlanningEntrainedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder=tempfile.TemporaryDirectory(prefix='neutral-initialization-check-')
        cls.binary=Path(cls.folder.name)/'observer'
        subprocess.run(['xcrun','clang++','-O3','-std=c++17',str(Path(__file__).with_name('NeuralSleepEntrainedObserver.cpp')),'-o',str(cls.binary)],check=True,capture_output=True)

    @classmethod
    def tearDownClass(cls):cls.folder.cleanup()

    def native(self,queries,step=1,forcing=60,shift=0):
        p=[float(np.exp(3.5)),7.8,-3.25,.9]
        lines=[f'{len(queries)} 1 1',' '.join(map(str,p)),'-1000000 0']
        for now,start,intervals in queries:
            lines.append(' '.join(map(str,[now+shift,start+shift,len(intervals),*[v+shift for pair in intervals for v in pair]])))
        path=Path(self.folder.name)/'input.tsv';path.write_text('\n'.join(lines)+'\n')
        return np.asarray(json.loads(subprocess.check_output([str(self.binary),str(path),str(step),str(forcing),'56'])))

    def test_neutral_then_observed_states_and_onset_match_independent_radau(self):
        p=[float(np.exp(3.5)),7.8,-3.25,.9];y=INITIAL.copy()
        def integrate(y,start,end,awake):
            if end<=start:return y
            def rhs(t,z):
                z=z.copy();z[:2]=[1.3,-6.7] if awake else [-15,1.3]
                d=derivative(t,z,p);d[:2]=0;return d
            solution=solve_ivp(rhs,(start,end),y,method='Radau',rtol=1e-9,atol=1e-11,max_step=.5)
            self.assertTrue(solution.success);return solution.y[:,-1]
        for day in range(56):
            t=day*24;y=integrate(y,t,t+7,False);y=integrate(y,t+7,t+19,True);y=integrate(y,t+19,t+24,False)
        for a,b,awake in [(-48,-36,True),(-36,-28,False),(-28,-8,True),(-8,0,False)]:y=integrate(y,a,b,awake)
        actual=self.native([(0,-48,[[-36,-28],[-8,0]])])[0,0]
        np.testing.assert_allclose(actual[1:],y[2:],rtol=0,atol=1e-5)
        y[:2]=[1.3,-6.7]
        def onset(t,z):return z[0]-z[1]
        onset.direction=-1;onset.terminal=True
        solution=solve_ivp(lambda t,z:derivative(t,z,p),(0,8),y,method='Radau',rtol=1e-9,atol=1e-11,max_step=1/60,events=onset)
        self.assertTrue(solution.success)
        expected=np.clip(solution.t_events[0][0]*60,1,480) if len(solution.t_events[0]) else 480
        self.assertAlmostEqual(actual[0],expected,delta=.01)

    def test_native_prefix_calendar_phase_and_half_step_convergence(self):
        queries=[(0,-48,[[-36,-28],[-8,0]]),(5,-43,[[-36,-28],[-8,0]])]
        full=self.native(queries);prefix=self.native(queries[:1]);half=self.native(queries,.5,30)
        shifted=self.native(queries,shift=24*20)
        np.testing.assert_array_equal(full[:1],prefix)
        np.testing.assert_allclose(full,shifted,rtol=0,atol=1e-7)
        np.testing.assert_allclose(full[:,:,0],half[:,:,0],rtol=0,atol=.01)
        np.testing.assert_allclose(full[:,:,1:],half[:,:,1:],rtol=0,atol=1e-5)

    def test_planning_and_blend_prefix_unresolved_labels_and_overnight(self):
        n=90;i=np.arange(n);wakes=1e7+i*86400.
        data=dict(X=np.full((n,1),60.),names=['lastDuration'],y=np.full(n,120.),wakes=wakes)
        context=dict(labels=np.ones(n,int),knownAt=wakes+20000,wakeClock=np.full(n,600.))
        context['knownAt'][20]=1e20;context['wakeClock'][::13]=120
        bank=np.tile([15.,120.,240.],(n,1));base=np.full(n,99.)
        full,_=replay(data,context,base,bank)
        short={k:(v if k=='names' else v[:70]) for k,v in data.items()}
        prefix,_=replay(short,{k:v[:70] for k,v in context.items()},base[:70],bank[:70])
        changed=dict(data,y=data['y'].copy());changed['y'][20]=9999;changed['y'][69:]=9999
        cc={k:v.copy() for k,v in context.items()};cc['labels'][20]=0;cc['labels'][69:]=0
        altered,_=replay(changed,cc,base,bank)
        for name,p in full.items():
            np.testing.assert_array_equal(p[:70],prefix[name]);np.testing.assert_array_equal(p[:70],altered[name][:70]);np.testing.assert_array_equal(p[::13],base[::13])


if __name__=='__main__':unittest.main()
