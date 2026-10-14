# 03: Plan the benchmark against gfx

Status: done

This plan defines the comparison task 002 must validate. The harness and workloads
were implemented in `fbcf949`; the full measurement campaign remains open. References
to proposed instrumentation below describe the plan, not missing implementation.
[Development](../../docs/development.md#benchmark) documents the current harness.

## Acceptance criteria

- [x] Workloads: the four ported samples against their gfx originals, a draw-call
      throughput test (many small draws, each with its own root in `frame_data`), and an
      upload throughput test
- [x] Metrics: main-thread CPU time per frame, GPU time per frame from timestamp queries,
      frame time with and without vsync, and startup time with the Slang compile
      reported separately. If the layer has no timestamp queries, the plan says how to
      add them
- [x] Conditions: headless and windowed, each run plainly and under
      `GOOSE_NGFX_SYNC=full` to measure what the barrier rule saves. Machines: the M1 Pro
      (Metal 4), the RTX 4090 (Vulkan), and Linux headless
- [x] Method: warm-up frames, a fixed frame count, the median and spread over repeated
      runs, and machine and driver versions recorded as in
      [design.md](../../docs/design.md#status)
- [x] Where the harness lives, and how it builds the gfx originals at the pin
- [x] The result that would show the architecture doesn't hold is stated in advance.
      For example: ngfx is slower than gfx per frame on any sample, or
      `GOOSE_NGFX_SYNC=full` costs nothing measurable
- [x] A task to run the benchmark exists, numbered after this one

## Workloads

| Name | ngfx | gfx | Exercises |
|---|---|---|---|
| `cube` | `samples/cube.goose` | Goose's `samples/27_gfx_cube.goose` | Fixed per-frame cost: flags 1 to 4 in subtask 02 |
| `ui_todo` | `samples/ui_todo.goose --test` | `29_ui_todo.goose --test` | Per-draw externs, `frame_data` against gfx's transfer buffers (flags 11 and 12) |
| `minecraft` | `samples/mini_minecraft.goose` | `30_mini_minecraft.goose` | Steady state, then rebuild frames (below) |
| `doom` | `samples/mini_doom.goose --wad data/freedoom1-e1m1.wad` | `31_mini_doom.goose`, same WAD | Main-thread CPU, per-frame buffer updates |
| `draws` | new, `bench/draws_ngfx.goose` | new, `bench/draws_gfx.goose` | N small draws a frame, N = 1k, 10k, 50k |
| `uploads` | new, `bench/uploads_ngfx.goose` | new, `bench/uploads_gfx.goose` | K `update_buffer` and `update_texture` calls a frame, K = 1, 4, 16 |

The originals come from the Goose pin in `README.md` (use the compiler's source checkout),
and gfx from `goose_gfx` at the ref in that pin's `src/blessed.txt`.

- **Sample changes:** each sample pair takes `--frames N` already. The harness instruments
  scratch copies of both sides under `build/bench/src/`, adding per-frame timing
  reports without editing the originals. These copies are regenerated from the pin
  and the working tree, never edited by hand.
- **Minecraft rebuild frames:** the `minecraft_mine` workload sets `GOOSE_BENCH_MINE=1`
  to script one block removal every 10 frames,
  so chunk rebuilds (subtask 02 flags 6 and 7) are measured separately from steady state.
- **`draws`:** each draw is a quad with a root in `frame_data` holding a transform and a
  color, against gfx's per-draw uniform push. It runs four variants: ngfx vertex pulling
  against gfx vertex input, and each one indexed and non-indexed.
- **`uploads`:** it updates a 64 KB buffer and a 256 x 256 RGBA8 texture K times a frame,
  drawing with each between updates. At K = 4 and up, it shows the stall of upload
  batches (subtask 01 row 2, subtask 02 flag 6).

## Metrics

| Metric | How |
|---|---|
| Main-thread CPU time per frame | `ngfx::time()` around the program's frame body, plus inside `ngfx::frame()`. gfx: the same points |
| GPU time per frame | Timestamps at the start and end of each frame's command buffer |
| Frame time | Time between consecutive `frame()` returns, with vsync on and off |
| Startup | `open` to the first `frame()` return, with `ngfx::slang` timed separately |
| Throughput | Frames per second over the measured window, without vsync only |

GPU timestamps: NoGraphicsAPI has `write_timestamp(commands, cpu_destination, stage)`,
and `UploadQueue` already reads timestamps back. ngfx has no public timestamp-query
API; its benchmark instrumentation is internal.

- **ngfx:** add timestamps behind `GOOSE_NGFX_BENCH=1`, read back one frame later, at the
  start and end of each frame's commands and around the screen copy. The screen copy
  then gets its own number (subtask 01 row 4). Add no surface to `ngfx.goose` for this:
  the layer prints the numbers at `release` or exit.
- **gfx:** SDL_GPU has no timestamp queries. On gfx, measure GPU time with Xcode's Metal
  System Trace and Nsight Graphics on the same frames, and record that the method
  differs. Without vsync, compare wall-clock throughput between the two instead.
  Headless gfx never waits for the GPU (subtask 02), so headless frame rates aren't
  comparable. Every headless run ends with a `read_pixels` of the screen, which drains
  the GPU, and the measured window includes that read.

## Conditions

- Machines: the M1 Pro (macOS 26, Metal 4), the RTX 4090 (Windows 11, Vulkan), and
  Linux headless in WSL on the same RTX 4090. Linux runs are ngfx only, unless gfx is
  headless there too.
- Windowed, with vsync on and off, and headless. Each sample keeps the size it opens at
  (the same in both ports), and `draws` and `uploads` open at 1280 x 800.
- Each run plainly and under `GOOSE_NGFX_SYNC=full`.
- Built with `goose build`, never run in the compiler: the JIT measures TinyCC.
- Release builds of both native parts. Record the CMake build type.

## Method

1. Close other GPU programs, plug in the Mac, and use a fixed power mode.
2. Run 120 warm-up frames, then 1000 measured frames: 3000 for `draws` and `uploads`,
   and 600 for `minecraft --bench-mine`.
3. Run each configuration 5 times, alternating ngfx and gfx.
4. Report the median and the 5th and 95th percentiles of the per-frame numbers. Report
   the spread across runs as the range of the run medians.
5. Record the machine, OS, driver, SDK, slangc, compiler, Goose and `goose_gfx` refs, and
   the ngfx commit, as in [design.md](../../docs/design.md#status).

## Harness

`bench/run_bench.py`, run as `python bench/run_bench.py [workload ...]` with `GOOSE` set as
for the tests. It copies the gfx originals from the Goose pin into `build/bench/src/` and
applies timing instrumentation to both sides. It builds each program with `goose build`
into `build/bench/bin/` and writes raw per-frame CSV to `build/bench/<time>/` and a
summary table to stdout. Results go into task 002, with the commands that produced
them. `bench/` follows
goose-http's: a script, its inputs, and a results file, with nothing generated checked in.

## What would show the architecture doesn't hold

Decide these before running. A result on any one line means reopening the decision it
names.

- **Per frame:** ngfx's median frame time without vsync is over 5% worse than gfx's on any
  sample, on either machine, and stays worse after follow-ups P1 and P2 from subtask 02.
  That reopens the offscreen screen and the single screen texture.
- **CPU per draw:** ngfx's main-thread CPU time per draw in `draws` is no better than
  gfx's. Binding-free drawing is the premise, so this reopens the extern boundary and
  the copy that `root()` and `frame_data` make.
- **Barrier rule:** `GOOSE_NGFX_SYNC=full` costs under 2% GPU time on every workload, on
  both machines. Then the barrier rule buys nothing measurable here, and the
  module-placed barriers should be weighed against simplicity (subtask 01 row 3).
- **Upload stall:** `uploads` at K = 4 shows a CPU wait for the previous frame, and gfx
  doesn't. That confirms follow-up P4 is needed before release.
- **vsync spread:** with vsync, ngfx's 95th-percentile frame time is over 1.5 times
  gfx's. That calls for P3 and then P8.

## Follow-up

Task 002 runs this plan.
