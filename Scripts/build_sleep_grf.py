#!/usr/bin/env python3
"""Build the external GRF core and its author-provided local-linear tests.

The GPL-licensed upstream source, object files and binaries stay in temporary
research directories, outside the app and repository. No R install is needed.
"""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import subprocess


def build(source, output):
    source, output = source.resolve(), output.resolve()
    root = Path(__file__).resolve().parents[1]
    if source.is_relative_to(root) or output.is_relative_to(root):
        raise ValueError("Keep third-party source and compiled research dependencies outside the repository")
    output.mkdir(parents=True, exist_ok=True)
    core = source / "core"
    sources = sorted((core / "src").rglob("*.cpp"))
    assert len(sources) > 40 and (core / "third_party/Eigen/Core").exists()
    includes = ["-I" + str(core / p) for p in ["src", "third_party", "test"]]
    flags = ["-std=c++17", "-O2", "-pthread"]
    headers = sorted((core / "src").rglob("*.h"))
    revision = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    header_digest = hashlib.sha256(b"".join(p.read_bytes() for p in headers)).hexdigest()
    def compile_one(path):
        name = str(path.relative_to(core)).replace("/", "_")
        obj = output / (name + ".o")
        digest = hashlib.sha256(path.read_bytes() + header_digest.encode() + revision.encode() + " ".join(flags).encode()).hexdigest()
        stamp = obj.with_suffix(".sha256")
        if not obj.exists() or not stamp.exists() or stamp.read_text() != digest:
            subprocess.run(["xcrun", "clang++", *flags, *includes, "-c", str(path), "-o", str(obj)], check=True)
            stamp.write_text(digest)
        return obj
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        objects = list(pool.map(compile_one, sources))
    archive = output / "libgrf.a"
    subprocess.run(["ar", "rcs", str(archive), *map(str, objects)], check=True)
    bridge = root / "Scripts/SleepReplay/GRFReplay.cpp"
    subprocess.run(["xcrun", "clang++", *flags, *includes, str(bridge), str(archive), "-o", str(output / "replay")], check=True)
    test_sources = [core / p for p in ["test/setup.cpp", "test/utilities/ForestTestUtilities.cpp", "test/forest/LocalLinearForestTest.cpp"]]
    subprocess.run(["xcrun", "clang++", *flags, *includes, *map(str, test_sources), str(archive), "-o", str(output / "upstream-local-tests")], check=True)
    subprocess.run([str(output / "upstream-local-tests")], cwd=core, check=True)
    report = dict(passed=True, upstreamRevision=revision, upstreamLicense="GPL-3.0-or-later; research dependency only",
        compilerVersion=subprocess.check_output(["xcrun", "clang++", "--version"], text=True).splitlines()[0],
        sourceFiles=len(sources), headerSHA256=header_digest, bridgeSHA256=hashlib.sha256(bridge.read_bytes()).hexdigest(),
        binarySHA256=hashlib.sha256((output / "replay").read_bytes()).hexdigest(), authorLocalLinearTestsPassed=True)
    (output / "build-check.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(build(args.source, args.output), indent=2))
