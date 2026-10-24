import sys
import csv
import tempfile
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).parents[1]))
from research_sleep_care_signatures import signature2,event_features,read_marks,replay


class CareSignatureTests(unittest.TestCase):
    def test_level_two_matches_known_example_shuffle_and_subdivision(self):
        first,second=signature2(np.array([[0,1],[-3,0]]))
        np.testing.assert_array_equal(first,[-3,1]);np.testing.assert_array_equal(second,[[4.5,0],[-3,.5]])
        rng=np.random.default_rng(42)
        for _ in range(20):
            delta=rng.normal(size=(12,9));a,b=signature2(delta)
            # Independent all-pairs integral: earlier/later segment products
            # plus each segment's straight-line half outer product.
            expected=delta.T@np.triu(np.ones((12,12)),1)@delta+.5*delta.T@delta
            np.testing.assert_allclose(b,expected,atol=1e-12)
            np.testing.assert_allclose(b+b.T,np.outer(a,a),atol=1e-12)
            c,d=signature2(np.repeat(delta/2,2,axis=0))
            np.testing.assert_allclose(a,c,atol=1e-12);np.testing.assert_allclose(b,d,atol=1e-12)

    def test_paths_distinguish_order_and_ignore_future_and_simultaneous_order(self):
        # Mark 1 is feed, mark 2 diaper; timing is equal across the two paths.
        events=np.array([[10,20,1],[30,40,2]],dtype=float);now=np.array([60.])
        swapped=events.copy();swapped[:,2]=[2,1]
        a=event_features(events,now);b=event_features(swapped,now)
        np.testing.assert_array_equal(a['counts'],b['counts']);self.assertFalse(np.array_equal(a['order'],b['order']))
        future=np.vstack([events,[0,100,0],[70,80,1]])
        c=event_features(future,now)
        for key in a:np.testing.assert_array_equal(a[key],c[key])
        same=np.array([[0,20,1],[10,20,2],[20,20,2]],dtype=float)
        a=event_features(same,now);b=event_features(same[::-1],now)
        for key in a:np.testing.assert_array_equal(a[key],b[key])
        self.assertEqual(a['counts'].shape,(1,27));self.assertEqual(a['timing'].shape,(1,51));self.assertEqual(a['order'].shape,(1,135))

    def test_reader_rejects_uncertain_timer_ends_and_keeps_instantaneous_records(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'events.csv'
            with p.open('w') as f:
                w=csv.DictWriter(f,fieldnames=['Type','Start','End']);w.writeheader()
                for kind in ['Sleep','Feed','Diaper','Other']:w.writerow(dict(Type=kind,Start='2025-01-01 10:00',End=''))
            events,skipped=read_marks(p,'UTC')
            self.assertEqual(skipped,2);self.assertEqual(len(events),2);np.testing.assert_array_equal(events[:,0],events[:,1])

    def test_heads_preserve_prefix_and_unavailable_label_isolation(self):
        i=np.arange(75);w=i*10800.;phase=i*.3;y=60+10*np.sin(i)
        d=dict(X=np.column_stack([np.sin(phase),np.cos(phase),60+np.cos(i)]),names=['clockSin1','clockCos1','lastDuration'],y=y,wakes=w,available=w+y*60)
        d['available'][:3]=1e20;blocks={k:np.column_stack([np.sin(i*.1),np.cos(i*.2)]) for k in ['counts','timing','order']};fallback=np.full(75,60.)
        full,diag=replay(d,blocks,fallback,fast_bins=False)
        prefix={k:(v if k=='names' else v[:60]) for k,v in d.items()};short,_=replay(prefix,{k:v[:60] for k,v in blocks.items()},fallback[:60],fast_bins=False)
        changed=dict(d,y=d['y'].copy());changed['y'][:3]=9999;alter,_=replay(changed,blocks,fallback,fast_bins=False)
        for name,v in full.items():np.testing.assert_array_equal(v[:60],short[name]);np.testing.assert_array_equal(v,alter[name])
        self.assertEqual(len(full),17);self.assertEqual(len(diag),12)
