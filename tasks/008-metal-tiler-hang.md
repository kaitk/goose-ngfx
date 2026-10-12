# 008: Find the GPU hang in Mini Minecraft on Metal

Status: in-progress

On the M1 Pro, headless `mini_minecraft --frames 40` sometimes never finishes. The
process blocks in `ngfx_gpu_next_frame`, in `wait_timeline`, and macOS restarts the GPU
with a "progress timeout" (`gpuEvent-*.ips`, signature 544): both TA slots (vertex and
tiling) busy, the 3D slots idle. `GOOSE_NGFX_SYNC=full` and `MTL_SHADER_VALIDATION=1`
have each hidden it. A build of `45dd8be`, before task 003, hangs too.

## Acceptance criteria

- [x] The hang reproduces at a known rate, at least 4 hangs in the default mode
- [ ] One piece of `GOOSE_NGFX_SYNC=full` (before each pass, after each pass, or the
      frame boundary on every frame) prevents it on its own
- [x] The barrier narrowed to its minimal stages and accesses, and `docs/design.md`
      ("Synchronization") explains why the default mode lacks it
- [x] Fixed in ngfx, or reduced and recorded if the cause is in NoGraphicsAPI or the
      driver
- [x] Tests pass plainly and under `GOOSE_NGFX_SYNC=full`
- [x] An interleaved A/B in which the default mode hangs and the fix doesn't

The second criterion is open: the fix came from the hypothesis about the TA slots, not
from testing each piece of the full mode, and the full mode's pieces were never tested
under the iTerm trigger.

## How runs are counted

Every number below comes from the M1 Pro, macOS 26.3.1 (a) (25D771280a), on AC power,
at `dbb290c` (Goose pin `fe6c543`). Each run is `GOOSE_GFX_HEADLESS=1 <exe> --frames 40`
from `samples/`; a healthy run takes 1.5 s. A run still going after 12 s is a hang: it is
killed, and the next run starts 20 s later. A run that follows a hang isn't counted,
because the GPU restart makes it time out too. Variants alternate run for run, in an
order that reverses each round.

`<exe>` is `build/bin/mini_minecraft` (built at 17:43, before the uncommitted bench
changes) or a debug build of the same tree with a temporary `DBG_SYNC` bitmask in
`ngfx_draw.cpp`: 1 records the full barrier before each pass, 2 after each pass, and 4
the frame boundary on every frame, renewed screens included. `DBG_B=s,a,s,a` (hex
NoGraphicsAPI `Stage` and `Access` bits) replaces the full barrier for 1 and 2.

## Results

The hang comes in clusters a few minutes long: twice in 128 runs at 23:20, then nothing
in 6,391 counted runs under every load tried, then four times between 06:48 and 06:55.

| Time (2026-10-11/12) | Executable and variants | Conditions | Hangs/runs |
| --- | --- | --- | --- |
| 23:18 to 23:19 | `build/bin` | | 0/30 |
| 23:20 to 23:24 | `build/bin` | | 2/98 |
| 23:25 to 00:03 | debug: `DBG_SYNC` 0, 1, 2, 4 | | 0/400 each |
| 00:04 to 00:17 | `build/bin` and debug `DBG_SYNC=0` | | 0/300 each |
| 00:18 to 01:19 | debug: `DBG_SYNC` 0, 1, 2, 4 | display off from 00:48 | 0/647 to 0/648 each |
| 01:19 to 01:30 | debug `DBG_SYNC=0` | a headless `cube` running alongside | 0/400 |
| 01:30 to 01:41 | debug `DBG_SYNC=0` | a windowed `cube` running alongside | 0/400 |
| 01:42 to 01:47 | debug `DBG_SYNC=0` | a second `mini_minecraft` running alongside | 0/200 |
| 01:50 to 02:00 | debug `DBG_SYNC=0` | ten processes spinning on the CPU | 0/300 |
| 02:04 to 02:14 | debug `DBG_SYNC=0` | Safari drawing a WebGL page, GPU at 99% | 0/300 |
| 07:27 to 07:33 | debug: default, the vertex barrier | Claude Code working in iTerm | 3/69, 0/70 |
| 02:32 to 07:00 | debug: default, the control, the vertex barrier, `GOOSE_NGFX_SYNC=full` (see "The overnight A/B") | display off until 06:32 | 2/2869, 2/2871, 0/2869, 0/2871 |

The two hangs left `gpuEvent` reports at 23:21:04 and 23:22:08, both signature 544, with
`fw_ta_state` busy in slots 0 and 1 and `fw_3d_state` idle. The earlier session's hangs
left reports at 21:58, 22:00, and 22:01. The 23:20 cluster came while the maintainer was
using the machine. The 06:48 cluster came after the display turned on at 06:32, with the
last keyboard or mouse input at 06:49; its four reports at 06:48:39, 06:52:14, 06:53:33,
and 06:54:33 have the same signature and TA state. The trigger is some state of the
machine that none of the loads above recreates, and it seems tied to the display or to
someone using the machine.

`mini_minecraft` holds a `PreventUserIdleDisplaySleep` assertion, even headless (SDL
disables the screen saver), so a loop of runs keeps the display from sleeping.
`pmset displaysleepnow` turns it off.

## Frames overlap on the GPU

With GPU timestamps around each pass (the temporary debug build, with
`GOOSE_NGFX_BENCH=1`), consecutive frames pipeline in the default mode. In each frame
pair where the CPU had recorded frame N+1 before the GPU finished frame N's fragment
work, the table counts how often N+1's vertex work started first. Each line is 10 runs of
40 frames; the times are mach ticks of 41.7 ns.

| Variant | Pairs with N+1 ready | N+1's vertex work before N's end |
| --- | --- | --- |
| default | 345 | 273 (79%) |
| `DBG_SYNC=4` (frame boundary every frame) | 379 | 280 (74%) |
| `DBG_SYNC=1` (full barrier before each pass) | 380 | 31 (8%) |
| `DBG_SYNC=2` (full barrier after each pass) | 379 | 35 (9%) |
| `GOOSE_NGFX_SYNC=full` | 374 | 73 (20%) |
| `DBG_SYNC=1 DBG_B=0,0,0,0` (records nothing) | 380 | 35 (9%) |

The frame boundary doesn't stop frames overlapping, as NoGraphicsAPI's Metal mapping
says: a barrier whose destination is color or depth output waits at the fragment and
tile stages only, so the next pass's vertex work can start
(`third_party/NoGraphicsAPI/docs/metal-support.md`, "Synchronization"). That is why a
build from before task 003, which recorded the frame boundary every frame, hangs too.

The last line rules out reading the rest as barrier semantics. The bit-1 path with a
barrier that records nothing serializes the frames as well as the full barrier does.
Neither half of that path does it on its own (a direct `barrier(none, ...)` call: 214 of
275 early; only the `getenv` and `sscanf`: 234 of 288), and spinning the CPU for 2 to
50 µs before each pass doesn't either (78% to 79%). Each run settles in one of two
regimes: the GPU slightly faster than the CPU and the passes serialized (about 13,000
ticks each), or the passes overlapping and slowing each other (17,000 to 28,000 ticks).
Small changes to the CPU's work choose the regime. So the hang needing the full mode's
barriers is not yet shown, and neither is which barrier.

A Metal 4 producer barrier (`barrierAfterStages:beforeQueueStages:`, which NoGraphicsAPI
records in a compute encoder of its own) makes later encoders wait for earlier work "in
the current and prior encoders", so it orders earlier command buffers on the queue. A
barrier from `Stage::vertex` to `Stage::vertex | Stage::index_input` before a frame's
first pass would keep two frames' vertex work out of the tiler at once, which is what the
`gpuEvent` reports show. No data hazard calls for it: consecutive frames draw into
different screens and share only read-only data. If it prevents the hang, the cause is
more likely in the driver than a barrier ngfx misses.

## The overnight A/B

`ab.py 100000 night.log` with four variants of the frozen debug build, from 02:32 to
07:00 on 2026-10-12: default (`DBG_SYNC=0`); the control, which takes the bit-1 path but
records nothing (`DBG_SYNC=1 DBG_B=0,0,0,0`); the vertex barrier before each pass
(`DBG_SYNC=1 DBG_B=4,0,6,0`, from `Stage::vertex` to `Stage::vertex | Stage::index_input`,
no accesses); and `GOOSE_NGFX_SYNC=full`.

| Variant | 02:32 to 07:00 | 06:45 to 06:56 |
| --- | --- | --- |
| default | 2/2869 | 2/86 |
| control | 2/2871 | 2/88 |
| vertex barrier | 0/2869 | 0/86 |
| `GOOSE_NGFX_SYNC=full` | 0/2871 | 0/88 |

All four hangs fell in the variants without a real barrier. If every variant hung at the
same rate, that would happen by chance one time in 16, so this points at the vertex
barrier but doesn't establish it. The control hanging means the timing regime that its
path chose in the overlap measurements doesn't protect on its own.

## A day run

`ab.py` with default and the vertex barrier only, for 5 minutes from 07:27, run in the
foreground of a Claude Code session in iTerm: default hung at 07:28:19, 07:29:08, and
07:30:22 (3 of 69 runs, three `gpuEvent` reports), the vertex barrier 0 of 70. Across
this and the overnight A/B, default has 5 hangs and the vertex barrier none; with equal
rates that would happen by chance one time in 32.

The maintainer sees the hang mostly while using Claude Code in iTerm, not while using
Firefox. iTerm draws with Metal, and Claude Code redraws it continuously while a tool
runs; the overnight A/B ran in the background, with nothing redrawing until 06:32.
That would make the trigger another process's Metal work of a particular shape, which
Safari's WebGL load doesn't have.

## The fix

`ngfx_begin_pass` records, on Metal only, a barrier from `Stage::vertex` to
`Stage::vertex | Stage::index_input` with no accesses before every pass
(`docs/design.md`, "Synchronization"). Before each frame's first pass alone might be
enough, but that wasn't tried.

`ab.py` from 07:42 to 07:51, in the foreground of a Claude Code session in iTerm, with
`AB_STOP=base:5`: `goose build` of `mini_minecraft` from the working tree (the bench
changes included) without the fix hung 5 of 123 runs; with the fix it hung 0 of 122.
With equal rates that would happen by chance one time in 32. The median run took 1.52 s
both ways, over 120 and 125 successful runs. A 40-frame run is mostly startup, though,
and `GOOSE_NGFX_BENCH=1`'s GPU times vary tenfold between runs of the same build, so
the barrier's per-frame cost isn't measured.

`GOOSE=../goose-upstream/build/goose python3 scripts/run_tests.py` with the fix: 36
passed, every test plainly and under `GOOSE_NGFX_SYNC=full`.

The harness, both builds, and the logs are in `build/dbg/008/` (ignored by Git).

## Next

- Try the barrier before each frame's first pass only, against the current fix.
- Close the second criterion: under the iTerm trigger, A/B default against each piece
  of the full mode on its own (`DBG_SYNC` 1, 2, and 4 in `build/dbg/008/mm_dbg`).
- Measure the barrier's per-frame cost with a steadier benchmark.
- Reduce it to a NoGraphicsAPI example (`examples/cube` with several passes, beside a
  Metal-drawing iTerm) and report it to Apple as a driver hang.
