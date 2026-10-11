# 02: Compare the code with gfx's

Status: todo

Read `native/` and `ngfx.goose` beside `goose_gfx` at the ref Goose blesses
(`~/.goose/pkg/github.com/aardappel/goose_gfx`). For each, follow one frame of each
ported sample and list the CPU work and the GPU work outside the program's own passes.
CPU work covers allocations, map and unmap, locks, `UploadQueue` and `DeleteQueue`
traffic, command buffers, submissions, and waits.

## Acceptance criteria

- [ ] A table for each sample comparing ngfx's per-frame and per-draw work with gfx's,
      with file:line references to both
- [ ] Every place where ngfx does more than gfx for the same sample is flagged, with a
      verdict: inherent to NoGraphicsAPI, a cost of a decision in subtask 01, or a fix
- [ ] The fixes are listed as follow-up tasks; none is made in this subtask
