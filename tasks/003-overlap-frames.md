# 003: Let consecutive frames overlap on the GPU

Status: in-progress

The screen textures now rotate per frame in flight, and the frame's passes are submitted
before acquiring the swapchain image. These changes remove the dependencies identified
in task 001's subtask 02, flags 1 to 3 and proposals P1 and P2. Correctness validation
passes; task 002 still needs to measure the before/after frame times.

The implementation addresses two sources of serialization in the earlier design:

1. Give each frame in flight its own screen and depth texture behind the same handles.
   Skip the frame-boundary barrier when the frame's first pass draws only into this
   slot's screen. The CPU's timeline wait already orders the slot's last use. Find out
   whether Vulkan still needs a memory dependency for the clear, and record the answer.
2. Submit the frame's passes first. Then acquire, copy, and present in a second command
   buffer, so only the copy waits for the image.

## Acceptance criteria

- [x] One screen and depth per frame in flight. `screenshot`, `read_pixels`, and resize
      see the current frame's screen, and the handles don't change
      (`test/ngfx_screen_frames.goose`; resize, which headless runs can't do, replaces
      every texture behind both handles and clears the current one)
- [x] No barrier at the frame boundary in a steady frame, plainly. Under
      `GOOSE_NGFX_SYNC=full` the barrier is still there
- [x] The passes are submitted before the swapchain image is acquired, and only the copy
      waits for it
- [x] Tests and samples pass plainly and under `GOOSE_NGFX_SYNC=full`, with unchanged
      output, on Metal and Vulkan
- [x] The screen decisions in `docs/design.md` updated, including the extra memory: one
      more screen and depth, 8 MB at 1280 x 800
- [ ] Task 002's frame-time numbers rerun for `cube` and `minecraft`, before and after

## Results

On the M1 Pro (Metal 4), 2026-10-11, at Goose `4f23f22`: every test passes plainly and
under `GOOSE_NGFX_SYNC=full`, and each sample prints what it did and saves a screenshot
byte-identical to the one before the change, both ways, headless. The cube and the to-do
list also ran windowed, both ways. With a print in `frame_boundary_barrier`, 30 headless
frames of each sample record it once, for the screen's clear at `open`, and 31 times
under `GOOSE_NGFX_SYNC=full`. The to-do list's ui pass, which loads the screen its
clearing pass drew, records the same-target barrier instead.

Vulkan needs no memory dependency for the clear of a switched screen. `docs/design.md`
("Synchronization") gives the reasoning from the spec and NoGraphicsAPI's backend.

On the RTX 4090 (Vulkan, driver 617.42), 2026-10-11, at Goose `4f23f22` with slangc
2026.18.2: every test passes plainly and under `GOOSE_NGFX_SYNC=full`, with clang-cl,
with MSVC, and built with `--aot`. Each sample prints the same and saves a screenshot
byte-identical to the one `e05b39d`, before tasks 003 to 007, saves, both ways, headless.
The tests and samples also pass under the Khronos validation layer with synchronization
validation (`VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation`,
`VK_KHRONOS_VALIDATION_VALIDATE_SYNC=true`), which reports nothing. Every sample also ran
windowed for 300 frames under the layer, both ways, and the cube, Mini Minecraft, and the
to-do list ran for 1500 frames while `SetWindowPos` resized their windows five times,
again with nothing reported; a screenshot after a resize has the new client size, and
by eye everything renders and resizes well.

`test/ngfx_screen_frames.goose` cleared to 0.5 green and expected 128, which Metal gives
and NVIDIA's Vulkan gives as 127: 0.5 is 127.5 in bytes, halfway between two. The test
now clears to multiples of 0.2, which no rounding splits.

## Not done here

- Task 002's frame-time numbers for `cube` and `minecraft`, before and after: no
  benchmarks were run. Task 002 measures them.
