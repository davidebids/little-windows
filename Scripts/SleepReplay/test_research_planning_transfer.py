import csv
from pathlib import Path
import sys
import tempfile
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_transfer import read_grid,diary_blocks,WeightedForest,replay


class PlanningTransferTests(unittest.TestCase):
    def test_grid_ages_and_unknown_annotations(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'diary.csv'
            with path.open('w') as handle:
                writer=csv.writer(handle);writer.writerow(['time',86,87,''])
                for i in range(96):writer.writerow([i/4,'S' if i<12 else '', 'NOTE' if i==24 else 'E',''])
            age,states=read_grid(path)
            self.assertEqual(age,86);self.assertEqual(len(states),192)
            np.testing.assert_array_equal(states[:13],[1]*12+[0])
            self.assertEqual(states[120],-1)
            with path.open() as handle:rows=list(csv.reader(handle))
            rows[0][2]='89'
            with path.open('w') as handle:csv.writer(handle).writerows(rows)
            with self.assertRaises(ValueError):read_grid(path)

    def test_unknown_cells_and_file_edges_censor_sleep(self):
        # The sleep touching an unknown state is not turned into an observed wake.
        states=np.array([1,1,0,1,1,0,1,0,-1,1,1,0,1,0,1,0,1])
        blocks=diary_blocks(86,states)
        self.assertEqual(len(blocks),2)
        np.testing.assert_array_equal(blocks[0][1][:,:2],[[86*86400+3*900,86*86400+5*900],[86*86400+6*900,86*86400+7*900]])
        np.testing.assert_array_equal(blocks[1][1][:,:2],[[86*86400+12*900,86*86400+13*900],[86*86400+14*900,86*86400+15*900]])

    def test_weighted_median_action(self):
        x=np.zeros((10,3));y=np.arange(10.)
        model=WeightedForest().fit(x,y,np.array([1]*9+[100.]))
        self.assertEqual(model.predict(x[:1])[0],9.)

    def test_prefix_future_outcomes_age_range_and_overnight(self):
        n=78;i=np.arange(n);wakes=1e7+i*86400.
        X=np.column_stack([86+i,np.sin(i),np.cos(i)])
        data=dict(X=X,names=np.array(['ageDays','clockSin1','clockCos1']),y=80.+i%40,wakes=wakes)
        C=np.zeros((n,11));C[:,5]=60;C[:,6]=1;C[:,7]=i%3
        context=dict(X=C,labels=np.ones(n,int),knownAt=wakes+18000,wakeClock=np.full(n,600.))
        context['knownAt'][30]=1e20;context['wakeClock'][::13]=120
        donorX=np.column_stack([np.linspace(90,160,80),np.sin(np.arange(80)),np.cos(np.arange(80)),np.full(80,60),np.ones(80),np.arange(80)%3])
        donorY=90.+np.arange(80)%30;base=np.full(n,110.)
        full,_=replay(data,context,base,donorX,donorY)
        short,_=replay({k:(v[:68] if k!='names' else v) for k,v in data.items()},{k:v[:68] for k,v in context.items()},base[:68],donorX,donorY)
        altered={k:v.copy() for k,v in data.items()};changedContext={k:v.copy() for k,v in context.items()}
        altered['y'][30]=9999;changedContext['labels'][30]=0;altered['y'][67:]=9999;changedContext['labels'][67:]=0
        changed,_=replay(altered,changedContext,base,donorX,donorY)
        for name,p in full.items():
            np.testing.assert_array_equal(p[:68],short[name]);np.testing.assert_array_equal(p[:68],changed[name][:68])
            np.testing.assert_array_equal(p[::13],base[::13]);np.testing.assert_array_equal(p[:4],base[:4]);np.testing.assert_array_equal(p[75:],base[75:])
            self.assertTrue(np.isfinite(p).all())


if __name__=='__main__':unittest.main()
