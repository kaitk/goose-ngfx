# The design of ngfx

What `ngfx` is, what it costs, and why it is shaped as it is. [api.md](api.md) is the API
overview, and the header of `ngfx.goose` the reference.

## What it is

`import ngfx;` gives a Goose program graphics on Sebastian Aaltonen's
[NoGraphicsAPI](https://github.com/sebbbi/NoGraphicsAPI) (`third_party/NoGraphicsAPI`), a
small C++ API over Metal 4 and Vulkan 1.4 with no bindings, no resource states, and GPU
pointers in place of descriptors. ngfx keeps Goose gfx's platform half (window, input,
time, the screen, textures, read-back) and draws the way NoGraphicsAPI does: a draw takes
the GPU address of a root struct the program fills and shares with its shader, and
shaders fetch their own vertices through pointers.

The submodule is a fork, `kaitk/NoGraphicsAPI`, for what ngfx needs that NoGraphicsAPI
lacks (2026-11-11). Each change is a branch of its own on upstream's `main`, small and
general, so it can be offered upstream as a pull request; the fork's `ngfx` branch is the
upstream commit ngfx pins with every such change merged, and the submodule follows it.
`main` mirrors upstream. The first change is ASTC 6 × 6 (`astc-6x6`), the block size
Draughts' photographs use. A change ngfx can make in its own layer stays there; the fork
is for what only NoGraphicsAPI can do.
Its pull request upstream, `astc-6x6` to `sebbbi/NoGraphicsAPI`, is the maintainer's to
open and isn't open yet (2026-11-11). gfx's `WINDOW_ONLY` is the same: a branch of
`kaitk/goose_gfx` (`window-only`), its pull request to `aardappel/goose_gfx` not yet open.

    Goose program --extern fn--> ngfx_* (native/, C and C++) --> NoGraphicsAPI (static)

Shaders are Slang modules, compiled while the program runs by `ngfx::slang`. Four of
Goose's gfx programs are ported to it as the acceptance set: `cube`, `ui_todo`,
`mini_minecraft`, and `mini_doom` in `samples/`, with Goose's gfx tests ported to
`test/`.

## Why a separate repository

ngfx began in a fork of Goose, with the compiler changes a native layer of Goose's own
gets: a builtin, `embed_slang`, that compiled Slang while Goose compiled the program;
the layer's symbols in the JIT; `--ngfx-link`; and the main-thread check. It was
proposed upstream and moved out instead (agreed with Goose's maintainer, 2026-10-10).
Goose keeps its toolchain light: its gfx compiles GLSL with a small built-in compiler,
so a Goose executable needs no Vulkan SDK and no external shader compiler, and Goose's
work is on CPU performance first. ngfx needs slangc and Metal 4 or Vulkan 1.4.

So this repository uses Goose as it ships, as a package (`ngfx.goose`, `ngfx.build`, and
a CMake project for the native part), and each compiler change has a counterpart here:

| In the fork | Here |
|---|---|
| `embed_slang` compiled Slang into the program | `ngfx::slang` compiles it when the program runs |
| `goose file.goose` ran ngfx programs with TinyCC | The same, through the package's JIT library |
| The compiler rejected ngfx calls from a `thread_fn` | The same, from `main_thread_only` in `ngfx.build` |
| `--ngfx-link` printed the link inputs | `goose build` links the package's native part |
| C names `gs_ngfx_*` | `ngfx_*`: `gs_` is Goose's |

## Status

See the [README status](../README.md#status) for platform coverage and
[development toolchains](development.md#toolchain) for tested versions.

On Metal, headless screenshots of the cube, Mini Doom, and the to-do list matched
Goose's gfx originals byte for byte in historical package validation.
Mini Minecraft differed in 48 isolated pixels of nearest-sampled leaves, where Slang
and Goose's MSL round a texture coordinate differently.

Task 001's architecture audits support the allocation, offscreen-screen, and
application-barrier policies, with deliberate deviations for gfx-compatible behavior.
Their follow-ups added pipeline preparation, indirect commands, indexed ui draws,
color-only transfer usage, larger upload batching, direct staging of buffer data,
hot-path trims, and overlapping screen frames.
Performance parity with gfx remains unverified: task 002 runs the benchmark, task 003
still needs its before/after frame times, and task 004 waits for the pacing results.
The Metal driver workaround and its measured cost are described under
[Synchronization](#synchronization).

## What it costs

These choices follow NoGraphicsAPI rather than the rest of Goose. Each is deliberate.

- **A separate module, not a gfx backend.** NoGraphicsAPI needs Metal 4 or Vulkan 1.4 on
  recent GPUs and drivers. Under gfx it would either hold gfx's API to what SDL_GPU and
  NoGraphicsAPI can both do, or drop platforms gfx supports.
- **Slang, not GLSL.** NoGraphicsAPI's shader headers are Slang. `ngfx::slang` runs
  `slangc` (and Xcode's `metal` and `metallib` on macOS) as subprocesses, so running an
  ngfx program needs those tools installed.
- **Y-down clip space** with depth from 0 to 1, NoGraphicsAPI's on both backends. 3D code
  using ngfx's `perspective`, `ortho`, and `look_at` sees no difference; 2D code that
  writes clip positions directly sees y flipped relative to gfx.
- **Row-major matrices** (`float4x4`), as NoGraphicsAPI's `shader_types.h` and its
  `-matrix-layout-row-major` build have them, so a struct shared with a shader means the
  same in C++, Slang, and Goose. gfx's `mat4` is column-major.
- **C++ in the native layer.** Goose's layers are C. ngfx's GPU half is C++ because it
  uses NoGraphicsAPIUtility's `UploadQueue`, `DeleteQueue`, and allocators directly,
  which is what keeps its uploads synchronized exactly as NoGraphicsAPI's are. A program
  links the C++ runtime.
- **A high hardware bar**: macOS 26 and Metal 4, or Vulkan 1.4.357 with descriptor heaps,
  64-bit only, and CMake 3.25.
- **A window from elsewhere.** ngfx has no platform: it draws into a native window the
  program gives it, in practice gfx's opened `WINDOW_ONLY`, which Goose's gfx doesn't
  have yet (`kaitk/goose_gfx`'s `main` has it, proposed upstream).

## How it is built

The layer follows the conventions of Goose's native layers (its `docs/design/physics.md`):
packed C structs, `let` constants, `ngfx_` names, and one X-macro list (`NGFX_API` in
`native/ngfx_api.h`) that expands into the prototypes and that `scripts/api_check.py`
compares with the `extern` declarations in `ngfx.goose`.

- `native/ngfx_core.c`: errors, open and close, `present` and `resize`, and PNG through
  stb_image (`third_party/stb`).
- `native/ngfx_device.cpp`, `ngfx_resources.cpp`, `ngfx_draw.cpp`, `ngfx_gpu.hpp`: the GPU
  half over NoGraphicsAPI and NoGraphicsAPIUtility.
- `native/ngfx_slang.cpp`: `ngfx::slang`.
- `native/ngfx_screen.slang`, `ngfx_mips.slang`: the layer's own shaders, compiled when
  the layer is built and embedded as byte arrays (`cmake/bin2h.cmake`).
- `CMakeLists.txt` builds NoGraphicsAPI, the shaders, and the layer, as the target
  `ngfx` that `ngfx.build` names; the Goose compiler builds it when a program imports
  ngfx ([development.md](development.md#how-a-program-is-built)).

### `ngfx::slang`

- **One blob holds SPIR-V and, on a Mac, a metallib.** The pipeline functions take the
  blob as bytes, so a program can build its own blobs too. A blob without a metallib
  fails on Metal, saying why.
- **Vertex, fragment, and compute entry points only.** NoGraphicsAPI also has mesh and
  task shaders; ngfx has no pipeline for them yet, so `ngfx::slang` rejects them.
- **One `slangc` run per target compiles the whole module**, every `[shader(...)]` entry
  point, and the blob shares the code between stages. Entry points, stages, and compute
  `numthreads` come from slangc's reflection JSON.
- **A subprocess, not libslang.** Linking would make every program depend on a library of
  about 100 MB. NoGraphicsAPI's own build runs `slangc` too.
- **At run time, because Goose has no hook for it.** Goose can't run an outside compiler
  while it compiles a program. The cost is about 0.2 s per module at startup on Windows,
  slangc on the machine that runs the program, and Slang errors that abort the program
  rather than fail its compile
  ([findings](goose-findings.md#shaders-in-an-outside-language-compile-at-run-time)).
- **The blob is appended to a `u8[>..]&`** with `goose.h`'s `gs_bld_append`, in the call
  that compiles it, so the layer keeps no result between calls. Text whose size the
  program can't know, such as `ngfx::error()` and `ngfx::clipboard()`, comes back the
  same way.
- **Tool paths are found at configure time**, overridable with `NGFX_SLANGC`,
  `NGFX_SPIRV_VAL`, and `NGFX_NOGRAPHICSAPI`. The include directories are the source
  tree's.

## Decisions

### Surface

- **gfx's platform half, NoGraphicsAPI's drawing.** `open`, `frame`, input, events, the
  screen, textures, samplers, read-back, `screenshot`, and `release` keep gfx's names and
  behavior. Drawing takes roots and GPU addresses. gfx's API rebuilt over NoGraphicsAPI
  would recreate the binding model NoGraphicsAPI removes.
- **Gone, with no NoGraphicsAPI equivalent:** `bind_*`, `uniforms`,
  `begin_compute`/`end_compute`, vertex formats, buffer usage flags, primitive types other
  than triangles, wireframe, MSAA, and the `NO_VSYNC` and `DEBUG` flags.
- **Every texture gets a descriptor slot** in heaps the module owns. NoGraphicsAPI leaves
  heaps to the application, but gfx programs never managed them.
- **In a window, the screen is the window's image** (2026-11-11), replacing an offscreen
  RGBA8 texture and its spare per frame in flight, copied into the image by a fullscreen
  draw at `present()`: 48 MB at 2560 × 1600 and a pass a frame, which made Draughts'
  2D game hold 52 MB more than on gfx. The handle's slot describes the image (BGRA8, the
  window's size), and a frame's first pass into it submits the frame's work so far and
  acquires the image in a new command buffer, so only the submission that presents waits
  for it. The image holds nothing of the last frame and can only be drawn into, so a
  window's screen can't be sampled, read back, updated, or saved, and a window that wants
  showing again (`needs_present()`) needs the program to draw a frame. On Apple's systems
  `open` and `resize` set the layer's drawable size to the screen's, so the image always
  fits it; when there is no image of the screen's size to acquire (a window minimized,
  a resize the swapchain hasn't followed), the frame draws into a stand-in texture,
  shown nowhere, given back once a frame gets an image. Headless, the screen is one RGBA8
  texture, which keeps what the last frame drew, as gfx's does. Rejected: reading the
  image back (NoGraphicsAPI gives it only as a render target; Metal would need the
  layer's `framebufferOnly` off, and Vulkan transfer usage on the swapchain), and
  keeping an offscreen copy only for programs that take windowed screenshots (a second
  way to draw the screen for one feature no program here needs in a window). The copy
  did no sRGB conversion, and neither does the image: it is UNORM, as gfx's swapchain.
- **`draw_indexed` takes its indices as a `Range`**, an address and a size, as
  NoGraphicsAPI's takes any `GpuRange`, so indices can live in frame memory
  (`frame_range`). The overloads that take a `Buffer` look its range up first, one more
  extern per draw; a program that draws a buffer often can keep `range(b)`. The size
  lets the layer check the draw's indices against it.
- **`SV_VertexID` counts from `first_vertex` on Metal and from 0 on Vulkan.** Slang
  compiles it to SPIR-V as `VertexIndex - BaseVertex` and to MSL as `[[vertex_id]]`,
  which Metal starts at `vertexStart` and offsets by `baseVertex`; `SV_InstanceID`
  excludes `first_instance` on both. Seen in slangc 2026.18.3's output, and measured on
  Metal and on Vulkan (2026-10-11); on Vulkan, `vertex_offset` is excluded too. Shaders that fetch their own vertices take where they start from
  their root, or draw indexed with `vertex_offset` 0, where `SV_VertexID` is the index on
  both. `ngfx_ui` draws that way.
- **Indirect commands take their arguments' address**, as a draw takes its root's, and
  `draw_indexed_indirect` its indices as a `Range`, as `draw_indexed` does. The layer
  checks the address is 4-byte aligned and the stride, and gives NoGraphicsAPI the
  range the commands span; it can't check the indices the GPU-written arguments name.
  `DrawArguments`, `DrawIndexedArguments`, and `DispatchArguments` spell the layouts,
  which Vulkan's and Metal's indirect argument structs share.
- **Pipelines are created lazily per set of target formats**, as gfx does, because
  NoGraphicsAPI fixes formats in the pipeline. `ngfx::prepare(pipeline, PassDesc)`
  creates one ahead, so the driver compiles its shaders before the frame loop, as
  NoGraphicsAPI's examples create every pipeline first. It takes a `PassDesc` rather than
  format fields in `PipelineDesc`: the formats then come from the textures the passes
  draw into, so they can't drift from them, `PipelineDesc` keeps gfx's fields, and one
  pipeline can be prepared for several passes. The samples prepare theirs for the
  screen (`prepare_screen`), and `ngfx_ui::prepare()` does the same for the ui.
- **No platform: ngfx draws into a window the program gives it** (2026-11-11), replacing
  the platform half copied from gfx over an SDL of ngfx's own. NoGraphicsAPI takes a
  native window and needs no SDL. With its own, ngfx put two SDLs in any process that
  also used gfx, `audio`, or `ui` (the objc runtime warned of every class twice on the
  Mac), duplicated gfx's platform code, and kept a program from choosing between gfx and
  ngfx at run time. `open` takes the window's native handle; `present()` ends the
  frame and says whether it showed one, which the program hands to its platform's wait.
  gfx's `WINDOW_ONLY` is that platform for Goose programs: it opens the window without
  a device and keeps input, events, time, and the idle wait, so draw on demand is gfx's
  wait and ngfx's knowing whether a pass drew into the screen, and a window the system
  exposes is presented again through `needs_present()`. Rejected: ngfx's platform on the
  program's SDL with no SDL built (still a second copy of gfx's platform code); a
  program's own host straight on SDL (every program would write one).
- **The name is `ngfx`.** It reads as gfx on NoGraphicsAPI. `gfx2` would presume it
  replaces gfx, `gpu` is NoGraphicsAPI's C++ namespace, and `nogfx` reads as "no graphics".
- `CULL_BACK` with counterclockwise front faces is NoGraphicsAPI's `CullMode::clockwise`,
  as in its cube example. `COMPARE_*` keep gfx's values, and the layer converts.
- `GOOSE_GFX_HEADLESS` makes `ngfx::open` headless too, as it does gfx's.

### Memory and submission

- **Memory is sized from use, starting small** (2026-11-11), as SDL_GPU's is with the
  patch Draughts carries for exact large allocations. Buffers and textures are
  suballocated with NoGraphicsAPIUtility's allocators from chunks made as they fill, 2 MB
  for buffers and 4 MB for textures; one over half a chunk gets memory of exactly its
  size, shared with nothing and given back with it, so a large resource never rounds up
  to a block or keeps one alive. A frame's memory starts at 256 KB per frame in flight
  and doubles when a frame outgrows it, the outgrown memory given back once that frame
  has finished. The upload queue is 4 MB; larger uploads pass through it in parts. The
  screen's depth is made only when a program asks for `screen_depth()`. Releases wait in
  lists that grow as needed, not NoGraphicsAPIUtility's `DeleteQueue`, whose fixed ring
  of 128-byte callbacks held 9 MB at the 65,536 entries a burst of releases needs.
  Timestamp storage is reserved only under `GOOSE_NGFX_BENCH`. Fixed, as measured too
  small to size: 8192 texture and 1024 sampler descriptors (72 KB on Metal).
- **The first idle frame gives back the driver's memory for recording** (2026-11-11). A
  Metal 4 command allocator keeps the most memory it was ever recorded into, and
  resetting it returns none, so the frames that set a program up (textures initialized,
  photographs uploaded in parts) held their command memory for good: 11 MB of the 20 MB
  of driver memory Draughts' 2D game held at rest. `present()` of a frame that recorded
  nothing, after frames that did, waits for the GPU and makes the frames' command pools
  again, and the upload queue too once more than its staging went through it since. An
  idle program has little left on the GPU to wait for, and the next frame's recording
  grows the pools back only to what it uses. Not under `GOOSE_NGFX_BENCH`, whose
  timestamps live in the pools.
- **Measured on the M1 Pro**, at rest in a 1280 × 800 window (2560 × 1600 pixels), the
  app's footprint: Draughts' 2D game 309 MB at the first sizes, 167 MB sized from use,
  147 MB drawing into the window's image, 118 MB with the idle trim and the smaller
  chunks, against 115 MB on its gfx build; its 3D game 614, 419, 389, and 315 MB, against
  358 MB. A program that opens ngfx and clears three frames went from 160 MB (138 MB of
  it graphics: 64 MB chunks committed whole, 2 × 16 MB of frame memory, a 32 MB upload
  queue) to 40 MB.
- **All GPU work runs on queue zero.** No program in the acceptance set needs async
  compute, and on M1 NoGraphicsAPI leaves open whether its queues are independent
  engines, so no gain could be measured. Adding it later extends the surface without
  changing it.
- **`update_buffer` takes effect for the whole frame** it is called in, as `update_texture`
  does. Uploads go through `UploadQueue`, flushed before each submission of the frame's
  commands, and earlier only when an upload overlaps one already in the batch. Up to
  eight batches can be pending, so a frame's flushes don't wait for an earlier frame.
  Data that changes between draws goes in `frame_data`.
- **Texture initialization is submitted at once**, in its own command buffer, as
  NoGraphicsAPI's cube example does, so no upload can overtake it.
- **Every color texture can be updated and read back** (`transfer_source |
  transfer_destination`), as in gfx. This may cost compression on some GPUs. Depth
  textures get neither: both backends refuse transfer usage on a combined depth/stencil
  format, and ngfx refuses to update or read back depth anyway.
- **`DEPTH24_STENCIL8` falls back to 32-bit float depth with stencil** where the device
  lacks it, as it always does on Metal, much as gfx's `DEPTH` falls back.

### Synchronization

- **The module records barriers only where it sees both sides; the program states the
  rest** with `ngfx::barrier(before, after)`. The module orders uploads, texture
  creation, read-back, each frame's first pass into anything but the window's image,
  and a pass drawing into a target an earlier pass drew into. It cannot see what
  shaders reach through roots, pointers, and descriptor indices, so it records nothing for that. Independent
  dispatches and passes wait for nothing, which is what NoGraphicsAPI exists for. Hidden
  conservative barriers at every pass and dispatch were tried first: they serialized
  independent work and still missed hazards.
- **The window's image needs no frame boundary barrier.** Its last use, another
  frame's presentation, is ordered before the frame's by acquiring it: Metal's
  `waitForDrawable` before the submission that draws into it, and on Vulkan the
  acquire semaphore NoGraphicsAPI waits on. The headless screen and every other target
  get the barrier, as their last frame's writes may still be in flight.
  `GOOSE_NGFX_SYNC=full` records it anyway.
- **`GOOSE_NGFX_PASS_BARRIER=1` starts each pass with a barrier between render stages**,
  which no data hazard calls for; it is off by default (2026-11-12), to find out
  whether a later macOS still needs it. Without one, the M1 Pro's GPU could hang on
  macOS 26.3.1 with both its vertex and tiling slots busy while another process draws with Metal, and macOS restarts the
  GPU (task 008). Any barrier with a render stage on both sides prevents it, whatever
  it orders: Vertex to Vertex,
  Fragment to Vertex, Fragment to Fragment, and the frame boundary all do, while an
  empty encoder and a barrier with Blit on either side don't. That points at the driver,
  not at an order ngfx misses. The frame boundary would serve, but a frame that draws
  only into the window's image records none. The barrier is from `Stage::vertex` to
  `Stage::vertex | Stage::index_input` with no accesses. It costs about 20 µs a frame
  in `cube` headless, and no measurable time in `mini_minecraft` or `mini_doom`;
  Fragment to Fragment costs the same. The hang was seen on macOS 26.3.1 (25D771280a)
  only, and a native Metal program reproduces it there without ngfx or NoGraphicsAPI.
  It is untested on 26.4 and later, which may not need the barrier.
- **A frame is two submissions when it presents.** The passes before its first pass
  into the window's image go first, then a command buffer that acquires the image, holds
  the rest of the frame, and presents. Only that second submission waits for the image
  (at all commands on Vulkan, after `waitForDrawable` on Metal), so the passes that
  draw into textures don't. A pass there that samples what an earlier pass drew is
  ordered by the program's barrier, as within one command buffer: Vulkan's barriers
  reach across submissions on a queue, and Metal's queue barriers across command
  buffers, as `UploadQueue`'s already rely on.
- **Barrier points are packed `i32` constants**: a NoGraphicsAPI stage mask in bits 0 to 11
  and an access mask in bits 16 to 27, with NoGraphicsAPI's own bit values, combined with
  `|`. Six common points are named (`COMPUTE_WRITE`, `VERTEX_READ`, and so on). A barrier
  inside a pass is a misuse.
- **`GOOSE_NGFX_SYNC=full` puts a full barrier around every pass and dispatch.** A program
  whose output changes under it is missing a barrier. `scripts/run_tests.py` runs every
  test both ways. No validation layer would catch a missing barrier
  through device addresses, so this check is the safety net.
- **`generate_mips` is Goose code in `ngfx.goose`**: a compute dispatch per level,
  reading the level above through the sampled view and writing through a per-level
  storage view (`storage_index(t, mip)`), with a barrier between levels. NoGraphicsAPI
  has no mip generation and leaves it to applications. It supports 2D textures with
  `SAMPLED | STORAGE` and not sRGB formats, which neither backend allows as storage.

### Ports

- **Each port changes only what drawing needs** and prints what the original prints.
- **Data rebuilt every frame moves to `frame_data`**; data that persists stays in buffers.
- **One root per Slang module** (`GPU_ROOT` binds slot 0), so a program whose pipelines
  take different roots compiles one module per root, sharing Slang through a `let` global.
- **ui draws through ngfx in a companion module, `ngfx_ui.goose`**, not in Goose's
  `ui`, which stays unchanged. ui's atlas texture ids are one namespace shared by both
  renderers, which is safe only because a program uses one.
- **`ngfx_ui` draws indexed, with a root per texture.** ui's vertices and indices go
  into frame memory once a frame; each draw command is a `draw_indexed` from its first
  index, and a new root is made only when the texture changes. That is 2 externs per
  draw command and 3 when the texture changes, against gfx ui's 3.

## Goose constraints met on the way

- **An entry point named like an MSL type fails on Metal only.** `half` compiles to SPIR-V,
  then breaks Xcode's Metal compiler; Slang doesn't rename it.
- **Goose structs are packed; a Slang root has a constant buffer's layout.** Since
  NoGraphicsAPI's Metal backend reads roots from the `constant` address space (upstream,
  2026-10-19), a root's size is a multiple of 16 bytes, a `float4` or matrix starts on a
  16-byte boundary and a `float2` on 8, and there are no three-component vectors. Each
  root names its padding as `padN` fields on both sides, which a Goose literal fills with
  `..`. Data a root points to keeps C's layout: a `u64` pointer on an 8-byte boundary,
  `float3` as 12 bytes aligned to 4.
- **By value, a packed Goose struct stands in for a naturally aligned C one** when the
  bytes match and the struct is larger than 16 bytes or integer-only. A layout test of
  an earlier one-to-one binding checked this on arm64; on x64 Windows, ngfx's own structs
  pass the tests under MSVC, but the rule isn't checked in general.

## Open

- Run the tests on Linux on a GPU: Mesa RADV 26.2 or later, or NVIDIA's driver. Mesa's
  lavapipe lacks `VK_EXT_descriptor_heap` and `VK_KHR_shader_untyped_pointers`, even on
  Mesa's main branch, so no CPU driver can stand in.
- Cache compiled Slang modules, keyed on the source, if the roughly 0.2 s per module
  at startup on the Windows test machine starts to matter.
- Uploads on a copy queue, waiting on `UploadQueue::flush()`'s timeline point, would stop
  a frame with uploads from serializing against the previous frame. It needs no surface
  change, and waits for a machine whose queues are independent engines.
- Mipmapped sRGB textures: a UNORM texture with `mutable_format`, an sRGB sampled view,
  and a UNORM storage view, which may cost compression.
- Per-pass barrier hints (`PassDesc.after`), if ports keep writing `barrier(); begin_pass()`.
