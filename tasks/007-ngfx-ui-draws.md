# 007: Draw ui with fewer externs and indexed quads

Status: todo

`ngfx_ui.goose` makes 4 externs per draw where gfx's ui makes 3, and a 40-byte root
per draw, though only `first` and the texture change between draws
(`ngfx_ui.goose:137-141`). Its draws aren't indexed, because ngfx's `draw_indexed` takes
a `Buffer` and the frame's indices are in frame memory. A quad costs 6 vertex
invocations instead of about 4. NoGraphicsAPI's `draw_indexed` takes any `GpuRange`
(`NoGraphicsAPI.cpp:3832`). Task 001's subtask 02 has the details as flags 11 and 12,
proposal P7.

## Acceptance criteria

- [ ] `first` passed as the draw's `first_vertex`, after checking that `SV_VertexID`
      includes it on both Metal and Vulkan, and recording the result
- [ ] A root made only when the texture changes
- [ ] `draw_indexed` takes an index range by GPU address, so indices in `frame_data`
      work. This is a surface change: `ngfx.goose`, `native/ngfx_api.h`, and
      `docs/api.md` together, with `scripts/api_check.py` passing
- [ ] `ngfx_ui.goose` draws indexed quads. `ui_todo` prints and screenshots what it does
      now, plainly and under `GOOSE_NGFX_SYNC=full`
