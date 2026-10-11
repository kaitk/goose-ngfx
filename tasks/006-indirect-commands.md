# 006: Add indirect draws and dispatch

Status: todo

NoGraphicsAPI has `draw_indirect`, `draw_indexed_indirect`, and `dispatch_indirect`
(`NoGraphicsAPI.hpp:817-821`), which take a GPU pointer to their arguments. ngfx has
none, so a program can't write GPU-driven culling. Task 001's subtask 01 has the details
as row 19. The barrier points `STAGE_INDIRECT` and `ACCESS_INDIRECT_READ` already order
them.

## Acceptance criteria

- [ ] `ngfx::draw_indirect`, `draw_indexed_indirect`, and `dispatch_indirect`. Each takes
      the arguments' GPU address, as `draw` takes a root's, and its index range the same
      way as task 007's `draw_indexed`
- [ ] `ngfx.goose`, `native/ngfx_api.h`, and `docs/api.md` changed together, with
      `scripts/api_check.py` passing
- [ ] A test in which a compute pass writes the arguments and draws with them, behind an
      `ngfx::barrier(COMPUTE_WRITE, STAGE_INDIRECT | ACCESS_INDIRECT_READ)`, passing
      plainly and under `GOOSE_NGFX_SYNC=full`
