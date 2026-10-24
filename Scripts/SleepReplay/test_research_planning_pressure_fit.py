from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import numpy as np
from scipy.optimize import brentq
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_pressure_fit import PressureModel,INITIAL,replay


class PlanningPressureFitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder=tempfile.TemporaryDirectory(prefix='neutral-pressure-model-')
        cls.binary=Path(cls.folder.name)/'pressure.dylib'
        subprocess.run(['xcrun','clang++','-O3','-std=c++17','-dynamiclib',str(Path(__file__).with_name('PlanningPressureFit.cpp')),'-o',str(cls.binary)],check=True,capture_output=True)

    @classmethod
    def tearDownClass(cls):cls.folder.cleanup()

    def model(self,sleeps,indices,clocks):
        m=PressureModel(self.binary,np.asarray(sleeps,float),indices,clocks);self.addCleanup(m.close);return m

    def test_analytic_pressure_and_constant_threshold_crossing(self):
        m=self.model([[0,1800],[5400,7200]],[0,1],[600.,720.])
        params=INITIAL.copy();params[2:]=[.7,0,0]
        _,points,states=m.evaluate([0,1],params)
        first=.5*np.exp(-30/120)
        second=(1-(1-first)*np.exp(-60/240))*np.exp(-30/120)
        np.testing.assert_allclose(states,[first,second],rtol=0,atol=1e-14)
        exact=-240*np.log((1-.7)/(1-states))
        np.testing.assert_allclose(points,np.clip(exact,1,480),rtol=0,atol=.001)
        targets=points+np.array([10.,40.]);loss,_,_=m.evaluate([0,1],params,targets,np.array([2.,1.]),30)
        self.assertAlmostEqual(loss,(20+40+30)/3)

    def test_completed_union_and_future_records_do_not_change_wake_states(self):
        a=self.model([[0,3600],[1800,5400],[7200,9000]],[1,2],[90,150])
        b=self.model([[0,3600],[1800,5400],[7200,9000],[10000,20000]],[1,2],[90,150])
        _,pa,sa=a.evaluate([0,1],INITIAL);_,pb,sb=b.evaluate([0,1],INITIAL)
        np.testing.assert_array_equal(pa,pb);np.testing.assert_array_equal(sa,sb)
        first=.5*np.exp(-90/120)
        second=(1-(1-first)*np.exp(-30/240))*np.exp(-30/120)
        np.testing.assert_allclose(sa,[first,second],rtol=0,atol=1e-14)
        np.testing.assert_array_equal(a.evaluate([0],INITIAL)[1],pa[:1])

    def test_oscillating_threshold_matches_independent_fine_grid_and_root(self):
        clocks=[240,600,1000,1320];m=self.model([[0,3600]],[0]*4,clocks)
        for params in [np.array([np.log(120),np.log(60),.65,.2,-.1]),np.array([np.log(480),np.log(240),.8,-.25,.15])]:
            _,points,states=m.evaluate(np.arange(4),params)
            for clock,state,point in zip(clocks,states,points):
                def difference(t):
                    angle=(clock+t)*2*np.pi/1440
                    threshold=np.clip(params[2]+params[3]*np.sin(angle)+params[4]*np.cos(angle),.01,.99)
                    return 1-(1-state)*np.exp(-t/np.exp(params[0]))-threshold
                grid=np.arange(0,480.001,.05);values=difference(grid);cross=np.flatnonzero(values>=0)
                if not len(cross):expected=480.
                elif cross[0]==0:expected=1.
                else:expected=np.clip(brentq(difference,grid[cross[0]-1],grid[cross[0]]),1,480)
                self.assertAlmostEqual(point,expected,delta=.01)

    def test_replay_prefix_unresolved_labels_and_overnight_preservation(self):
        n=78;i=np.arange(n);sleeps=np.column_stack([i*8*3600,i*8*3600+3600]).astype(float);wakes=sleeps[:,1]
        data=dict(indices=i,wakes=wakes,y=90.+i%30,X=np.full((n,1),60.),names=['lastDuration'])
        context=dict(labels=np.ones(n,int),knownAt=wakes+18000,wakeClock=np.full(n,600.))
        context['knownAt'][20]=1e20;context['wakeClock'][::13]=120
        m=self.model(sleeps,i,context['wakeClock']);base=np.full(n,110.)
        full,_=replay(data,context,base,m,maxfev=8)
        short={k:(v if k=='names' else v[:70]) for k,v in data.items()}
        prefix,_=replay(short,{k:v[:70] for k,v in context.items()},base[:70],m,maxfev=8)
        altered={k:(v.copy() if isinstance(v,np.ndarray) else v) for k,v in data.items()};altered['y'][20]=9999;altered['y'][69:]=9999
        changedContext={k:v.copy() for k,v in context.items()};changedContext['labels'][20]=0;changedContext['labels'][69:]=0
        changed,_=replay(altered,changedContext,base,m,maxfev=8)
        for name,p in full.items():
            np.testing.assert_array_equal(p[:70],prefix[name]);np.testing.assert_array_equal(p[:70],changed[name][:70])
            np.testing.assert_array_equal(p[:41],base[:41]);np.testing.assert_array_equal(p[::13],base[::13])
            self.assertTrue(np.isfinite(p).all())


if __name__=='__main__':unittest.main()
