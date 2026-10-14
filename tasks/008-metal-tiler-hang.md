# 008: Find the GPU hang in Mini Minecraft on Metal

Status: in-progress

The Metal workaround is implemented and tested. The historical investigation below
records the evidence, including experiments without the workaround. Multipass testing,
validation on a later macOS version, and reports to upstream and Apple remain open.
Temporary debug harnesses, logs, patches, and the native Metal repro were not committed;
their names below identify experiment provenance, not files available from this clone.

On the M1 Pro, headless `mini_minecraft --frames 40` sometimes never finishes. The
process blocks in `ngfx_gpu_next_frame`, in `wait_timeline`, and macOS restarts the GPU
with a "progress timeout" (`gpuEvent-*.ips`, signature 544): both TA slots (vertex and
tiling) busy, the 3D slots idle. `GOOSE_NGFX_SYNC=full` and `MTL_SHADER_VALIDATION=1`
have each hidden it. A build of `45dd8be`, before task 003, hangs too.

## Acceptance criteria

- [x] The hang reproduces at a known rate, at least 4 hangs in the default mode
- [x] One piece of `GOOSE_NGFX_SYNC=full` (before each pass, after each pass, or the
      frame boundary on every frame) prevents it on its own
- [x] The barrier narrowed to its minimal stages and accesses, and `docs/design.md`
      ("Synchronization") explains why the default mode lacks it
- [x] Fixed in ngfx, or reduced and recorded if the cause is in NoGraphicsAPI or the
      driver
- [x] Tests pass plainly and under `GOOSE_NGFX_SYNC=full`
- [x] An interleaved A/B in which the default mode hangs and the fix doesn't
- [ ] Compare every-pass and first-pass barriers in a program with multiple passes
- [ ] Rerun the native repro on a later macOS version before sharing it
- [ ] Report the repro and affected OS versions to NoGraphicsAPI's author and Apple

Each piece prevented it on its own (see "The full mode's pieces").

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

`python3 scripts/run_tests.py`, with `GOOSE` set to the compiler at the pin and the fix: 36
passed, every test plainly and under `GOOSE_NGFX_SYNC=full`.

The temporary harness, builds, and logs were kept outside version control.

## The first pass only

The temporary `mm_vtx` build uses the fixed tree with a `DBG_VTX` switch
(`dbg_vtx.patch`): 0 records the barrier before every pass, as the fix
does; 1 only before the first pass in each command buffer; 2 never. `ab.py` from 09:17
to 09:42, in the foreground of a Claude Code session in iTerm, with `AB_STOP=none:5`
(`first.log`):

| Variant | Hangs/runs |
| --- | --- |
| never | 5/270 |
| every pass | 0/269 |
| first pass only | 0/272 |

The median successful run took 1.57 s to 1.58 s in every variant.

This doesn't compare the two placements: `mini_minecraft` draws one pass a frame
(`begin_screen` to `end_pass`), so "every pass" and "first pass only" record the same
commands. It confirms the fix again, 5 hangs to none. Comparing them needs a program
with several passes a frame.

## The full mode's pieces

`ab.py` with `mm_dbg` (`dbb290c`, without the fix), in the foreground of a Claude Code
session in iTerm, from 09:42 to 10:09 and from 10:43 to 10:45 (`pieces.log`). It
stopped at 4 default hangs rather than 5:

| Variant | Hangs/runs |
| --- | --- |
| default (`DBG_SYNC=0`) | 4/250 |
| full barrier before each pass (`DBG_SYNC=1`) | 0/248 |
| full barrier after each pass (`DBG_SYNC=2`) | 0/251 |
| frame boundary every frame (`DBG_SYNC=4`) | 0/251 |

The default hangs came at 09:52:36, 10:00:54, 10:01:37, and 10:03:49. The maintainer
opened Signal at about the time of one of them, and was using a second Claude Code
session in iTerm during another, so the trigger looks like any other process drawing
with Metal, not one program starting.

With equal rates, all four hangs would fall in default one time in 256; against any one
piece alone, one time in 16. Each piece seems to prevent the hang on its own, the frame
boundary included, though it doesn't stop frames overlapping (see "Frames overlap on the
GPU"). So overlapping frames alone don't explain the hang, or the boundary's fragment-side
wait changes the timing enough to avoid it.

## The barrier's cost

The temporary `cost.py` harness runs `bench/run_bench.py --no-build` on `mm_vtx`'s tree, one
run at a time, alternating the three `DBG_VTX` placements in an order that reverses
each round: 8 rounds from 10:47 to 11:18 of `cube`, `minecraft`, and `doom`, 1,000
measured frames each after 120 of warmup, headless and windowed without vsync
(`cost.csv`). Another session was measuring CPU work on the machine at the time. One
headless `minecraft` run without the barrier hung (`gpuEvent` at 10:55:43) and was
killed. All three samples draw one pass a frame, so "first pass only" matches "every
pass" here, as expected.

Headless, the median over runs of each run's median:

| Workload | Variant | Frame (ms) | Range of runs | GPU (ms) | FPS |
| --- | --- | --- | --- | --- | --- |
| `cube` | never | 0.137 | 0.136 to 0.142 | 0.021 | 6599 |
| `cube` | every pass | 0.159 | 0.154 to 0.160 | 0.038 | 5921 |
| `minecraft` | never | 0.249 | 0.208 to 0.268 | 0.231 | 3136 |
| `minecraft` | every pass | 0.254 | 0.232 to 0.264 | 0.306 | 3112 |
| `doom` | never | 0.357 | 0.338 to 0.376 | 0.214 | 2400 |
| `doom` | every pass | 0.362 | 0.332 to 0.392 | 0.202 | 2381 |

In `cube`, which the GPU finishes fastest, the barrier costs about 20 µs a frame
(10% of its frame rate): the next frame's vertex work no longer overlaps the last one's
fragment work. In `minecraft` and `doom` the frame time moves 5 µs, inside the range of
runs. The GPU time per frame rises with the barrier in `cube` and `minecraft`, probably
because the pass's timestamps now include the wait for the earlier frame. Windowed, frames mostly take 8.3 ms
(the 120 Hz display) and the runs spread over 0.5 to 8.4 ms, so those runs don't
resolve a cost this small.

## Which barriers protect

Every variant that prevented the hang so far records a barrier compute encoder between
frames' render encoders, and the control that hung records none: NoGraphicsAPI's
`barrier` returns before opening an encoder when either side maps to no Metal stages.
These A/Bs separate the encoder from the barrier's stages. All ran in the foreground of
a Claude Code session in iTerm, with `mini_minecraft` builds of the fixed tree in which
a temporary `DBG_MODE` replaces the fix's barrier (`dbg_mode*.patch` and
temporary `dbg_raw*.patch` files). `raw` records
`barrierAfterStages:beforeQueueStages:` with the given Metal stages and no visibility,
bypassing NoGraphicsAPI's mapping.

| Variant (`DBG_MODE`) | Metal stages, after to before | Hangs/runs |
| --- | --- | --- |
| `none` | no barrier | 2/331, 1/250, 1/265, 5/766 |
| `vtx`, the fix | Vertex to Vertex, Fragment, Tile | 0/332 |
| `xfer` | Blit to Blit | 2/333 |
| `empty` | an encoder with no barrier (NoGraphicsAPI patched) | 1/331 |
| `raw` `1,1` | Vertex to Vertex | 0/249, 0/266 |
| `raw` `1,10000000` | Vertex to Blit | 2/251 |
| `raw` `2,1` | Fragment to Vertex | 0/247, 0/266 |
| `raw` `10000000,1` | Blit to Vertex | 4/251 |
| `raw` `2,2` | Fragment to Fragment | 0/266, 0/762 |

`enc.log` ran from 12:46 to 13:24, `raw.log` from 13:25 to 14:03, `raw2.log` from
14:03 to 14:31, and `ff.log`, with `none` and Fragment to Fragment only, from 14:32 to
15:14. The hangs cluster: 6 of `raw.log`'s 7 came between 13:28 and 13:36,
while the maintainer was using the machine; `raw2.log` ran with the trigger mostly
absent, so its zeros say little. Each of the first 13 hangs left a `gpuEvent` report within
15 s of it, all signature 544 with TA slots 0 and 1 busy, one of them in substate 4,
and the 3D and CL slots idle, whatever the variant. No report came without a logged
hang.

A hang shows a variant doesn't protect; a zero only weighs against equal rates. So
the encoder alone doesn't protect, and neither does a barrier with Blit on either side.
Every barrier with a render stage on both sides has none so far, including ones that
order unrelated work (Fragment to Vertex), or whose destination leaves the next frame's
vertex work free to start (Fragment to Fragment, and the frame boundary, under which
frames were measured overlapping). That fits the driver treating a render-to-render
barrier differently, not a missing order between frames.

## The trigger

Historical session transcripts correlate the hangs with a second Claude Code session
in iTerm running CPU benchmarks and redrawing the terminal. Per 10 minutes, counting the
variants that don't protect:

| Window | Hangs/runs | That session's assistant messages |
| --- | --- | --- |
| 13:20 to 13:40 | 7/367 | 238 |
| 14:20 to 15:00 | 1/643 | 6 |
| 15:10 to 15:20 | 3/62 | 38 |

It doesn't hold everywhere: 13:00 to 13:20 had about 90 messages per 10 minutes and 1
hang in about 260 runs each. That session ran CPU benchmarks as well as redrawing iTerm,
and the transcripts don't separate the two. The maintainer saw two hangs come as that
session showed a question's options and while typing a prompt into it.

## Fragment to Fragment as the fix

`mm_fix`'s tree with the fix's barrier changed to `barrier(Stage::fragment, none,
Stage::fragment, none)`, which NoGraphicsAPI maps to Vertex, Object, Mesh, Fragment, and
Tile to Fragment and Tile, the frame boundary's shape, with a temporary `DBG_MODE`
selecting the old barrier or none (`ff_dbg.patch`). `ab.py` from 15:18 to 15:42, with
`AB_STOP=none:3` (`fffix.log`): none 3/268, the current fix 0/267, Fragment to Fragment
0/269.

`cost.py` with the same switch, 8 rounds headless, 1,000 measured frames
(`cost_ff.csv`), the median over runs of each run's median frame time:

| Workload | None | Fragment to Fragment | The fix |
| --- | --- | --- | --- |
| `cube` | 0.140 ms | 0.159 ms | 0.159 ms |
| `minecraft` | 0.243 ms | 0.261 ms | 0.256 ms |
| `doom` | 0.344 ms | 0.367 ms | 0.364 ms |

Fragment to Fragment costs what the fix does, so the fix stays: it has far more runs
without a hang behind it.

## Is ngfx's frame legal NoGraphicsAPI?

NoGraphicsAPI leaves synchronization to the application and means frames to overlap:
its Metal mapping lets "independent vertex, object and mesh work overlap previous
passes", and timestamp reads add no wait, "preserving the opportunity for overlap
between frames" (`metal-support.md`, "Synchronization"). Against that contract, ngfx's
frame in the default mode orders every hazard:

- A frame that clears the screen draws into an instance no earlier frame in flight uses:
  `renew_screen` rotates `frames_in_flight` instances, and the timeline wait before a
  slot's pool reset covers the frame that last drew into the instance it takes.
- Frame memory and command pools are reused after that same wait, as `examples/cube`
  does; the contract asks for "completion of their submitted uses".
- Uploads carry `UploadQueue`'s own all-commands barriers, and passes in one frame that
  reuse a target get a barrier.

So the missing barrier is no missing order. But no upstream example records this frame:
`examples/cube` draws into one depth texture and records a depth-to-depth barrier, a
render-to-render one, every frame; `examples/deferred_renderer` keeps one G-buffer and
records the frame boundary's barrier every frame; and `examples/triangle` records no
barrier but draws into the drawable, behind `submit_and_present`'s `waitForDrawable`.
Only headless ngfx with renewed screens submits render command buffers back to back with
neither. `metal_barrier_test` probes overlap across submissions, but NoGraphicsAPI is
tested on an M3 Max with macOS 26.6.2 only (`metal-validation.md`); M1 is unverified.
The investigation used macOS 26.3.1; later OS versions were not tested.

## A native Metal repro

The untracked `repro_metal_tiler_hang.mm` (not yet shared) is
standalone Metal 4 in the form of NoGraphicsAPI's `tests/repro_metal_render_timestamps.mm`,
with no NoGraphicsAPI, Slang, or ngfx. Each frame is one command buffer with one render
pass that clears a color and a depth target of its frame-in-flight slot and draws 50,000
vertex-pulled triangles (about 0.4 ms); two frames are in flight, paced by a shared
event, with nothing between them. `--barrier vv|ff|bb` records a producer barrier in a
compute encoder before each pass. It exits 2 when a frame doesn't finish in 10 s. It
passes Metal API validation. Build it with
`clang++ -std=c++20 -O2 -fno-objc-arc repro_metal_tiler_hang.mm -framework Foundation -framework Metal -o repro`.

`repro_ab.py` with `--frames 4000` (1.6 s a run), from 16:03 to 16:15, in the foreground
of a Claude Code session in iTerm, with the maintainer working (`repro.log`):

| Variant | Hangs/runs |
| --- | --- |
| no barrier | 3/93 |
| Vertex to Vertex | 0/94 |
| Fragment to Fragment | 0/93 |
| Blit to Blit | 1/93 |

The first run without a barrier hung too. Every hang left a `gpuEvent` report with
signature 544, both TA slots busy, and the 3D slots idle, as `mini_minecraft`'s do. So
the hang needs none of ngfx, NoGraphicsAPI, or Slang.

## Next

- Compare the barrier before every pass with the first pass in each command buffer, for
  the hang and the cost, in a program that draws several passes a frame.
- Rerun the repro on a later macOS version (no barrier against Vertex to Vertex),
  to see whether a later driver fixed it. Share nothing before that.
- Then report it to NoGraphicsAPI's author in the form of `docs/known-driver-issues.md`,
  and to Apple, with the repro and the macOS versions it hangs on.
