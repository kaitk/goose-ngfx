# 02: Compare the code with gfx's

Status: done

Read `native/` and `ngfx.goose` beside `goose_gfx` at the ref Goose blesses
(`~/.goose/pkg/github.com/aardappel/goose_gfx`). For each, follow one frame of each
ported sample and list the CPU work and the GPU work outside the program's own passes.
CPU work covers allocations, map and unmap, locks, `UploadQueue` and `DeleteQueue`
traffic, command buffers, submissions, and waits.

## Acceptance criteria

- [x] A table for each sample comparing ngfx's per-frame and per-draw work with gfx's,
      with file:line references to both
- [x] Every place where ngfx does more than gfx for the same sample is flagged, with a
      verdict: inherent to NoGraphicsAPI, a cost of a decision in subtask 01, or a fix
- [x] The fixes are listed as [follow-ups](#follow-ups); implementation is separate
      from this review

## Method

This historical review was written on 2026-10-11 without GPU runs.
File and line references describe the snapshot recorded in `4200991`; follow-ups
record later changes.
See [the design](../../docs/design.md) for current behavior. References use these roots:

| Prefix | Path |
| --- | --- |
| (none) | this repository |
| `nga/` | `third_party/NoGraphicsAPI/` (the backend in `src/`, the utility in `utility/src/`) |
| `gfx/` | `~/.goose/pkg/github.com/aardappel/goose_gfx/v1/` |
| `sdl/` | `gfx/third_party/SDL/src/gpu/`, the SDL that gfx links |
| `orig/` | `samples/` in Goose at `4f23f22` |

A steady-state frame is one with no resize, no new ui atlas, no chunk rebuild, and no
screenshot. "Externs" counts the graphics calls a frame makes across the extern
boundary; input calls are the same in both and left out. Each port's Goose code outside
drawing is the original's, so only the drawing differs.

## Fixed costs per frame

### ngfx

`ngfx::frame()` (`ngfx.goose:329-333`) calls `ngfx_frame` and `misuse_count`, as gfx's
does. `ngfx_frame` (`native/ngfx_platform.c:416-424`) ends the frame in
`ngfx_gpu_next_frame` (`native/ngfx_device.cpp:310-336`):

1. Windowed only: `acquire` the window's image. On Vulkan this waits on the present
   fence of the image used two frames ago, then calls `vkAcquireNextImageKHR` and
   records a layout barrier (`nga/src/NoGraphicsAPI.cpp:2487-2560`). On Metal it calls
   `nextDrawable`, which blocks when both drawables are in use
   (`nga/src/NoGraphicsAPIMetal.mm:1421-1437`).
2. Windowed only: the screen copy (`native/ngfx_device.cpp:98-115`): one barrier, one
   render pass, `bind_pso`, 16 bytes of frame memory, and a 3-vertex draw.
3. `submit_frame_commands` (`native/ngfx_device.cpp:159-171`): `UploadQueue::flush`,
   which returns at once when nothing was uploaded (`nga/utility/src/upload_queue.cpp:209`),
   then one `submit` or `submit_and_present`. Vulkan: one `vkQueueSubmit2`, plus
   `vkQueuePresentKHR`. Metal: `waitForDrawable`, one `commit`, and two `signalEvent`s
   (`nga/src/NoGraphicsAPIMetal.mm:1383-1457`).
4. Waits on the timeline for frame N-1 (`native/ngfx_device.cpp:328`), as
   `nga/examples/cube/cube.cpp:160-161` does.
5. Resets the next slot's command pool and frame memory, ticks the `DeleteQueue` (an
   early return when empty, `nga/utility/src/delete_queue.cpp:21-28`), and reclaims
   upload batches.
6. Begins the next command buffer and binds both descriptor heaps
   (`native/ngfx_device.cpp:35-43`).

The frame's first `begin_pass` records the frame-boundary barrier
(`native/ngfx_draw.cpp:370-378`). A later pass into a target an earlier pass drew into
records the same-target barrier (`native/ngfx_draw.cpp:379-386`). On Vulkan each barrier
is one `vkCmdPipelineBarrier2` with a global memory barrier
(`nga/src/NoGraphicsAPI.cpp:1393-1408`). On Metal each one opens a compute encoder,
records `barrierAfterStages`, and ends the encoder
(`nga/src/NoGraphicsAPIMetal.mm:1558-1572`, `:498-508`).

Steady state allocates nothing: the pending-release and written-target vectors keep their
capacity, and frame memory is a bump allocator over one mapped heap
(`native/ngfx_resources.cpp:353-369`). There are no locks. Every extern checks the main
thread with `std::this_thread::get_id()` (`native/ngfx_platform.c:83-92`).

A draw (`native/ngfx_draw.cpp:478-509`) checks the pass, finds the pipeline slot, scans
its variants for the pass's targets, and binds the PSO and depth state when they change
(`:80-96`). NoGraphicsAPI then pushes the 8-byte root pointer and draws: on Vulkan,
`vkCmdPushDataEXT` and `vkCmdDraw` (`nga/src/NoGraphicsAPI.cpp:3664-3674`, `:3825-3846`,
with `vkCmdBindIndexBuffer3KHR` per indexed draw); on Metal, `setAddress` on the argument
table and the draw (`nga/src/NoGraphicsAPIMetal.mm:1817-1858`).

### gfx

`gs_gfx_frame` (`gfx/src/gfx/gfx_device.c:604-612`) presents and submits:

1. `gfx_present` (`gfx/src/gfx/gfx_device.c:488-511`) calls
   `SDL_WaitAndAcquireGPUSwapchainTexture`, which waits on the fence of frame N-2
   (`sdl/vulkan/SDL_gpu_vulkan.c:10216`, `sdl/metal/SDL_gpu_metal.m:3908`), then acquires
   (`vkAcquireNextImageKHR` at `:10242`, or `nextDrawable` at `SDL_gpu_metal.m:3933`).
   It then blits the screen: `vkCmdBlitImage` with layout transitions on Vulkan
   (`sdl/vulkan/SDL_gpu_vulkan.c:9336-9420`), a render pass with SDL's blit pipeline on
   Metal (`sdl/metal/SDL_gpu_metal.m:3081`).
2. `gfx_submit` (`gfx/src/gfx/gfx_device.c:159-164`): SDL's submit takes `submitLock`,
   submits and presents, polls `vkGetFenceStatus` on every submitted command buffer and
   cleans those done, scans the allocator for defragmentation, and runs pending destroys
   (`sdl/vulkan/SDL_gpu_vulkan.c:10816-10990`). Metal's does the same cleanup scan
   (`sdl/metal/SDL_gpu_metal.m:4066-4120`).
3. The next frame's first call acquires a command buffer from SDL's pool under a lock
   (`gfx/src/gfx/gfx_device.c:150-157`, `sdl/vulkan/SDL_gpu_vulkan.c:9674`).

Each render pass (`gfx/src/gfx/gfx_draw.c:18-113`) looks up a `VkRenderPass` and a
framebuffer in hash tables under locks, and transitions every attachment to its
attachment layout at the start and back at the end
(`sdl/vulkan/SDL_gpu_vulkan.c:7888-8100`, `:8217-8250`). A clearing pass sets `cycle`
(`gfx/src/gfx/gfx_draw.c:59`, `:94`), so SDL gives the screen and depth fresh textures
while an earlier frame still uses them (`sdl/vulkan/SDL_gpu_vulkan.c:6103-6113`). Every
bind is tracked per command buffer with a linear scan and an atomic increment
(`sdl/vulkan/SDL_gpu_vulkan.c:2395-2410`). On Metal, SDL leaves hazards to Metal's
resource tracking and records no barriers.

A draw (`gfx/src/gfx/gfx_draw.c:323-360`) checks every slot the pipeline's shaders read.
On Vulkan, after any binding or uniform change, SDL then fetches descriptor sets, calls
`vkUpdateDescriptorSets`, and binds four sets with dynamic offsets
(`sdl/vulkan/SDL_gpu_vulkan.c:5167-5473`). A uniform push is a `memcpy` into a pooled
ring (`sdl/vulkan/SDL_gpu_vulkan.c:7803-7886`). An `update_buffer` creates a transfer
buffer, maps it, copies, records a copy pass, and releases the buffer
(`gfx/src/gfx/gfx_resources.c:103-127`). On Vulkan each transfer buffer is a new
`VkBuffer` with a dedicated `vkAllocateMemory` under `allocatorLock`
(`sdl/vulkan/SDL_gpu_vulkan.c:7029-7041`, `:1985-1991`). On Metal it is a new
`MTLBuffer`.

### Frame pacing

ngfx waits for frame N-1 right after submitting frame N, so while the CPU records N+1 the
GPU has at most frame N queued. gfx waits for frame N-2 before submitting N, so two
frames can be queued. On Metal, ngfx asks for 2 drawables
(`nga/src/NoGraphicsAPIMetal.mm:708`, default `nga/include/NoGraphicsAPI/NoGraphicsAPI.hpp:466`),
and SDL keeps `CAMetalLayer`'s default of 3. On Vulkan both swapchains have about 2
images.

ngfx's submission waits for the window's image at all commands
(`nga/src/NoGraphicsAPI.cpp:3449-3455`), and on Metal the queue waits for the drawable
before the commit (`nga/src/NoGraphicsAPIMetal.mm:1447`). The frame's own passes share
that submission, so none of them starts before the image is free. SDL waits at color
attachment output (`sdl/vulkan/SDL_gpu_vulkan.c:10837`).

Headless, ngfx still waits for frame N-1 every frame. gfx never waits headless: SDL's
submit doesn't block, so its headless frame rate measures how fast it records and submits.

## cube

ngfx `samples/cube.goose:115-139`; gfx `orig/27_gfx_cube.goose:117-144`.

| Work | ngfx | gfx |
| --- | --- | --- |
| Externs per frame | 11: `frame` (2), `screen_size`, `begin_screen` (3), `bind`, `address`, `frame_data`, `draw_indexed`, `end_pass` | 12: `frame` (2), `screen_size`, `begin_screen` (3), `bind`, `bind_vertex_buffer`, `bind_index_buffer`, `push_uniforms`, `draw_indexed`, `end_pass` |
| Per-frame data | 136-byte root into frame memory (`cube.goose:132-134`, `ngfx_resources.cpp:361-367`) | 128-byte uniform push into SDL's ring (`27_gfx_cube.goose:139`, `gfx_draw.c:251-281`) |
| Uploads, deletes, allocations | None | None |
| Command buffers, submissions | 1 and 1 | 1 and 1 |
| Waits | Timeline, frame N-1 (`ngfx_device.cpp:328`) | Fence, frame N-2 (`SDL_gpu_vulkan.c:10216`) |
| Passes | Screen, then the copy | Screen, then the blit |
| Barriers, Vulkan | 3: frame boundary, copy, acquire | About 8: 2 per attachment for the pass, the blit's transitions, acquire |
| Barriers, Metal | 2, each an empty compute encoder | None |
| Pipeline lookup | Variant scan at the draw (`ngfx_draw.cpp:84-88`) | Variant scan at `bind` (`gfx_draw.c:137`) |
| Descriptor writes | None | Vulkan: sets fetched, written, and bound at the draw (`SDL_gpu_vulkan.c:5167-5473`) |
| Per draw, native | Slot and variant lookups, buffer lookup, push root, bind indices, draw | Slot checks, vertex buffer bind, descriptor sets with dynamic offset, draw |

## ui_todo

ngfx `samples/ui_todo.goose:176-178` and `ngfx_ui.goose:113-146`; gfx
`orig/29_ui_todo.goose:176-178` and `gfx/ui.goose:1900-1938`. D is the frame's ui draw
commands.

| Work | ngfx | gfx |
| --- | --- | --- |
| Externs per frame | 14 + 4D: `frame` (2), `begin_screen` (3), `end_pass`, `open_count`, `frame_data` (2), `texture_info`, `index(sampler)`, `begin_pass`, `bind`, `end_pass` | 16 + 3D: `frame` (2), `begin_screen` (3), `end_pass`, `open_count`, `update_buffer` (2), `texture_info`, `begin_pass`, `bind`, two buffer binds, `push_uniforms`, `end_pass` |
| Externs per draw | 4: `scissor`, `index(texture)`, `frame_data` (root), `draw` (`ngfx_ui.goose:137-141`) | 3: `scissor`, `bind_texture`, `draw_indexed` (`ui.goose:1931-1933`) |
| Per-frame data | Vertices and indices copied into frame memory, read in place (`ngfx_ui.goose:120-121`) | Two `update_buffer`s: two transfer buffers (Vulkan: two dedicated allocations), two copy passes with barriers (`ui.goose:1913-1914`) |
| Per-draw data | 40-byte root | Texture bind; one uniform push per pass |
| Command buffers, submissions | 1 and 1 | 1 and 1 |
| Passes | Clear, ui, copy | Clear, ui, blit |
| Barriers, Vulkan | 4: boundary, same target (`ngfx_draw.cpp:379-386`), copy, acquire | About 12: 2 per attachment per pass, copy-pass buffer barriers, blit, acquire |
| Barriers, Metal | 3 empty compute encoders | None |
| Descriptor writes | None | Vulkan: one set written per draw for the texture |
| Vertex shading | One invocation per index: non-indexed draws that read indices in the shader (`ngfx_ui.goose:58`) | Indexed draws, with post-transform reuse |

## mini_minecraft

ngfx `samples/mini_minecraft.goose:1585-1645`; gfx `orig/30_mini_minecraft.goose:1561-1626`.
C is the chunks drawn, at most 25.

| Work | ngfx | gfx |
| --- | --- | --- |
| Externs per frame | 21 + 3C: `frame` (2), `screen_size`, `frame_data` (hud, debris), `root(scene)`, `index` (2), `begin_screen` (3), three binds, sky, debris, and hud roots and draws (6), `end_pass` | 24 + 3C: `frame` (2), `screen_size`, `buffer_size` and `update_buffer` (hud), `update_buffer` (debris), `begin_screen` (3), three binds, `bind_texture` (2), uniforms (4), sky, debris, and hud draws with binds (5), `end_pass` |
| Externs per chunk | 3: `address`, `frame_data` (24-byte root), `draw_indexed` (`:1630-1632`) | 3: `bind_vertex_buffer`, `bind_index_buffer`, `draw_indexed` (`:1613-1615`) |
| Per-frame data | HUD and debris vertices and a 384-byte `Scene` into frame memory | HUD and debris through `update_buffer`: up to two transfer buffers and copy passes (`:1568-1580`) |
| Rebuild frames | Per chunk: 2 releases (a heap-allocated slot each, into the `DeleteQueue`), 2 `create_buffer`s (heap suballocation, a zeroed vector, an `UploadQueue` copy). One extra submission for the frame, with two all-commands barriers | Per chunk: 2 releases, 2 `create_buffer`s, each with a transfer buffer and a command buffer submitted at once: 2 extra submissions per chunk (`gfx_resources.c:81-98`) |
| Command buffers, submissions | 1 and 1; 2 on a rebuild frame | 1 and 1; 1 + 2 per rebuilt chunk |
| Barriers, Vulkan | 3 | About 8, plus copy-pass buffer barriers |
| Barriers, Metal | 2 empty compute encoders; 4 on a rebuild frame | None |
| Descriptor writes | None | Vulkan: sets rebound with dynamic offsets per chunk |

## mini_doom

ngfx `samples/mini_doom.goose:1529-1557`; gfx `orig/31_mini_doom.goose:1511-1539`.

| Work | ngfx | gfx |
| --- | --- | --- |
| Externs per frame | 21: `frame` (2), `screen_size`, `frame_data` (2), `index` (4), `root` (2), `begin_screen` (3), `viewport` (2), `bind` (2), `draw` (2), `end_pass` | 23: `frame` (2), `screen_size`, `buffer_size` and `update_buffer` (4), `begin_screen` (3), `viewport` (2), `bind` (2), `bind_texture` (2), `bind_vertex_buffer` (2), uniforms (2), `draw` (2), `end_pass` |
| Per-frame data | The rebuilt world mesh (40 bytes a vertex) and the HUD copied into frame memory, read in place (`:1532`, `:1537`) | Both through `update_buffer` (`:1395-1400`): two transfer buffers the size of the mesh and HUD (Vulkan: two dedicated allocations), two GPU copies into vertex buffers |
| Command buffers, submissions | 1 and 1 | 1 and 1; plus 1 when a buffer grows |
| Barriers, Vulkan | 3 | About 8, plus copy-pass buffer barriers |
| Barriers, Metal | 2 empty compute encoders | None |
| Descriptor writes | None | Vulkan: sets written and bound per draw |
| GPU copies outside passes | The screen copy | The two buffer copies and the blit |

## Flags

### Where ngfx does more

1. **Barriers on Metal are compute encoders.** ngfx records 2 barriers a steady frame (frame
   boundary, screen copy) and 3 in ui_todo. On Metal each is an empty compute encoder
   with a queue barrier; gfx on Metal records none. Verdict: the encoder is inherent to
   NoGraphicsAPI (`nga/src/NoGraphicsAPIMetal.mm:1558-1572`); the barriers are the cost
   of the decisions "the module records barriers only where it sees both sides" and "the
   screen is an offscreen RGBA8 texture".
2. **One screen serializes consecutive frames on the GPU.** The frame-boundary barrier
   orders frame N+1's first pass after frame N's passes and copy
   (`native/ngfx_draw.cpp:155-160`). gfx clears with `cycle`, so SDL renders frame N+1
   into another texture, and on Metal, whose hazard tracking sees no shared resource,
   consecutive frames can overlap. On Vulkan, SDL's layout barriers order against all
   earlier commands too, so both serialize there. Verdict: cost of the decision "the
   screen is an offscreen RGBA8 texture", with a fix ([P1](#follow-ups)).
3. **The whole frame waits for the window's image.** The frame's passes share the
   submission that waits for the image at all commands (Vulkan) or after
   `waitForDrawable` (Metal); gfx waits at color output. Verdict: inherent to
   NoGraphicsAPI's `submit_and_present`, with a fix in ngfx ([P2](#follow-ups)).
4. **Two drawables on Metal**, where gfx has 3. With vsync, `nextDrawable` blocks sooner
   and a slow frame can't be absorbed. Verdict: a fix, NoGraphicsAPI's default unchanged
   ([P3](#follow-ups)).
5. **One frame queued, where gfx allows two.** ngfx waits for N-1 after submitting N
   (`native/ngfx_device.cpp:327-328`). This lowers latency and leaves less slack for a
   CPU spike. Verdict: inherent to NoGraphicsAPI's examples (`frames_in_flight` 2 in
   `native/ngfx_gpu.hpp:199`, as `nga/examples/cube/cube.cpp:160-161`). Change it only
   if the benchmark shows a cost ([P8](#follow-ups)).
6. **A frame with uploads gets a second submission and two all-commands barriers**
   (`nga/utility/src/upload_queue.cpp:153`, `:211`), so its uploads wait for all earlier
   work, including the previous frame, and everything after waits for them. In the
   samples, only Mini Minecraft's rebuild frames upload. A second upload overlapping an
   earlier one in the same frame flushes a batch (`native/ngfx_device.cpp:143-157`); with
   2 pending batches allowed (`native/ngfx_device.cpp:247`), a third batch in one frame
   makes the CPU wait in `UploadQueue::begin` (`nga/utility/src/upload_queue.cpp:147-151`).
   Verdict: the barriers are the cost of the decision "`update_buffer` takes effect for
   the whole frame", and the copy queue in design.md's Open list addresses them; the
   CPU wait is a fix ([P4](#follow-ups)).
7. **`create_buffer` copies the whole buffer once more than gfx.** It builds a zeroed
   `std::vector` of the full size, copies the data in, then copies it to staging
   (`native/ngfx_resources.cpp:297-299`); gfx writes data and zeros straight into the
   mapped transfer buffer (`gfx/src/gfx/gfx_resources.c:115-118`). This runs on Mini
   Minecraft's rebuild frames. Verdict: a fix ([P5](#follow-ups)).
8. **`update_texture` flushes uploads before and after** (`native/ngfx_resources.cpp:410-412`):
   one or two extra submissions a call, where gfx records the copy in the frame. Only
   startup and new ui atlases hit it. Verdict: a fix, low priority
   ([P6](#follow-ups)).
9. **The pipeline is looked up at every draw** (`native/ngfx_draw.cpp:84-88`), where gfx
   looks it up at `bind` (`gfx/src/gfx/gfx_draw.c:137`). Verdict: a fix
   ([P6](#follow-ups)).
10. **Every extern checks the thread** (`native/ngfx_platform.c:83-92`); gfx checks only
    that the device is open (`gfx/src/gfx/gfx_device.c:44-47`). Verdict: cost of the
    decision to reject calls from a `thread_fn` (design.md, "Why a separate repository"),
    whose compile-time half is `main_thread_only`; the run-time check could leave the
    draw path ([P6](#follow-ups)).
11. **ngfx_ui makes one more extern and one 40-byte root per draw** (`ngfx_ui.goose:137-141`)
    than gfx's texture bind (`gfx/ui.goose:1932`). Only `first` and the texture change
    between draws. Verdict: cost of the decision "drawing takes roots and GPU addresses",
    with a fix ([P7](#follow-ups)).
12. **ngfx_ui shades one vertex per index.** Its draws aren't indexed, because
    `draw_indexed` takes a `Buffer` and the frame's indices are frame memory; a quad
    costs 6 vertex invocations instead of about 4. NoGraphicsAPI's `draw_indexed` takes
    any `GpuRange` (`nga/src/NoGraphicsAPI.cpp:3832`). Verdict: cost of ngfx's surface,
    with a fix ([P7](#follow-ups)).

### Where ngfx does less

- **No transfer buffers.** gfx allocates one per `update_buffer` (on Vulkan a dedicated
  `vkAllocateMemory`) and records a copy pass: 2 a frame in ui_todo and Mini Doom, 1 to 2
  in Mini Minecraft. ngfx copies per-frame data once into mapped device-local memory and
  the GPU reads it in place, with no GPU copy.
- **No descriptor work per draw.** SDL on Vulkan writes and binds descriptor sets with
  dynamic offsets per draw; ngfx pushes one pointer.
- **No resource tracking, render-pass caches, or locks.** SDL scans and refcounts every
  bind, looks up render passes and framebuffers under locks, and scans submitted command
  buffers at each submit.
- **Fewer barriers on Vulkan**: 3 or 4 a frame, against SDL's 2 per attachment per pass
  plus copies and the blit.
- **Fewer submissions on Mini Minecraft's rebuild frames**: one batch, against 2 per
  rebuilt chunk.
- **Less Goose math**: ngfx's matrix `mul` transposes once (`ngfx.goose:813-818`); gfx's
  gathers a row 16 times (`gfx/gfx.goose:716-722`).

### Same work, to measure

- Vertex pulling: the cube, Mini Minecraft, and Mini Doom fetch vertices through root
  pointers where gfx uses fixed-function vertex input. Inherent to NoGraphicsAPI; the
  GPU cost is unknown on both backends.
- The screen copy: a fullscreen draw in ngfx; `vkCmdBlitImage` in gfx on Vulkan and a
  fullscreen draw on Metal.
- Every texture having transfer usage costs nothing more than gfx: SDL's Vulkan backend
  adds both transfer bits to every image (`sdl/vulkan/SDL_gpu_vulkan.c:5748`), and
  Metal has no such usage.

## Follow-ups

- [x] **P1. A screen per frame in flight** (task 003, implemented; measurement pending).
  Each slot has its own screen and depth behind the same handles. A frame starting
  with a clear of renewed screens skips the frame-boundary barrier: the CPU timeline
  wait orders the slot's last use on both backends, including Vulkan's memory
  dependency. The reasoning is in the design's Synchronization section. This costs
  one more screen and depth (8 MB at 1280 x 800). Flags 1 and 2.
- [x] **P2. Submit the frame before acquiring** (task 003, implemented). The passes are
  submitted first, then acquire, copy, and present use a second command buffer, so only
  the copy waits for the image.
  Costs one submission a frame. Flag 3.
- **P3. Three drawables on Metal** (task 004), passing `desired_swapchain_image_count = 3`, if the
  benchmark shows vsync stalls. Flag 4.
- [x] **P4. More pending upload batches** than frames in flight, so overlapping updates in
  one frame never make the CPU wait. Flag 6. Done in `7c04663`.
- [x] **P5. `create_buffer` without the intermediate vector**: upload the data, then the
  zeros, straight into staging. Flag 7. Done in `71ec02b`.
- [x] **P6. Trim the hot paths**: resolve the PSO once per bind and pass, drop the run-time
  thread check from draws and `frame_data` if `main_thread_only` covers them, and flush
  in `update_texture` only when staging needs it. Flags 8 to 10. Done: the flushes in
  `7c04663`, the rest in `329e970`.
- [x] **P7. ngfx_ui: one root per texture, and indexed draws** (task 007).
  `draw_indexed` takes an index range from frame memory. `SV_VertexID` includes
  `first_vertex` on Metal but excludes it on Vulkan, so the bridge uses indexed draws
  with `first_index` instead. Flags 11 and 12.
- **P8. Three frames in flight** (task 004), only if the benchmark shows ngfx's frame times vary
  more than gfx's under load. Costs 16 MB of frame memory and a third command pool.
  Flag 5.

## For the benchmark

Subtask 03 should make sure it measures these:

- GPU time and frame throughput on the M1 Pro without vsync, windowed: flags 1 to 3 cost
  most there, where gfx's frames can overlap.
- Frame-time spread with vsync on both machines: flags 3 to 5.
- Main-thread CPU time in ui_todo and Mini Doom on Vulkan, where gfx allocates transfer
  buffers every frame.
- Mini Minecraft with scripted mining, to cover rebuild frames (flags 6 and 7).
- Headless runs with GPU timestamps or a closing `flush`: gfx doesn't wait headless, so
  frame rate alone compares unlike things.
- In the draw-call test, vertex pulling against vertex input and indexed against
  non-indexed draws.
