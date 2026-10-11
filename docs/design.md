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
proposed upstream and moved out instead (Kait and Goose's maintainer, 2026-10-10).
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
1.4.363, slangc 2026.18.2, clang-cl 22.1.3, and Goose `2de6d1d`. The API check, every
test (plainly and under `GOOSE_NGFX_SYNC=full`, run in the compiler), and every sample
(built) pass, headless.

In the fork, the same code also passed on macOS 26 on an Apple M1 Pro (Metal 4). There,
headless, the cube's, Mini Doom's, and the to-do list's screenshots were byte-identical
to the gfx originals'. Mini Minecraft's differed in 36 isolated pixels of nearest-sampled
leaves on Metal, where Slang and Goose's MSL round a texture coordinate differently, and
in one pixel by one step on Vulkan.

| Platform | State |
| --- | --- |
| Windows, Vulkan 1.4 | Tested here on an RTX 4090, headless and windowed. |
| macOS 26, Metal 4 | Tested in the fork on an M1 Pro; this repository's build is untried there. |
| Linux, Vulkan 1.4 | Not built. NoGraphicsAPI is headless-only on Linux, and `CMakeLists.txt` stops there. Needs a little work to build headless. |

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
- **Pipelines are created lazily per set of target formats**, as gfx does, because
  NoGraphicsAPI fixes formats in the pipeline.
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
- **`update_buffer` takes effect for the whole frame** it is called in. Uploads go through
  `UploadQueue`, flushed before each submission of the frame's commands. Data that changes
  between draws goes in `frame_data`.
- **Texture initialization is submitted at once**, in its own command buffer, as
  NoGraphicsAPI's cube example does, so no upload can overtake it.
- **Every texture can be updated and read back** (`transfer_source |
  transfer_destination`), as in gfx. This may cost compression on some GPUs.

### Synchronization

- **The module records barriers only where it sees both sides; the program states the
  rest** with `ngfx::barrier(before, after)`. The module orders uploads, texture
  creation, read-back, the screen copy, each frame's first pass, and a pass drawing into
  a target an earlier pass drew into. It cannot see what shaders reach through roots,
  pointers, and descriptor indices, so it records nothing for that. Independent
  dispatches and passes wait for nothing, which is what NoGraphicsAPI exists for. Hidden
  conservative barriers at every pass and dispatch were tried first: they serialized
  independent work and still missed hazards.
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

- Build and test this repository on macOS with Metal 4, which the code passed in the
  fork.
- Verify on Vulkan on Linux, headless on AMD, which needs `CMakeLists.txt` to build
  there (see [Status](#status)).
- Cache compiled Slang modules, keyed on the source, if the 0.2 s per module at startup
  starts to matter.
- Uploads on a copy queue, waiting on `UploadQueue::flush()`'s timeline point, would stop
  a frame with uploads from serializing against the previous frame. It needs no surface
  change, and waits for a machine whose queues are independent engines.
- Mipmapped sRGB textures: a UNORM texture with `mutable_format`, an sRGB sampled view,
  and a UNORM storage view, which may cost compression.
- Per-pass barrier hints (`PassDesc.after`), if ports keep writing `barrier(); begin_pass()`.
