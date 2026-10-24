import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_adaptation import split_history,replay,expand_context

class PlanningAdaptationTests(unittest.TestCase):
    def fixture(self,n=100):
        w=np.arange(n,dtype=float)*86400
        d=dict(X=np.arange(n,dtype=float)[:,None],y=np.arange(n,dtype=float)+30,wakes=w)
        c=dict(labels=np.ones(n,int),knownAt=w+600,wakeClock=np.full(n,600.),X=np.zeros((n,11)))
        return d,c,np.full(n,100.)
    def factory(self,seen=None,bad=False):
        outer=self
        class Model:
            def __init__(self,mode):self.mode=mode;self.bestEpoch=0;self.trainingSteps=0
            def fit(self,X,y,X_val,y_val):
                self.train=X[:,0].copy();self.val=X_val[:,0].copy()
                outer.assertLess(self.train.max(),self.val.min())
                return self
            def update_context(self,X,y):
                self.point=float(np.median(y))
                if seen is not None:seen.append((self.mode,self.train,self.val,X[:,0].copy()))
            def predict(self,X,output_type):
                outer.assertEqual(len(X),1);outer.assertEqual(output_type,['mean','median'])
                return {k:[np.nan if bad else self.point] for k in ['mean','median']}
        return Model
    def test_chronological_validation_purges_unmatured_older_labels(self):
        d,c,b=self.fixture();known=np.arange(40);c['knownAt'][30]=d['wakes'][33]+100
        train,val=split_history(d,c,known)
        self.assertEqual(val.tolist(),list(range(32,40)));self.assertNotIn(30,train)
        seen=[];replay(d,c,b,self.factory(seen))
        for _,training,validation,context in seen[:2]:
            self.assertNotIn(30,training);self.assertIn(30,context);self.assertEqual(len(context),40)
    def test_full_known_context_and_only_planning_labels(self):
        d,c,b=self.fixture();seen=[];p,_=replay(d,c,b,self.factory(seen))
        self.assertEqual(p['frozenMedian'][40],49.5)
        for _,train,val,context in seen:self.assertEqual(len(context),len(train)+len(val))
        d,c,b=self.fixture();c['labels'][0]=0;c['knownAt'][1]=1e20;d['y'][2]=10;seen=[]
        replay(d,c,b,self.factory(seen))
        for _,train,val,context in seen:
            for j in [0,1,2]:self.assertNotIn(j,context)
    def test_current_future_outcomes_prefix_and_night_fallback(self):
        d,c,b=self.fixture();full,_=replay(d,c,b,self.factory());cut=80
        pre,_=replay({k:v[:cut] for k,v in d.items()},{k:v[:cut] for k,v in c.items()},b[:cut],self.factory())
        d['y'][cut-1:]=400;c['labels'][cut-1:]=2;d['X'][cut:]=999
        changed,_=replay(d,c,b,self.factory())
        for k in full:
            np.testing.assert_array_equal(full[k][:cut],pre[k]);np.testing.assert_array_equal(full[k][:cut],changed[k][:cut])
        d,c,b=self.fixture();c['wakeClock'][-1]=120;p,_=replay(d,c,b,self.factory())
        for v in p.values():self.assertEqual(v[-1],100)
    def test_expanded_context_preserves_selected_model_object(self):
        class Inner:
            def __init__(self,model):self.model_=model;self._load_model=lambda:None
            def fit(self,X,y):self.rows=len(X)
        class Wrapper:
            model_=object();n_estimators_inference=8
            def _resolve_device(self):return 'cpu'
            def _build_inner_estimator(self,model,n,device):return Inner(model)
            def _transform_X_for_inference(self,X):return X
        w=Wrapper();selected=w.model_
        expand_context(w,np.zeros((40,2)),np.zeros(40))
        self.assertIs(w._final_estimator_.model_,selected);self.assertEqual(w._final_estimator_.rows,40)
        self.assertTrue(w._final_estimator_._save_model_weights)

    def test_support_expiry_sparse_and_nonfinite_output(self):
        d,c,b=self.fixture(150);seen=[];replay(d,c,b,self.factory(seen))
        self.assertGreaterEqual(seen[-1][3].min(),68)
        d,c,b=self.fixture(20);p,diag=replay(d,c,b,self.factory());self.assertEqual(diag['refits'],0)
        for v in p.values():np.testing.assert_array_equal(v,b)
        d,c,b=self.fixture()
        with self.assertRaises(ValueError):replay(d,c,b,self.factory(bad=True))

if __name__=='__main__':unittest.main()
