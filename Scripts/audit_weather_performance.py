#!/usr/bin/env python3
"""Run the native weather/Today audit on an explicitly selected iOS simulator."""

import argparse
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time


def frame_benchmarks(simulator, derived_data, output):
    """Measure real list rendering without XCTest's main-thread AX snapshots."""
    app = Path(derived_data).resolve() / "Build/Products/Debug-iphonesimulator/LittleWindows.app"
    if not app.is_dir():
        raise RuntimeError(f"Build the Debug simulator app first: {app}")
    subprocess.run(["xcrun", "simctl", "install", simulator, str(app)], check=True)
    reports = []
    failures = []
    for repetition in range(3):
        for scenario in ("reference", "today", "weather"):
            environment = dict(os.environ)
            for key, value in {
                "LITTLE_WINDOWS_UI_TESTING": "1", "LITTLE_WINDOWS_WEATHER_PREVIEW": "1",
                "LITTLE_WINDOWS_INTERACTION_AUDIT": "1", "LITTLE_WINDOWS_SCROLL_BENCHMARK": scenario,
                "LITTLE_WINDOWS_INTERACTION_REFERENCE": "3" if scenario == "reference" else "0",
                "LITTLE_WINDOWS_START_URL": "littlewindows://weather" if scenario == "weather" else
                    "littlewindows://profile/00000000-0000-0000-0000-000000000101/today",
            }.items():
                environment[f"SIMCTL_CHILD_{key}"] = value
            log_path = output / f"frames-{scenario}-{repetition}.log"
            with log_path.open("w") as log:
                process = subprocess.Popen([
                    "xcrun", "simctl", "launch", "--terminate-running-process", "--console-pty",
                    simulator, "com.debidia.LittleWindows", "--little-windows-ui-testing", "--weather-preview",
                ], env=environment, stdout=log, stderr=subprocess.STDOUT)
                try:
                    deadline = time.monotonic() + 30
                    report = None
                    while time.monotonic() < deadline:
                        match = re.search(r"SCROLL-BENCHMARK (\{[^\r\n]+\})", log_path.read_text(errors="replace"))
                        if match:
                            report = json.loads(match[1]); break
                        if process.poll() is not None:
                            break
                        time.sleep(0.05)
                    if report is None:
                        raise RuntimeError(f"{scenario}: no completed frame report; see {log_path}")
                finally:
                    subprocess.run(["xcrun", "simctl", "terminate", simulator, "com.debidia.LittleWindows"],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.terminate(); process.wait(timeout=5)
            reports.append(report)
            (output / "frame-reports.json").write_text(json.dumps(reports, indent=2))
            if report.get("error") or report.get("scenario") != scenario or len(report.get("samples", [])) != 4:
                raise RuntimeError(f"{scenario}: incomplete benchmark: {report}")
            if scenario == "today" and not report["counts"].get("today.layout.full"):
                raise RuntimeError("Prepare the neutral Full-layout performance fixture with the complete audit first.")
            for sample in report["samples"]:
                maximum = sample["maxGapMS"]
                ratio = sample["lateMS"] / max(0.001, sample["duration"])
                print(f"FRAME AUDIT {scenario} cold {repetition}: frames={sample['frames']} "
                      f"max-gap={maximum:.2f}ms late={ratio:.2f}ms/s", flush=True)
                if sample["frames"] <= 5 or sample["duration"] < 0.15 or not math.isfinite(maximum + ratio):
                    raise RuntimeError(f"{scenario}: invalid or missing frame samples")
                if maximum > 50 or ratio > 10:
                    failures.append(f"{scenario} cold {repetition}: {maximum:.2f}ms gap, {ratio:.2f}ms/s late")
    if failures:
        raise RuntimeError(f"Frame budgets exceeded: {'; '.join(failures)}. See {output / 'frame-reports.json'}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("simulator", help="UDID from xcrun simctl list devices available")
    parser.add_argument("--derived-data", default="/tmp/LittleWindowsWeatherPerformanceBuild")
    parser.add_argument("--repeat", type=int, choices=range(1, 6), default=1)
    parser.add_argument("--frames-only", action="store_true", help="Use the already built app and prepared neutral Full-layout performance fixture")
    parser.add_argument("--include-frames", action="store_true", help="Also investigate cold-scroll rendering; this diagnostic currently exceeds its budgets")
    args = parser.parse_args()
    inventory = json.loads(subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "--json"], text=True))
    matches = [device for runtime, devices in inventory["devices"].items()
               if ".iOS-" in runtime for device in devices
               if device["udid"] == args.simulator and device.get("isAvailable")]
    if len(matches) != 1:
        parser.error("Select an available iOS simulator UDID; physical devices are not supported.")

    root = Path(__file__).resolve().parent.parent
    output = Path(tempfile.mkdtemp(prefix="little-windows-weather-audit-"))
    selections = [
        "LittleWindowsTests/CareTrackingPreferenceTests",
        "LittleWindowsTests/WeatherForecastTests",
        "LittleWindowsTests/WatchCompanionTests",
        "LittleWindowsTests/SleepConditionsTests",
        "LittleWindowsUITests/WeatherDashboardUITests",
        "LittleWindowsUITests/UserVisibleFlowUITests/testWeatherHeaderIsCompactAndOffersLocationOrCity",
        "LittleWindowsUITests/UserVisibleFlowUITests/testWeatherZIPSearchDisplaysAndSavesCityName",
        "LittleWindowsUITests/UserVisibleFlowUITests/testTodayEssentialsUsesLargeButtonsAndKeepsConfigurationInMenu",
        "LittleWindowsUITests/UserVisibleFlowUITests/testProductionScaleEssentialsLayoutSwitchesLoggingAndScrollingStayResponsive",
        "LittleWindowsUITests/UserVisibleFlowUITests/testEssentialsUseProfileAppropriateChoicesAndLoggingRoutes",
        "LittleWindowsUITests/UserVisibleFlowUITests/testTodayHomeSummaryHandsOffToHomeAndRetainsModeForSession",
    ]
    command = [
        "xcodebuild", "test", "-project", "LittleWindows.xcodeproj", "-scheme", "LittleWindows",
        "-destination", f"platform=iOS Simulator,id={args.simulator}",
        "-derivedDataPath", args.derived_data, "-resultBundlePath", str(output / "Audit.xcresult"),
        "CODE_SIGNING_ALLOWED=NO", "-parallel-testing-enabled", "NO",
        "-test-timeouts-enabled", "YES", "-maximum-test-execution-time-allowance", "300",
    ] + [f"-only-testing:{selection}" for selection in selections]
    if args.repeat > 1:
        command += ["-test-iterations", str(args.repeat)]
    print(f"Simulator: {matches[0]['name']}\nResults: {output}", flush=True)
    if args.frames_only:
        try:
            frame_benchmarks(args.simulator, args.derived_data, output)
            return 0
        except (RuntimeError, subprocess.SubprocessError) as error:
            print(f"PERFORMANCE AUDIT FAILED: {error}", flush=True)
            return 1
    with (output / "xcodebuild.log").open("w") as log:
        process = subprocess.Popen(command, cwd=root, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True, bufsize=1)
        for line in process.stdout:
            log.write(line)
            if any(token in line for token in ("INTERACTION AUDIT", "SCROLL AUDIT", "error:", "Test Suite", "** TEST")):
                print(line, end="", flush=True)
        status = process.wait()
    print(f"Full log and XCTest attachments: {output}", flush=True)
    if status == 0 and args.include_frames:
        try:
            frame_benchmarks(args.simulator, args.derived_data, output)
        except (RuntimeError, subprocess.SubprocessError) as error:
            print(f"PERFORMANCE AUDIT FAILED: {error}", flush=True)
            return 1
    elif status == 0:
        print("Interaction audit passed. Cold-scroll rendering remains a separate opt-in diagnostic (--include-frames).", flush=True)
    return status


if __name__ == "__main__":
    sys.exit(main())
