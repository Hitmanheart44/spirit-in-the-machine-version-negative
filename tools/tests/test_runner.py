#!/usr/bin/env python3
"""Bounded existing-loop gate and its temporary fake-engine failure checks."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
ERROR = re.compile(r"(?:SCRIPT ERROR|ERROR|FATAL|Parse Error):", re.IGNORECASE)
SCENES = (
    ("promotion_return_test", "vn-01-", "VN01_SCRATCH", r"VN-01: 105 checks, 0 failures"),
    ("loop_contract_test", "vn-02-", "VN02_SCRATCH", r"VN-02: 70 checks, 0 failures"),
    ("session_reset_test", "vn-03-", "VN03_SCRATCH", r"VN-03: 83 checks, 0 failures"),
    ("dungeon_camera_test", "vn-05-", "VN05_SCRATCH", r"VN-05: 17 checks, 0 failures"),
)


def invoke(engine, arguments, prefix, marker, seconds):
    scratch = Path(tempfile.mkdtemp(prefix=prefix, dir="/tmp"))
    environment = os.environ.copy()
    for key in ("VN01_SCRATCH", "VN02_SCRATCH", "VN03_SCRATCH", "VN05_SCRATCH"):
        environment.pop(key, None)
    for key, directory in (("HOME", "home"), ("XDG_DATA_HOME", "data"),
                           ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
        target = scratch / directory
        target.mkdir()
        environment[key] = str(target)
    if marker:
        environment[marker] = str(scratch)
    log = scratch / "engine.log"
    print(f"LOG={log}", flush=True)
    try:
        with log.open("w") as output:
            result = subprocess.run([engine, *arguments], cwd=ROOT, env=environment,
                                    stdout=output, stderr=subprocess.STDOUT, timeout=seconds)
        status = result.returncode if result.returncode >= 0 else 128 - result.returncode
    except subprocess.TimeoutExpired:
        print(f"FAIL: engine timeout after {seconds:g}s; log retained: {log}", flush=True)
        status = 124
    except OSError as error:
        print(f"FAIL: engine could not start: {error}; log retained: {log}", flush=True)
        status = 127
    text = log.read_text(errors="replace")
    print(text, end="" if text.endswith("\n") else "\n", flush=True)
    return status, text


def gate():
    engine_name = os.environ.get("GODOT_BIN", "godot")
    engine = shutil.which(engine_name)
    if not engine:
        print(f"FAIL: engine executable unavailable: {engine_name}", flush=True)
        return 127
    engine = str(Path(engine).resolve())
    try:
        seconds = float(os.environ.get("GODOT_TIMEOUT_SECONDS", "45"))
        if not 0.1 <= seconds <= 300:
            raise ValueError
    except ValueError:
        print("FAIL: GODOT_TIMEOUT_SECONDS must be a number in 0.1..300", flush=True)
        return 2
    status, version = invoke(engine, ["--version"], "vn-02-version-", None, seconds)
    if status:
        return status
    if ERROR.search(version) or not re.match(r"^4\.7\.2(?:[.\s-]|$)", version.strip()):
        print("FAIL: Godot 4.7.2 is required; version probe failed", flush=True)
        return 1
    for scene, prefix, marker, verdict in SCENES:
        status, output = invoke(engine, ["--headless", "--path", str(ROOT),
                                        f"res://world/tests/{scene}.tscn"], prefix, marker, seconds)
        if status:
            print(f"FAIL: {scene} exited {status}", flush=True)
            return status
        if ERROR.search(output):
            print(f"FAIL: {scene} reported a script/runtime error", flush=True)
            return 1
        if not re.search(r"^" + verdict + r"$", output, re.MULTILINE):
            print(f"FAIL: {scene} completion verdict missing", flush=True)
            return 1
        print(f"PASS: {scene}", flush=True)
    print("VN-02 GATE: 4 scenes passed", flush=True)
    return 0


def self_test():
    """Run the real shell wrapper from another directory; never edit gameplay files."""
    sandbox = Path(tempfile.mkdtemp(prefix="vn-02-runner-checks-", dir="/tmp"))
    fake = sandbox / "fake godot"
    fake.write_text("#!" + sys.executable + "\n" + '''
import os, pathlib, sys, time
mode = os.environ["VN02_FAKE_MODE"]
if "--version" in sys.argv:
    print("4.6.stable" if mode == "wrong_version" else "4.7.2.stable.fake")
    sys.exit(0)
scene = sys.argv[-1]
scenes = {
    "promotion_return_test.tscn": ("VN01_SCRATCH", "/tmp/vn-01-", "VN-01: 105 checks, 0 failures"),
    "loop_contract_test.tscn": ("VN02_SCRATCH", "/tmp/vn-02-", "VN-02: 70 checks, 0 failures"),
    "session_reset_test.tscn": ("VN03_SCRATCH", "/tmp/vn-03-", "VN-03: 83 checks, 0 failures"),
    "dungeon_camera_test.tscn": ("VN05_SCRATCH", "/tmp/vn-05-", "VN-05: 17 checks, 0 failures"),
}
marker, prefix, verdict = scenes[scene.rsplit("/", 1)[-1]]
promotion = marker == "VN01_SCRATCH"
third = marker == "VN03_SCRATCH"
fourth = marker == "VN05_SCRATCH"
root = pathlib.Path(os.environ[marker])
assert str(root).startswith(prefix)
assert all(key not in os.environ for key in ("VN01_SCRATCH", "VN02_SCRATCH", "VN03_SCRATCH", "VN05_SCRATCH") if key != marker)
assert sys.argv[1:3] == ["--headless", "--path"]
assert pathlib.Path(sys.argv[3]) == pathlib.Path(os.environ["VN02_EXPECT_ROOT"])
for key, suffix in [("HOME", "home"), ("XDG_DATA_HOME", "data"),
                    ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")]:
    target = pathlib.Path(os.environ[key])
    assert target == root / suffix and target.is_dir() and not list(target.iterdir())
print("FAKE_ISOLATED=" + str(root), flush=True)
if mode == "timeout" or (mode == "timeout_third" and third) or (mode == "timeout_fourth" and fourth):
    time.sleep(5)
if mode == "early" or (mode == "early_second" and not promotion) or (mode == "early_third" and third) or (mode == "early_fourth" and fourth):
    sys.exit(0)
print(verdict)
if mode == "nonzero" or (mode == "nonzero_third" and third) or (mode == "nonzero_fourth" and fourth):
    sys.exit(7)
if mode == "runtime" or (mode == "runtime_third" and third) or (mode == "runtime_fourth" and fourth):
    print("ERROR: deliberate runtime error")
if mode == "script":
    print("SCRIPT ERROR: deliberate script error")
if mode == "parse":
    print("Parse Error: deliberate parse error")
''')
    fake.chmod(0o700)
    cases = [("success", 0), ("relative", 0), ("missing", 127), ("nonzero", 7), ("timeout", 124),
             ("runtime", 1), ("script", 1), ("parse", 1), ("early", 1),
             ("early_second", 1), ("early_third", 1), ("early_fourth", 1), ("runtime_third", 1),
             ("runtime_fourth", 1), ("nonzero_third", 7), ("nonzero_fourth", 7),
             ("timeout_third", 124), ("timeout_fourth", 124), ("wrong_version", 1), ("shell_fragment", 127),
             ("invalid_timeout", 2)]
    failures = 0
    for mode, expected in cases:
        environment = os.environ.copy()
        environment.update(GODOT_BIN=str(fake), VN02_FAKE_MODE=mode, VN02_EXPECT_ROOT=str(ROOT),
                           GODOT_TIMEOUT_SECONDS="0.2" if mode in ("timeout", "timeout_third", "timeout_fourth") else "5")
        # Poison inherited markers: invoke must remove them and set only the relevant fresh one.
        environment.update(VN01_SCRATCH="/must/not/be/used", VN02_SCRATCH="/must/not/be/used",
                           VN03_SCRATCH="/must/not/be/used", VN05_SCRATCH="/must/not/be/used")
        if mode == "relative":
            environment["GODOT_BIN"] = "./fake godot"
        if mode == "missing":
            environment["GODOT_BIN"] = str(sandbox / "missing")
        if mode == "shell_fragment":
            environment["GODOT_BIN"] = str(fake) + " --headless"
        if mode == "invalid_timeout":
            environment["GODOT_TIMEOUT_SECONDS"] = "nan"
        result = subprocess.run(["sh", str(ROOT / "tools/test.sh")], cwd=sandbox,
                                env=environment, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=20)
        log = sandbox / (mode + ".log")
        log.write_text(result.stdout)
        ok = result.returncode == expected
        engine_logs = re.findall(r"^LOG=(.+)$", result.stdout, re.MULTILINE)
        ok = ok and all(Path(path).is_file() for path in engine_logs)
        if mode in ("success", "relative"):
            roots = re.findall(r"^FAKE_ISOLATED=(.+)$", result.stdout, re.MULTILINE)
            ok = ok and len(roots) == len(set(roots)) == 4
            ok = ok and "VN-02 GATE: 4 scenes passed" in result.stdout
        elif mode not in ("missing", "shell_fragment", "invalid_timeout"):
            ok = ok and bool(engine_logs) and "VN-02 GATE: 4 scenes passed" not in result.stdout
        if mode.endswith("_third"):
            ok = ok and len(engine_logs) == 4
            ok = ok and "PASS: promotion_return_test" in result.stdout and "PASS: loop_contract_test" in result.stdout
        if mode.endswith("_fourth"):
            ok = ok and len(engine_logs) == 5
            ok = ok and "PASS: session_reset_test" in result.stdout
        print(f"{'PASS' if ok else 'FAIL'} runner {mode}: exit {result.returncode}, expected {expected}; LOG={log}")
        failures += int(not ok)
    print(f"VN-02 RUNNER: {len(cases)} checks, {failures} failures")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        sys.exit(self_test())
    if sys.argv[1:]:
        print("Usage: sh tools/test.sh [--self-test]", file=sys.stderr)
        sys.exit(2)
    sys.exit(gate())
