import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).parents[1]))
from research_sleep_cold_handoff import handoff


class ColdHandoffTests(unittest.TestCase):
    def test_resolved_count_gate_preserves_prefix_and_all_forecasts(self):
        i=np.arange(70);w=i*10800.;d=dict(wakes=w,available=w+3600);d['available'][5]=1e20
        cold=i.astype(float)+1;mature=i.astype(float)+100;p,count=handoff(d,cold,mature)
        self.assertEqual(len(p),70);self.assertEqual(count[40],39);self.assertEqual(count[41],40)
        np.testing.assert_array_equal(p[count<40],cold[count<40]);np.testing.assert_array_equal(p[count>=40],mature[count>=40])
        short,counts=handoff({k:v[:55] for k,v in d.items()},cold[:55],mature[:55])
        np.testing.assert_array_equal(p[:55],short);np.testing.assert_array_equal(count[:55],counts)
