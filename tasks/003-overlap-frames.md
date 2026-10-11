# 003: Let consecutive frames overlap on the GPU

Status: in-progress

ngfx draws every frame into one screen texture. The barrier at each frame's first
pass orders it after the previous frame's passes and screen copy
(`native/ngfx_draw.cpp:155-160`). The frame's passes also share the submission that waits
for the swapchain image, so none can start until the image is free. On Metal, gfx's frames
overlap where ngfx's can't. Task 001's subtask 02 has the details as flags 1 to 3,
proposals P1 and P2.

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
- [ ] Tests and samples pass plainly and under `GOOSE_NGFX_SYNC=full`, with unchanged
      output, on Metal and Vulkan (Metal done; see below)
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

## Needs Vulkan

- Tests and samples, plainly and under `GOOSE_NGFX_SYNC=full`, on Windows or Linux.
- A windowed run on Windows, which is the only Vulkan platform that presents, to exercise
  the second submission and its acquire.

## Not done here

- Task 002's frame-time numbers for `cube` and `minecraft`, before and after: no
  benchmarks were run. Task 002 measures them.
