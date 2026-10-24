import sys
from pathlib import Path
import unittest
import csv
import datetime as dt
import hashlib
import json
import subprocess
import tempfile
import numpy as np

sys.path.insert(0, str(Path(__file__).parents[1]))
from research_sleep_care_values import nursing_segment, care_values


class CareValueFeatureTests(unittest.TestCase):
    def test_duration_grammar_and_two_sided_values(self):
        self.assertEqual(nursing_segment("00:05L"), (5, "L"))
        self.assertEqual(nursing_segment("01:02R"), (62, "R"))
        for invalid in ["00:00L", "00:99R", "unknown", ""]:
            self.assertIsNone(nursing_segment(invalid))
        record = dict(Type="Feed", startEpoch=0, endEpoch=720,
                      **{"Start Condition": "00:05L", "End Condition": "00:07R"})
        x, names = care_values([record], [1000])
        self.assertEqual(x[0, names.index("nursingLastMinutes")], 12)
        self.assertAlmostEqual(x[0, names.index("nursingLastLeftFraction")], 5 / 12)
        self.assertEqual(x[0, names.index("nursingLastSegments")], 2)

    def test_future_records_and_later_queries_do_not_change_prefix(self):
        past = dict(Type="Feed", startEpoch=0, endEpoch=60,
                    **{"Start Condition": "00:05L", "End Condition": ""})
        future = dict(Type="Feed", startEpoch=900, endEpoch=2000,
                      **{"Start Condition": "01:00R", "End Condition": ""})
        full, _ = care_values([past, future], [1000, 3000])
        prefix, _ = care_values([past], [1000])
        np.testing.assert_allclose(full[:1], prefix, rtol=0, atol=0, equal_nan=True)

    def test_diaper_details_expire_from_rolling_counts(self):
        record = dict(Type="Diaper", startEpoch=0, endEpoch=0, **{"End Condition": "Both Poo:Loose"})
        x, names = care_values([record], [60, 25 * 3600])
        self.assertEqual(x[0, names.index("diaperWetCount12h")], 1)
        self.assertEqual(x[0, names.index("diaperDirtyCount12h")], 1)
        self.assertEqual(x[0, names.index("lastDiaperLooseFlag")], 1)
        self.assertEqual(x[1, names.index("diaperLooseCount24h")], 0)

    def test_complete_command_handles_native_model_results_and_empty_care(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            source, cache, baseline, output = [folder / name for name in ["source.csv", "features.npz", "baseline.json", "result.json"]]
            origin = dt.datetime(2026, 1, 1, tzinfo=dt.timezone.utc).timestamp()
            with source.open("w") as stream:
                writer = csv.DictWriter(stream, fieldnames=["Type", "Start", "End", "Start Condition", "End Condition"])
                writer.writeheader()
                for i in range(46):
                    stamp = lambda value: dt.datetime.fromtimestamp(value, dt.timezone.utc).strftime("%Y-%m-%d %H:%M")
                    writer.writerow(dict(Type="Sleep", Start=stamp(origin + i * 7200), End=stamp(origin + i * 7200 + 3600)))
            wakes = origin + np.arange(45) * 7200 + 3600
            phase = np.mod(wakes, 86400) * 2 * np.pi / 86400
            np.savez_compressed(cache, X=np.column_stack([np.sin(phase), np.cos(phase), np.full(45, 60.)]),
                names=["clockSin1", "clockCos1", "lastDuration"], y=np.full(45, 60.),
                wakes=wakes, available=wakes + 3600, indices=np.arange(45))
            baseline.write_text(json.dumps(dict(audit=dict(sourceSHA256=hashlib.sha256(source.read_bytes()).hexdigest()),
                events=[dict(index=i, actual=float(w + 3600), prediction=float(w + 3600), wakeMinutes=60.) for i, w in enumerate(wakes)])))
            result = subprocess.run([sys.executable, str(Path(__file__).parents[1] / "research_sleep_care_values.py"),
                "--source", str(source), "--features", str(cache), "--baseline", str(baseline),
                "--time-zone", "UTC", "--output", str(output)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            saved = json.loads(output.read_text())
            self.assertEqual(len(saved["events"]), 9)
            for name, model in saved["models"].items():
                if name.startswith(("control_", "values_")):
                    self.assertEqual(model["fits"], 1)
            for rows in saved["events"].values():
                self.assertEqual(len(rows), 45)
                np.testing.assert_allclose([row["prediction"] for row in rows], 60, rtol=0, atol=1e-6)
