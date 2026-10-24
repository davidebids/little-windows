#!/usr/bin/env python3
"""Replay an external CSV through the app's Swift prediction engine, without importing it.

Usage: python3 Scripts/replay_sleep_predictions.py INPUT.csv --birth-date YYYY-MM-DD
       --time-zone America/Los_Angeles --output /tmp/sleep-replay.json
Raw records, birth dates, and per-event results stay outside the repository.
"""
import argparse
import csv
import datetime as dt
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
from zoneinfo import ZoneInfo


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--birth-date", required=True)
    parser.add_argument("--time-zone", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--engine", type=Path)
    parser.add_argument("--uncombined", action="store_true", help="Replay the unchanged v6 baseline instead of the prepared production combination")
    parser.add_argument("--ios-input", type=Path, help="Write external parity-test input outside the repository")
    parser.add_argument("--limit", type=int, help="Chronological prefix for development; omit for final evaluation")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root):
        parser.error("Keep personal replay results outside the repository")
    tz = ZoneInfo(args.time_zone)
    def date(value):
        return dt.datetime.strptime(value, "%Y-%m-%d %H:%M").replace(tzinfo=tz)
    rows = list(csv.DictReader(args.input.open(encoding="utf-8-sig")))
    sleeps, invalid = [], 0
    care = []
    for row in rows:
        if row["Type"] == "Feed":
            start = date(row["Start"])
            end = date(row["End"]) if row["End"] else start
            care.append(dict(start=start.timestamp(), end=end.timestamp(), nursing=row["Start Location"] == "Breast"))
        if row["Type"] != "Sleep":
            continue
        try:
            start, end = date(row["Start"]), date(row["End"])
            if end <= start:
                raise ValueError("Nonpositive duration")
        except ValueError:
            invalid += 1
            continue
        sleeps.append(dict(start=start, end=end))
    sleeps.sort(key=lambda s: s["start"])
    # Match the existing legacy importer. CSV contains no explicit nap/night field.
    for i, s in enumerate(sleeps):
        s["night"] = s["start"].hour >= 19 or s["start"].hour < 6 or s["end"].date() > s["start"].date()
        if not s["night"] and s["start"].hour < 9 and i:
            prev = sleeps[i - 1]
            s["night"] = prev["night"] and (s["start"] - prev["end"]).total_seconds() <= 90 * 60
    total = len(sleeps)
    if args.limit:
        sleeps = sleeps[:args.limit]
    payload = dict(
        birth=dt.datetime.strptime(args.birth_date, "%Y-%m-%d").replace(tzinfo=tz).timestamp(),
        zone=args.time_zone,
        totalSleeps=total,
        care=care,
        sleeps=[dict(start=s["start"].timestamp(), end=s["end"].timestamp(), night=s["night"]) for s in sleeps],
    )
    engine = (args.engine or root / "LittleWindows/Services/SleepPredictionEngine.swift").read_text()
    # Exclude only the UserDefaults persistence facade; retain the prediction engine verbatim.
    compiled_engine = engine[:engine.index("enum ActiveSleepPlanService {")] + engine[engine.index("enum SleepPredictionEngine {"):]
    tuning = (root / "LittleWindows/Services/PredictionTuningService.swift").read_text()
    bias = tuning[tuning.index("    static func conservativeBiasCorrection("):tuning.index("    private static func latestOpenRecord(")]
    support = root / "Scripts/SleepReplay"
    with tempfile.TemporaryDirectory(prefix="lw-sleep-replay-") as temp:
        temp = Path(temp)
        (temp / "Engine.swift").write_text(compiled_engine)
        (temp / "Tuning.swift").write_text("import Foundation\nenum PredictionTuningService {\n" + bias + "}\n")
        (temp / "input.json").write_text(json.dumps(payload))
        modern = "static func predictUncombined(" in engine
        names = ["PortableSleepFeatures.swift", "PortableSleepForest.swift", "PersonalizedSleepLearning.swift"]
        if modern:
            names += ["ReferenceSleepForest.swift", "PortableSleepCalibration.swift", "PortableSleepSpecialists.swift",
                "PortableSleepBaseline.swift", "PersonalizedSleepSession.swift", "PortableSleepPlanning.swift", "SleepLearningCoordinator.swift"]
        sources = [root / "LittleWindows/Services" / name for name in names]
        flags = (["-D", "UNCOMBINED_SLEEP_REPLAY"] if args.uncombined else []) if modern else ["-D", "LEGACY_SLEEP_REPLAY"]
        source_hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in
            [*sources, support / "Support.swift", support / "main.swift", root / "LittleWindows/Services/PredictionTuningService.swift"]}
        subprocess.run(["xcrun", "swiftc", "-O", *flags, "-module-cache-path", str(temp / "cache"), str(support / "Support.swift"), *map(str, sources), str(temp / "Engine.swift"), str(temp / "Tuning.swift"), str(support / "main.swift"), "-o", str(temp / "replay")], check=True)
        subprocess.run([str(temp / "replay"), str(temp / "input.json"), str(args.output)], check=True)
    result = json.loads(args.output.read_text())
    if args.ios_input:
        if args.ios_input.resolve().is_relative_to(root):
            parser.error("Keep personal parity-test input outside the repository")
        args.ios_input.write_text(json.dumps(dict(payload, expected=result["events"])))
    result["audit"] = dict(sourceRows=len(rows), sleepRows=total + invalid, invalidSleepRows=invalid,
                           sourceSHA256=hashlib.sha256(args.input.read_bytes()).hexdigest(),
                           engineSHA256=hashlib.sha256(engine.encode()).hexdigest(),
                           sourceFilesSHA256=source_hashes,
                           preparedHistory=modern and not args.uncombined,
                           careExposure="completed",
                           method="Predict once at each completed sleep end; reveal next sleep only after scoring; chronological 60/20/20 split")
    args.output.write_text(json.dumps(result, indent=2))
    print(json.dumps({k: v for k, v in result.items() if k != "events"}, indent=2))


if __name__ == "__main__":
    main()
