# 007: Draw ui with fewer externs and indexed quads

Status: done

`ngfx_ui.goose` makes 4 externs per draw where gfx's ui makes 3, and a 40-byte root
per draw, though only `first` and the texture change between draws
(`ngfx_ui.goose:137-141`). Its draws aren't indexed, because ngfx's `draw_indexed` takes
a `Buffer` and the frame's indices are in frame memory. A quad costs 6 vertex
invocations instead of about 4. NoGraphicsAPI's `draw_indexed` takes any `GpuRange`
(`NoGraphicsAPI.cpp:3832`). Task 001's subtask 02 has the details as flags 11 and 12,
proposal P7.

## Acceptance criteria

- [x] `first` passed as the draw's `first_vertex`, after checking that `SV_VertexID`
      includes it on both Metal and Vulkan, and recording the result. It includes it on
      Metal and not on Vulkan, both measured (`docs/design.md`, "Surface"), so `first`
      is the indexed draw's `first_index` instead, where `SV_VertexID` is the index on
      both
- [x] A root made only when the texture changes
- [x] `draw_indexed` takes an index range by GPU address, so indices in `frame_data`
      work. This is a surface change: `ngfx.goose`, `native/ngfx_api.h`, and
      `docs/api.md` together, with `scripts/api_check.py` passing
- [x] `ngfx_ui.goose` draws indexed quads. `ui_todo` prints and screenshots what it does
      now, plainly and under `GOOSE_NGFX_SYNC=full`

## Results

On the M1 Pro (Metal 4), 2026-10-11: a probe drawing with `first_vertex` 5 saw
`SV_VertexID` 5 to 7, and `draw_indexed` with `vertex_offset` 10 saw 10 to 12; both saw
`SV_InstanceID` 0 with `first_instance` 7. Slang's SPIR-V for the same shader subtracts
`BaseVertex` and `BaseInstance`. `test/ngfx_draw_ranges.goose` draws from frame memory
and from a buffer's range. Every test passes both ways, and `ui_todo`'s screenshot is
byte-identical to the one before the change, both ways.

On the RTX 4090 (Vulkan), 2026-10-11: the same probe, its vertex shader recording its IDs
into a buffer, saw `SV_VertexID` 0 to 2 for both draws, and `SV_InstanceID` 0, as
Slang's SPIR-V says. `test/ngfx_draw_ranges.goose` passes both ways, and `ui_todo`'s
screenshot is byte-identical to the one before the change, both ways, as task 003
records.
