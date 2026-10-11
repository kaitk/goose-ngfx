# 004: Tune frame pacing if the benchmark asks for it

Status: todo

ngfx asks Metal for 2 drawables where gfx has 3, and it queues 1 frame where gfx allows 2
(`frames_in_flight` in `native/ngfx_gpu.hpp:199`, as NoGraphicsAPI's cube example has
it). Task 001's subtask 02 has the details as flags 4 and 5, proposals P3 and P8. Start
after task 002, and only if its vsync line in subtask 03's plan fails: ngfx's 95th
percentile frame time over 1.5 times gfx's.

## Acceptance criteria

- [ ] Three drawables on Metal (`desired_swapchain_image_count = 3`), measured against
      two with vsync
- [ ] Only if three drawables aren't enough: `frames_in_flight = 3`, measured. It costs
      16 MB of frame memory and a third command pool
- [ ] The choice and its numbers recorded in `docs/design.md`, or this task cancelled
      with the numbers that show it isn't needed
