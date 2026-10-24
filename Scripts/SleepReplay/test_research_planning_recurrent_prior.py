import hashlib
import sys
import tempfile
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research_sleep_planning_recurrent_prior import request,replay,covariates,validate_bootstrap


class RecurrentPriorTests(unittest.TestCase):
    def fixture(self,n=40):
        w=100000+np.arange(n)*10800.;y=100+np.arange(n,dtype=float)
        return dict(wakes=w,y=y),dict(knownAt=w+600,labels=np.ones(n,int)),np.full(n,99.),np.arange(n*7,dtype=float).reshape(n,7)/100

    def test_forecast_step_contains_current_inputs_only(self):
        d,c,b,X=self.fixture();c['knownAt'][5]=d['wakes'][10]+1
        item,known=request(d,c,X,10,True)
        self.assertNotIn(5,known);self.assertNotIn(10,known)
        np.testing.assert_array_equal(item['target'][0],d['y'][known].astype(np.float32))
        np.testing.assert_array_equal(item['future_covariates'][:,-1],X[10].astype(np.float32))
        np.testing.assert_array_equal(item['future_covariates'][:,:-1],X[known].T.astype(np.float32))
        self.assertIsNone(request(d,c,X,10,False)[0]['future_covariates'])

    def test_prefix_current_future_label_isolation_and_fail_fast(self):
        d,c,b,X=self.fixture();predict=lambda args:float(args['target'][0,-1]+(args['future_covariates'][0,-1] if args['future_covariates'] is not None else 0))
        full,diag=replay(d,c,b,X,predict);cut=25
        pre,_=replay({k:v[:cut] for k,v in d.items()},{k:v[:cut] for k,v in c.items()},b[:cut],X[:cut],predict)
        d['y'][cut-1:]=99999;c['labels'][cut-1:]=0;X[cut:]=99999
        changed,_=replay(d,c,b,X,predict)
        for name in full:
            np.testing.assert_array_equal(full[name][:cut],pre[name]);np.testing.assert_array_equal(full[name][:cut],changed[name][:cut])
            np.testing.assert_array_equal(full[name][:3],b[:3])
        self.assertGreater(diag['issuedQueries'],0)
        with self.assertRaises(RuntimeError):replay(d,c,b,X,lambda _:np.nan)

    def test_maturity_expiry_and_minimum_context(self):
        d,c,b,X=self.fixture();c['knownAt'][:]=d['wakes'][-1]+86400
        out,_=replay(d,c,b,X,lambda _:123.)
        for values in out.values():np.testing.assert_array_equal(values,b)
        d,c,b,X=self.fixture();d['wakes'][30:]+=61*86400;c['knownAt'][30:]+=61*86400
        out,_=replay(d,c,b,X,lambda _:123.)
        for values in out.values():np.testing.assert_array_equal(values[30:33],b[30:33])

    def test_named_covariates_and_nonfinite_rejection(self):
        names=['ageDays','clockSin1','clockCos1','lastDuration','lastNight','sleepMinutes24h'];d=dict(names=names,X=np.arange(18.).reshape(3,6));c=dict(X=np.arange(33.).reshape(3,11))
        X,selected=covariates(d,c);np.testing.assert_array_equal(X[:,:6],d['X']);np.testing.assert_array_equal(X[:,6],c['X'][:,7]);self.assertEqual(len(selected),7)
        d['X'][0,0]=np.nan
        with self.assertRaises(ValueError):covariates(d,c)

    def test_bootstrap_hashes_must_match_before_private_inference(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'model').write_text('public weights');(root/'source.py').write_text('public code')
            sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
            boot=dict(passed=True,publicOnly=True,repeatedExact=True,shortContextSupported=True,crossModeIsolated=True,modelFilesSHA256={'model':sha(root/'model')},packageSourceSHA256={'source.py':sha(root/'source.py')})
            validate_bootstrap(boot,root,root);(root/'source.py').write_text('changed')
            with self.assertRaises(ValueError):validate_bootstrap(boot,root,root)


if __name__=='__main__':unittest.main()
