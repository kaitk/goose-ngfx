# 03: Plan the benchmark against gfx

Status: todo

Write a benchmark specification that another session can run without making further
decisions. Don't run it in this task. Subtasks 01 and 02 say what is worth measuring.

## Acceptance criteria

- [ ] Workloads: the four ported samples against their gfx originals, a draw-call
      throughput test (many small draws, each with its own root in `frame_data`), and an
      upload throughput test
- [ ] Metrics: main-thread CPU time per frame, GPU time per frame from timestamp queries,
      frame time with and without vsync, and startup time with the Slang compile
      reported separately. If the layer has no timestamp queries, the plan says how to
      add them
- [ ] Conditions: headless and windowed, each run plainly and under
      `GOOSE_NGFX_SYNC=full` to measure what the barrier rule saves. Machines: the M1 Pro
      (Metal 4), the RTX 4090 (Vulkan), and Linux headless
- [ ] Method: warm-up frames, a fixed frame count, the median and spread over repeated
      runs, and machine and driver versions recorded as in
      [design.md](../../docs/design.md#status)
- [ ] Where the harness lives, and how it builds the gfx originals at the pin
- [ ] The result that would show the architecture doesn't hold is stated in advance.
      For example: ngfx is slower than gfx per frame on any sample, or
      `GOOSE_NGFX_SYNC=full` costs nothing measurable
- [ ] A task to run the benchmark exists, numbered after this one
