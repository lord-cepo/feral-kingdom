"""Run opt-in Godot regressions, isolating saves and rejecting script errors.

Usage: python tools/run_tests.py [scene_name ...] [--godot PATH]
With no names, runs every tests/*_test.tscn scene. Invoke only after an explicit
user request ending TEST, as required by AGENTS.md. This is not an editor hook.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
ERROR = re.compile(r"(?m)^(?:SCRIPT ERROR:|ERROR:|FATAL:)|\b[1-9]\d* failures\b")


def main():
    """Run isolated scenes, retain complete evidence, and fail on timeout, nonzero exit or logged engine/script errors."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scenes", nargs="*")
    parser.add_argument("--godot", type=Path, default=ROOT / ".tools/godot/Godot_v4.5.1-stable_win64_console.exe")
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args()
    scenes = [ROOT / "tests" / (name if name.endswith(".tscn") else name + ".tscn") for name in args.scenes]
    if not scenes:
        scenes = sorted((ROOT / "tests").glob("*_test.tscn"))
    if not args.godot.is_file() or any(not scene.is_file() for scene in scenes):
        parser.error("The Godot executable and every requested scene must exist.")
    output = ROOT / ".tools/test-runs" / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    output.mkdir(parents=True)
    results = []
    for scene in scenes:
        folder = output / scene.stem
        folder.mkdir()
        environment = dict(os.environ)
        for name in ("APPDATA", "LOCALAPPDATA"):
            environment[name] = str(folder / name.lower())
            Path(environment[name]).mkdir()
        command = [str(args.godot.resolve()), "--headless", "--path", str(ROOT),
                   "res://" + scene.relative_to(ROOT).as_posix()]
        start = time.monotonic()
        timed_out = False
        with (folder / "output.log").open("w", encoding="utf-8") as log:
            try:
                completed = subprocess.run(command, cwd=ROOT, env=environment, stdout=log,
                                           stderr=subprocess.STDOUT, timeout=args.timeout, check=False)
                code = completed.returncode
            except subprocess.TimeoutExpired:
                code = None
                timed_out = True
        contents = (folder / "output.log").read_text(encoding="utf-8", errors="replace")
        passed = code == 0 and not timed_out and ERROR.search(contents) is None
        counts = re.findall(r"(\d+) checks", contents)
        result = {"scene": scene.stem, "passed": passed, "exit_code": code,
                  "timeout": timed_out, "seconds": round(time.monotonic() - start, 2),
                  "checks": int(counts[-1]) if counts else None, "log": str(folder / "output.log")}
        results.append(result)
        print(f"{'PASS' if passed else 'FAIL'} {scene.stem} ({result['seconds']}s)", flush=True)
        if not passed:
            print("\n".join(contents.splitlines()[-35:]), flush=True)
        (output / "results.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    failed = sum(not result["passed"] for result in results)
    print(f"{len(results) - failed}/{len(results)} suites passed; {failed} failed", flush=True)
    print(f"Report: {output / 'results.json'}", flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
