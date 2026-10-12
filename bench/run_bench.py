"""Benchmarks ngfx against Goose's gfx, as task 001's subtask 03 plans.

    python bench/run_bench.py [options] [workload ...]

Workloads: cube, ui_todo, minecraft, minecraft_mine, doom, draws, uploads
(default: all). Each runs as ngfx, ngfx under GOOSE_NGFX_SYNC=full, and gfx,
alternating, --runs times, under each of --conditions: headless, vsync
(windowed), novsync (windowed, presenting without waiting for vsync).

The gfx side is Goose's own samples, copied from the Goose tree that GOOSE
was built from (or --goose-src), and bench/draws_gfx.goose and
bench/uploads_gfx.goose. Both sides get the same instrumentation, patched
into copies under build/bench/src/: the time each frame() is called and
returns, and the time from open() to the first frame. ngfx adds its GPU
timestamps (GOOSE_NGFX_BENCH=1) and the time ngfx::slang took. Each program
is built with goose build, never run in the compiler.

Per run, the frames after --warmup are measured. Raw per-frame numbers go to
build/bench/<time>/<run>.csv, one line per run to runs.csv beside them, and
a summary table to stdout: per configuration, the median over runs of each
run's median, 5th and 95th percentile, with the range of the run medians.
"""

import argparse
import csv
import datetime
import os
import platform
import re
import shutil
import statistics
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "build" / "bench"
EXE = ".exe" if os.name == "nt" else ""

# name: (ngfx source, gfx source, arguments, measured frames, variants)
# A source starting with "goose:" is in the Goose tree's samples/. A
# variant adds arguments and a suffix to the name.
WORKLOADS = {
    "cube": ("samples/cube.goose", "goose:27_gfx_cube.goose", [], 1000, [("", [])]),
    "ui_todo": ("samples/ui_todo.goose", "goose:29_ui_todo.goose", [], 1000, [("", [])]),
    "minecraft": ("samples/mini_minecraft.goose", "goose:30_mini_minecraft.goose", [], 1000,
                  [("", [])]),
    "minecraft_mine": ("samples/mini_minecraft.goose", "goose:30_mini_minecraft.goose", [], 600,
                       [("", [])]),
    "doom": ("samples/mini_doom.goose", "goose:31_mini_doom.goose",
             ["--wad", "data/freedoom1-e1m1.wad"], 1000, [("", [])]),
    "draws": ("bench/draws_ngfx.goose", "bench/draws_gfx.goose", [], 3000,
              [(f"_{n // 1000}k{'_indexed' if ix else ''}",
                ["--draws", str(n)] + (["--indexed"] if ix else []))
               for n in (1000, 10000, 50000) for ix in (False, True)]),
    "uploads": ("bench/uploads_ngfx.goose", "bench/uploads_gfx.goose", [], 3000,
                [(f"_k{k}", ["--updates", str(k)]) for k in (1, 4, 16)]),
}

PATCH = """
// Timing added by bench/run_bench.py: when each frame() is called and
// returns, on the monotonic clock in nanoseconds, printed at close.
struct BenchFrame { called: i64, returned: i64 }
var bench_frames: BenchFrame[>..];
var bench_opened: i64 = 0;
var bench_mine_on = false;

fn bench_on(name: const u8[:]) -> bool {
    var value: u8[>..] = [];
    return env(name, value) && value == "1";
}

// The flags open() is given, evaluated as it is called.
fn bench_open_flags() -> i32 {
    bench_opened = clock_ns();
    bench_mine_on = bench_on("GOOSE_BENCH_MINE");
    return MOD::WINDOW_RESIZABLE NO_VSYNC;
}

fn bench_frame() -> bool {
    let called = clock_ns();
    let open = MOD::frame();
    bench_frames.push(BenchFrame { called: called, returned: clock_ns() });
    return open;
}

fn bench_report() {
    print("bench opened ", bench_opened, " ended ", clock_ns());
    for f in bench_frames { print("bench frame ", f.called, " ", f.returned); }
}
"""

# Mini Minecraft with GOOSE_BENCH_MINE=1: a block mined every 10 frames,
# spread over the chunks, so rebuild frames are measured too.
MINE = """
fn bench_mine() {
    guard bench_mine_on && bench_frames.len % 10 == 0 else { return; }
    let k = bench_frames.len / 10;
    let x = (k * 37 + 5) % WIDTH;
    let z = (k * 53 + 11) % DEPTH;
    var y = HEIGHT - 1;
    while y > 0 && !solid(block_at(cell(x, y, z))) { y--; }
    if y > 0 { edit(cell(x, y, z), AIR); }
}
"""

CONDITIONS = ("headless", "vsync", "novsync")


def goose_tree(goose, given):
    if given:
        return Path(given).resolve()
    # The compiler is built in <tree>/build/, or <tree>/build/<config>/ on Windows.
    for parent in Path(goose).resolve().parents:
        if (parent / "samples").is_dir() and (parent / "src" / "blessed.txt").exists():
            return parent
    sys.exit("can't find the Goose tree GOOSE was built from: pass --goose-src")


def readme_pin():
    m = re.search(r"\| Goose \| `aardappel/goose` `([0-9a-f]+)`", (REPO / "README.md").read_text())
    return m.group(1) if m else None


def git(cwd, *args):
    r = subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True)
    return r.stdout.strip()


def patch(text, side, mine):
    """The program with the timing hooks in: each hook point must be there once."""
    mod = side
    points = [(f"{mod}::WINDOW_RESIZABLE)", "bench_open_flags())"),
              (f"while {mod}::frame() {{", "while bench_frame() {"),
              (f"\n    {mod}::close();", f"\n    bench_report();\n    {mod}::close();")]
    if mine:
        points.append(("\n        rebuild_dirty();\n", "\n        bench_mine();\n        rebuild_dirty();\n"))
    for old, new in points:
        if text.count(old) != 1:
            sys.exit(f"patch: expected one {old.strip()!r}, found {text.count(old)}")
        text = text.replace(old, new)
    no_vsync = (" | (if bench_on(\"GOOSE_BENCH_NO_VSYNC\") { gfx::NO_VSYNC } else { 0 })"
                if side == "gfx" else "")
    hooks = PATCH.replace("MOD", mod).replace(" NO_VSYNC", no_vsync) + (MINE if mine else "")
    at = text.index("\nfn main()")
    text = text[:at] + "\n" + hooks + text[at:]
    if side == "ngfx":
        text = text.replace('import ngfx from "../";', 'import ngfx from "../../../../";')
    return text


def prepare(goose, tree, names):
    """Patches and builds each program; returns {(side, name): executable}."""
    src = OUT / "src"
    bins = OUT / "bin"
    bins.mkdir(parents=True, exist_ok=True)
    data = {"ngfx": REPO / "samples" / "data", "gfx": tree / "samples" / "data"}
    for side in ("ngfx", "gfx"):
        d = src / side
        d.mkdir(parents=True, exist_ok=True)
        link = d / "data"
        if not link.exists():
            link.symlink_to(data[side], target_is_directory=True)
    exes = {}
    for name in names:
        ngfx_src, gfx_src, _, _, _ = WORKLOADS[name]
        for side, path in (("ngfx", ngfx_src), ("gfx", gfx_src)):
            source = tree / "samples" / path[6:] if path.startswith("goose:") else REPO / path
            target = src / side / (name + ".goose")
            target.write_text(patch(source.read_text(encoding="utf-8"), side,
                                    name == "minecraft_mine"), encoding="utf-8")
            exe = bins / f"{side}_{name}{EXE}"
            print(f"building {side} {name}", flush=True)
            r = subprocess.run([str(goose), "build", "-o", str(exe), target.name],
                               cwd=target.parent, capture_output=True, text=True)
            if r.returncode:
                sys.exit(f"goose build {target} failed:\n{r.stderr}")
            exes[(side, name)] = exe
    return exes


def percentile(xs, p):
    xs = sorted(xs)
    if not xs:
        return float("nan")
    k = (len(xs) - 1) * p / 100
    lo = int(k)
    hi = min(lo + 1, len(xs) - 1)
    return xs[lo] + (xs[hi] - xs[lo]) * (k - lo)


def parse(out, err, warmup, measured):
    """Per-frame series in milliseconds, and the run's scalars."""
    opened = ended = None
    frames = []
    for line in out.splitlines():
        p = line.split()
        if line.startswith("bench opened"):
            opened, ended = int(p[2]), int(p[4])
        elif line.startswith("bench frame"):
            frames.append((int(p[2]), int(p[3])))
    gpu = []
    slang = (0.0, 0)
    for line in err.splitlines():
        p = line.split()
        if line.startswith("ngfx_bench gpu"):
            gpu.append((float(p[2]), float(p[3]), float(p[4])))
        elif line.startswith("ngfx_bench slang"):
            slang = (float(p[2]), int(p[3]))
    if opened is None or len(frames) < warmup + measured:
        return None
    ms = 1e-6
    frames = frames[:warmup + measured]
    series = {"frame": [], "body": [], "in_frame": []}
    for i in range(warmup, len(frames)):
        called, returned = frames[i]
        end = frames[i + 1][0] if i + 1 < len(frames) else ended
        series["in_frame"].append((returned - called) * ms)
        series["body"].append((end - returned) * ms)
        if i + 1 < len(frames):
            series["frame"].append((frames[i + 1][1] - returned) * ms)
    # GPU record k is the work recorded after the k-th frame() returned;
    # record 0, open's.
    measured_gpu = gpu[warmup + 1:warmup + 1 + measured]
    series["gpu"] = [(p + c) / 1000 for p, c, _ in measured_gpu]
    series["gpu_passes"] = [p / 1000 for p, _, _ in measured_gpu]
    series["gpu_copy"] = [c / 1000 for _, c, _ in measured_gpu]
    window = (ended - frames[warmup][1]) * 1e-9
    scalars = {"fps": measured / window, "startup_ms": (frames[0][1] - opened) * ms,
               "slang_ms": slang[0], "slang_modules": slang[1]}
    return series, scalars


def machine():
    lines = [f"python {platform.python_version()}, {platform.platform()}"]
    if sys.platform == "darwin":
        chip = subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"], capture_output=True,
                              text=True).stdout.strip()
        power = subprocess.run(["pmset", "-g", "batt"], capture_output=True, text=True).stdout
        lines.append(f"{chip}; {power.splitlines()[0] if power else ''}")
    return lines


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--goose", default=os.environ.get("GOOSE") or shutil.which("goose"))
    ap.add_argument("--goose-src", help="the Goose tree the gfx originals come from")
    ap.add_argument("--runs", type=int, default=5)
    ap.add_argument("--warmup", type=int, default=120)
    ap.add_argument("--frames", type=int, help="measured frames, in place of each workload's")
    ap.add_argument("--conditions", default=",".join(CONDITIONS))
    ap.add_argument("--sides", default="ngfx,ngfx_full,gfx")
    ap.add_argument("--no-build", action="store_true", help="run what the last build left")
    ap.add_argument("workloads", nargs="*")
    args = ap.parse_args()
    if not args.goose:
        ap.error("no Goose compiler: set GOOSE or put goose on PATH")
    names = args.workloads or list(WORKLOADS)
    for n in names:
        if n not in WORKLOADS:
            ap.error(f"unknown workload {n}; there are {', '.join(WORKLOADS)}")
    conditions = args.conditions.split(",")
    sides = args.sides.split(",")
    tree = goose_tree(args.goose, args.goose_src)
    pin, head = readme_pin(), git(tree, "rev-parse", "HEAD")
    if pin and not head.startswith(pin):
        print(f"warning: the Goose tree is at {head[:9]}, the pin is {pin}", file=sys.stderr)

    if args.no_build:
        exes = {(s, n): OUT / "bin" / f"{s}_{n}{EXE}" for s in ("ngfx", "gfx") for n in names}
    else:
        exes = prepare(args.goose, tree, names)

    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    outdir = OUT / stamp
    outdir.mkdir(parents=True)
    info = machine() + [f"ngfx {git(REPO, 'rev-parse', '--short', 'HEAD')}"
                        f"{' (modified)' if git(REPO, 'status', '--porcelain') else ''}",
                        f"goose {head[:9]}", f"command: {' '.join(sys.argv)}"]
    (outdir / "machine.txt").write_text("\n".join(info) + "\n")
    print("\n".join(info), flush=True)

    rows = []
    for name in names:
        _, _, base_args, measured, variants = WORKLOADS[name]
        measured = args.frames or measured
        for suffix, extra in variants:
            for cond in conditions:
                for run in range(args.runs):
                    for side in sides:
                        exe_side = "gfx" if side == "gfx" else "ngfx"
                        env = dict(os.environ)
                        for k in ("GOOSE_GFX_HEADLESS", "GOOSE_NGFX_SYNC", "GOOSE_NGFX_NO_VSYNC",
                                  "GOOSE_BENCH_NO_VSYNC", "GOOSE_BENCH_MINE", "GOOSE_NGFX_BENCH"):
                            env.pop(k, None)
                        if cond == "headless":
                            env["GOOSE_GFX_HEADLESS"] = "1"
                        if cond == "novsync":
                            env["GOOSE_NGFX_NO_VSYNC"] = env["GOOSE_BENCH_NO_VSYNC"] = "1"
                        if side == "ngfx_full":
                            env["GOOSE_NGFX_SYNC"] = "full"
                        if exe_side == "ngfx":
                            env["GOOSE_NGFX_BENCH"] = "1"
                        if name == "minecraft_mine":
                            env["GOOSE_BENCH_MINE"] = "1"
                        exe = exes[(exe_side, name)]
                        cmd = [str(exe), "--frames", str(args.warmup + measured)] + base_args + extra
                        label = f"{name}{suffix} {cond} {side} run {run + 1}"
                        r = subprocess.run(cmd, cwd=OUT / "src" / exe_side, env=env,
                                           capture_output=True, text=True, timeout=1200)
                        parsed = parse(r.stdout, r.stderr, args.warmup, measured)
                        if r.returncode or not parsed:
                            print(f"FAIL {label}: exit {r.returncode}\n{r.stderr[-2000:]}", flush=True)
                            continue
                        series, scalars = parsed
                        raw = outdir / f"{name}{suffix}_{cond}_{side}_{run + 1}.csv"
                        with open(raw, "w", newline="") as f:
                            w = csv.writer(f)
                            keys = list(series)
                            w.writerow(keys)
                            for i in range(max(len(v) for v in series.values())):
                                w.writerow([f"{series[k][i]:.4f}" if i < len(series[k]) else ""
                                            for k in keys])
                        row = {"workload": name + suffix, "condition": cond, "side": side,
                               "run": run + 1, **scalars}
                        for k, v in series.items():
                            row[f"{k}_p50"] = statistics.median(v) if v else float("nan")
                            row[f"{k}_p5"] = percentile(v, 5)
                            row[f"{k}_p95"] = percentile(v, 95)
                        rows.append(row)
                        print(f"ok   {label}: frame {row['frame_p50']:.3f} ms, body "
                              f"{row['body_p50']:.3f} ms, gpu {row['gpu_p50']:.3f} ms, "
                              f"{row['fps']:.0f} fps", flush=True)
    if not rows:
        return 1
    with open(outdir / "runs.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    print(f"\nresults in {outdir}\n")
    print(summary(rows))
    return 0


def summary(rows):
    """One Markdown row per configuration: medians over runs, run-median ranges."""
    groups = {}
    for r in rows:
        groups.setdefault((r["workload"], r["condition"], r["side"]), []).append(r)

    def med(rs, k):
        return statistics.median(r[k] for r in rs)

    def spread(rs, k):
        return f"{min(r[k] for r in rs):.2f}-{max(r[k] for r in rs):.2f}"

    out = ["| Workload | Condition | Side | Frame p50 | p5 | p95 | Spread | Body p50 | In frame() p50 "
           "| GPU p50 | GPU p95 | Copy p50 | FPS | Startup ms | Slang ms |",
           "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for (w, c, s), rs in groups.items():
        out.append(f"| {w} | {c} | {s} | {med(rs, 'frame_p50'):.3f} | {med(rs, 'frame_p5'):.3f} | "
                   f"{med(rs, 'frame_p95'):.3f} | {spread(rs, 'frame_p50')} | {med(rs, 'body_p50'):.3f} | "
                   f"{med(rs, 'in_frame_p50'):.3f} | {med(rs, 'gpu_p50'):.3f} | {med(rs, 'gpu_p95'):.3f} | "
                   f"{med(rs, 'gpu_copy_p50'):.3f} | {med(rs, 'fps'):.0f} | {med(rs, 'startup_ms'):.0f} | "
                   f"{med(rs, 'slang_ms'):.0f} |")
    return "\n".join(out)


if __name__ == "__main__":
    sys.exit(main())
