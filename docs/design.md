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
a CMake project for the native part), and each compiler change has a counterpart here,
recorded in [goose-findings.md](goose-findings.md):

| In the fork | Here |
|---|---|
| `embed_slang` compiled Slang into the program | `ngfx::slang` compiles it when the program runs |
| `goose file.goose` ran ngfx programs with TinyCC | The same, through the package's JIT library |
| The compiler rejected ngfx calls from a `thread_fn` | The same, from `main_thread_only` in `ngfx.build` |
| `--ngfx-link` printed the link inputs | `goose build` links the package's native part |
| C names `gs_ngfx_*` | `ngfx_*`: `gs_` is Goose's |

## Status

Built and tested on Windows 11 with Vulkan: an NVIDIA RTX 4090, driver 617.42, Vulkan SDK
1.4.363, slangc 2026.18.2, clang-cl 22.1.3 and MSVC 19.51, and Goose `2de6d1d`. The API
check, every test (plainly and under `GOOSE_NGFX_SYNC=full`, run in the compiler and
built), and every sample (built) pass, headless. At Goose `4f23f22`, the README's quick
start, from fresh clones and an empty `GOOSE_HOME`, passes the API check, every test, and
every sample, with clang-cl and, tests built, with MSVC.

Built and tested on macOS 26.3 with Metal 4: an Apple M1 Pro, Xcode 26.4 (Apple clang 21),
slangc 2026.18.3, and Goose `2de6d1d`. The API check, every test (plainly and under
`GOOSE_NGFX_SYNC=full`, run in the compiler and built), and every sample (built) pass,
headless. A program outside the repository that imports the package from git runs in
the compiler and built, and the to-do list and Mini Minecraft, built that way, print
what they print here. At Goose `4f23f22`, the README's quick start, from fresh clones
and an empty `~/.goose`, passes the API check, every test, and every sample.

On the Mac, headless, the cube's, Mini Doom's, and the to-do list's screenshots are
byte-identical to those of Goose's gfx originals. Mini Minecraft's differs in 48
isolated pixels of nearest-sampled leaves, where Slang and Goose's MSL round a texture
coordinate differently. In the fork, it differed in 36 such pixels on Metal, and in one
pixel by one step on Vulkan.

| Platform | State |
| --- | --- |
| Windows, Vulkan 1.4 | Tested here on an RTX 4090, headless and windowed. |
| macOS 26, Metal 4 | Tested here on an M1 Pro, headless, and windowed in a short run. |
| Linux, Vulkan 1.4 | Headless only. Builds and runs in WSL (Ubuntu 26.04, gcc 15), where no driver has `VK_EXT_descriptor_heap`: the tests that need no device pass, and the rest skip. Untried on a GPU. |

## What it costs

These choices follow NoGraphicsAPI rather than the rest of Goose. Each is deliberate.

- **A separate module, not a gfx backend.** NoGraphicsAPI needs Metal 4 or Vulkan 1.4 on
  recent GPUs and drivers, and can't present on Linux. Under gfx it would either hold
  gfx's API to what SDL_GPU and NoGraphicsAPI can both do, or drop platforms gfx supports.
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
- **Duplication with gfx and ui.** The platform half of `native/ngfx_platform.c` is a
  copy of gfx's `src/gfx/gfx_device.c` with `ngfx_` names, and `ngfx_ui.goose` repeats
  ui's 90-line input bridge. Sharing either would change Goose's gfx package.

## How it is built

The layer follows the conventions of Goose's native layers (its `docs/design/physics.md`):
packed C structs, `let` constants, `ngfx_` names, and one X-macro list (`NGFX_API` in
`native/ngfx_api.h`) that expands into the prototypes and that `scripts/api_check.py`
compares with the `extern` declarations in `ngfx.goose`.

- `native/ngfx_platform.c`: window, input, and time over SDL3, from gfx. The package
  builds its own SDL3, at the commit and with the options of Goose's gfx package, since
  two packages can't share C. A program that also imports `audio` or `ui` links two
  identical SDL archives, and the linker takes one; a `goose run` loads one per package
  ([findings](goose-findings.md#two-packages-cant-share-a-c-library)).
- `native/ngfx_device.cpp`, `ngfx_resources.cpp`, `ngfx_draw.cpp`, `ngfx_gpu.hpp`: the GPU
  half over NoGraphicsAPI and NoGraphicsAPIUtility.
- `native/ngfx_slang.cpp`: `ngfx::slang`.
- `native/ngfx_screen.slang`, `ngfx_mips.slang`: the layer's own shaders, compiled when
  the layer is built and embedded as byte arrays (`cmake/bin2h.cmake`).
- `CMakeLists.txt` builds SDL, NoGraphicsAPI, the shaders, and the layer, as the target
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
- **The result comes back in two calls**, the size and then the bytes, because a library
  can't append to a Goose builder
  ([findings](goose-findings.md#a-c-library-cant-append-to-a-goose-builder)).
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
- **The screen is an offscreen RGBA8 texture**, copied to the swapchain by a fullscreen
  draw at `frame()`. NoGraphicsAPI gives the swapchain image only as a render target, and
  this is what makes `screenshot`, `read_pixels`, and headless mode possible. The copy
  does no sRGB conversion, as gfx's swapchain does.
- **The screen and its depth have a texture per frame in flight behind each handle**, so
  consecutive frames can overlap on the GPU, as gfx's do on Metal through SDL's
  `cycle`. A pass that clears the screen or its depth as the frame's first use of it
  switches the handle to the texture used longest ago. Any other first use (a pass that
  loads, `index`, read-back) keeps the texture, so what a frame doesn't clear holds what
  the last frame drew, as in gfx, and `screenshot` after `frame()` sees the last frame.
  `index(screen())` holds only for the frame it is taken in. It costs one more screen
  and depth: 8 MB at 1280 x 800.
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
- **The name is `ngfx`.** It reads as gfx on NoGraphicsAPI. `gfx2` would presume it
  replaces gfx, `gpu` is NoGraphicsAPI's C++ namespace, and `nogfx` reads as "no graphics".
- `CULL_BACK` with counterclockwise front faces is NoGraphicsAPI's `CullMode::clockwise`,
  as in its cube example. `COMPARE_*` keep gfx's values, and the layer converts.
- `GOOSE_GFX_HEADLESS` makes `ngfx::open` headless too, as it does gfx's.

### Memory and submission

- **Memory is fixed-size**, suballocated with NoGraphicsAPIUtility's allocators: buffers
  from 64 MB chunks (larger ones get their own heap), textures from one 512 MB heap, 16 MB
  of frame memory per frame in flight (running out is a misuse), 8192 texture and 1024
  sampler descriptors. Releases wait in a `DeleteQueue`.
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
  creation, read-back, the screen copy, each frame's first pass into anything but a
  freshly switched screen, and a pass drawing into a target an earlier pass drew into. It cannot see what shaders reach through roots,
  pointers, and descriptor indices, so it records nothing for that. Independent
  dispatches and passes wait for nothing, which is what NoGraphicsAPI exists for. Hidden
  conservative barriers at every pass and dispatch were tried first: they serialized
  independent work and still missed hazards.
- **A switched screen needs no barrier, on either backend.** The texture's last frame
  finished before the CPU recorded this one: `ngfx_gpu_next_frame` waits on the
  timeline for it. On Vulkan, NoGraphicsAPI signals the timeline at
  `VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT` (`submit_commands` in `NoGraphicsAPI.cpp`), and
  the spec gives a semaphore signal a first access scope of "all memory access
  performed by the device" ("Semaphore Signaling"), so that frame's writes are made
  available. A later `vkQueueSubmit2` orders all its commands after everything that
  happened before it on the host, with a second access scope of all device access
  ("Host Write Ordering Guarantees"), and the host wait happened before it. That covers
  the clear's write after the old writes and the copy's read. The texture stays in
  `VK_IMAGE_LAYOUT_GENERAL`, so there is no layout transition to order. NoGraphicsAPI's
  own frame memory is reused the same way, after a timeline wait with no barrier
  (`examples/cube`). On Metal, the shared event's completion covers it, as
  NoGraphicsAPI's `barrier` notes for host visibility. `GOOSE_NGFX_SYNC=full` records the
  frame boundary's barrier anyway.
- **A frame is two submissions when it presents.** The passes go first, then a command
  buffer that acquires the window's image, copies the screen into it, and presents. Only
  that second submission waits for the image (at all commands on Vulkan, after
  `waitForDrawable` on Metal), so the frame's passes don't. The copy's barrier orders
  it after the passes, which come earlier in submission order: Vulkan's barriers reach
  across submissions on a queue, and Metal's queue barriers across command buffers, as
  `UploadQueue`'s already rely on.
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
- **Goose structs are packed; Slang structs have C layout.** A root spells C's padding
  with `pad n`: a `u64` pointer on an 8-byte boundary, `float3` as 12 bytes aligned to 4.
- **By value, a packed Goose struct stands in for a naturally aligned C one** when the
  bytes match and the struct is larger than 16 bytes or integer-only. A layout test of
  an earlier one-to-one binding checked this on arm64; on x64 Windows, ngfx's own structs
  pass the tests under MSVC, but the rule isn't checked in general.

## Open

- Run the tests on Linux on a GPU: Mesa RADV 26.2 or later, or NVIDIA's driver. Mesa's
  lavapipe lacks `VK_EXT_descriptor_heap` and `VK_KHR_shader_untyped_pointers`, even on
  Mesa's main branch, so no CPU driver can stand in.
- Cache compiled Slang modules, keyed on the source, if the 0.2 s per module at startup
  starts to matter.
- Uploads on a copy queue, waiting on `UploadQueue::flush()`'s timeline point, would stop
  a frame with uploads from serializing against the previous frame. It needs no surface
  change, and waits for a machine whose queues are independent engines.
- Mipmapped sRGB textures: a UNORM texture with `mutable_format`, an sRGB sampled view,
  and a UNORM storage view, which may cost compression.
- Per-pass barrier hints (`PassDesc.after`), if ports keep writing `barrier(); begin_pass()`.
