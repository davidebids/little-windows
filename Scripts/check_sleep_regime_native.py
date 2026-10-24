#!/usr/bin/env python3
"""Verify native specialist fitting against synthetic causal Python fits."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

import numpy as np
from research_sleep_predictions import PortableForest
from research_sleep_regimes import run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    n = 150
    clock = np.resize([120., 480., 900.], n) / 1440 * 2 * np.pi
    data = dict(X=np.column_stack([np.arange(n) % 13, np.sin(clock), np.cos(clock), np.resize([1, 1, 0], n)]),
        y=np.arange(n, dtype=float) % 17 * 6, wakes=np.arange(n, dtype=float) * 3600,
        available=np.arange(n, dtype=float) * 3600 + 600,
        names=["identifier", "clockSin1", "clockCos1", "lastNight"])
    data["available"][0] = data["wakes"][-1] + 86400
    fallback = np.full(n, 120.)
    expected, counts = run(data, fallback, "wakePhase", model_factory=lambda: PortableForest(80, 5))
    sources = [root / "LittleWindows/Services/PortableSleepForest.swift", root / "Scripts/SleepReplay/RegimeReplay.swift"]
    with tempfile.TemporaryDirectory(prefix="lw-synthetic-specialists-") as folder:
        folder = Path(folder)
        subprocess.run(["xcrun", "swiftc", "-O", "-parse-as-library", "-module-cache-path", str(folder / "cache"),
            *map(str, sources), "-o", str(folder / "replay")], check=True)
        from research_sleep_regimes import regimes
        payload = dict(x=data["X"].tolist(), y=data["y"].tolist(), wakes=data["wakes"].tolist(),
            available=data["available"].tolist(), groups=regimes(data, "wakePhase").tolist(),
            fallback=fallback.tolist(), lookbackDays=60, refitEvery=24)
        def native(values):
            (folder / "input.json").write_text(json.dumps(values))
            subprocess.run([str(folder / "replay"), str(folder / "input.json"), str(folder / "output.json")], check=True)
            return json.loads((folder / "output.json").read_text())
        full = native(payload)
        np.testing.assert_allclose(full["predictions"], expected, rtol=0, atol=1e-6)
        np.testing.assert_array_equal(full["trainingCounts"], counts)
        changed = dict(payload, y=payload["y"].copy())
        changed["y"][0] = 1e8
        np.testing.assert_array_equal(native(changed)["predictions"], full["predictions"])
        prefix = {k: v[:135] if isinstance(v, list) else v for k, v in payload.items()}
        np.testing.assert_array_equal(native(prefix)["predictions"], full["predictions"][:135])
    result = dict(passed=True, syntheticForecasts=n, syntheticRefits=int(np.sum(counts > 0)),
        prefixForecasts=135, unavailableLabelInvariant=True,
        maximumPredictionDifference=float(np.max(np.abs(np.array(full["predictions"]) - expected))),
        sourceFilesSHA256={p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sources})
    args.output.write_text(json.dumps(result, indent=2))
    print(json.dumps(result))


if __name__ == "__main__":
    main()
