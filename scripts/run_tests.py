#!/usr/bin/env python3
"""Runs what CMake built (docs/development.md): the API check, every test in
test/ and every sample in samples/, off screen (GOOSE_GFX_HEADLESS).

A test runs in test/, so the Slang files it names are found there, and
passes when it exits with 0 and prints test/expected/<name>.out. One with an
expected/<name>.aborts must exit otherwise, and print every line of
expected/<name>.stderr somewhere in its stderr. Each test that passes runs
again with GOOSE_NGFX_SYNC=full, a full barrier around every pass and
dispatch, which must not change what it prints: if it does, a barrier is
missing.

A sample runs in samples/, where its screenshots land, with the arguments in
samples/data/<name>.args, and passes when it prints
samples/expected/<name>.out.

A run that finds no GPU device is a skip, not a failure.

    python scripts/run_tests.py [--build DIR] [name ...]
"""

import argparse
import os
import shlex
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
NO_DEVICE = "no NoGraphicsAPI device"
EXE = ".exe" if os.name == "nt" else ""

sys.path.insert(0, str(REPO / "scripts"))
import api_check  # noqa: E402


def text(path):
    return path.read_text(encoding="utf-8") if path.exists() else None


def lines(s):
    return s.replace("\r\n", "\n")


def run(exe, args, cwd, sync_full=False):
    env = dict(os.environ, GOOSE_GFX_HEADLESS="1")
    if sync_full:
        env["GOOSE_NGFX_SYNC"] = "full"
    else:
        env.pop("GOOSE_NGFX_SYNC", None)
    try:
        r = subprocess.run([str(exe)] + args, cwd=cwd, env=env, capture_output=True,
                           timeout=300, encoding="utf-8", errors="replace")
    except subprocess.TimeoutExpired:
        return None, "", "timed out after 300 s"
    return r.returncode, lines(r.stdout), lines(r.stderr)


class Results:
    def __init__(self):
        self.passed, self.failed, self.skipped = [], [], []

    def report(self, label, problem, skip=False):
        if skip:
            self.skipped.append(label)
            print(f"skip {label}: {problem}")
        elif problem:
            self.failed.append(label)
            print(f"FAIL {label}: {problem}")
        else:
            self.passed.append(label)
            print(f"ok   {label}")


def judge(code, out, err, expected_out, aborts, expected_err):
    """What is wrong with a run, or None."""
    if code is None:
        return err
    if aborts:
        if code == 0:
            return "exited with 0, expected an abort"
        missing = [l for l in (expected_err or "").splitlines() if l and l not in err]
        if missing:
            return f"stderr lacks {missing!r}; it was:\n{err}"
        if expected_out is not None and out != lines(expected_out):
            return f"stdout differs; it was:\n{out}"
        return None
    if code != 0:
        return f"exited with {code}; stderr:\n{err}"
    if expected_out is None:
        return f"no expected output; it printed:\n{out}"
    if out != lines(expected_out):
        return f"stdout differs from the expected; it was:\n{out}"
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--build", default=str(REPO / "build"), help="the CMake build directory")
    ap.add_argument("names", nargs="*", help="only these tests and samples")
    args = ap.parse_args()
    bindir = Path(args.build) / "bin"
    res = Results()

    if not args.names:
        problems = api_check.check()
        res.report("api check", "\n".join(problems) if problems else None)

    def wanted(name):
        return not args.names or name in args.names

    for src in sorted((REPO / "test").glob("*.goose")):
        name = src.stem
        if not wanted(name):
            continue
        exe = bindir / (name + EXE)
        if not exe.exists():
            res.report(name, f"{exe} is not built")
            continue
        exp = REPO / "test" / "expected"
        expected_out = text(exp / f"{name}.out")
        aborts = (exp / f"{name}.aborts").exists()
        expected_err = text(exp / f"{name}.stderr")
        for sync_full in (False, True):
            if sync_full and aborts:
                break
            label = name + (" sync=full" if sync_full else "")
            code, out, err = run(exe, [], REPO / "test", sync_full)
            if NO_DEVICE in err:
                res.report(label, NO_DEVICE, skip=True)
                break
            problem = judge(code, out, err, expected_out, aborts, expected_err)
            res.report(label, problem)
            if problem:
                break

    workdir = REPO / "samples"
    for src in sorted((REPO / "samples").glob("*.goose")):
        name = src.stem
        if not wanted(name):
            continue
        exe = bindir / (name + EXE)
        if not exe.exists():
            res.report(f"sample {name}", f"{exe} is not built")
            continue
        argtext = text(REPO / "samples" / "data" / f"{name}.args") or ""
        argv = shlex.split(argtext)
        code, out, err = run(exe, argv, workdir)
        if NO_DEVICE in err:
            res.report(f"sample {name}", NO_DEVICE, skip=True)
            continue
        expected_out = text(REPO / "samples" / "expected" / f"{name}.out")
        res.report(f"sample {name}", judge(code, out, err, expected_out, False, None))

    print(f"\n{len(res.passed)} passed, {len(res.failed)} failed, {len(res.skipped)} skipped")
    return 1 if res.failed else 0


if __name__ == "__main__":
    sys.exit(main())
