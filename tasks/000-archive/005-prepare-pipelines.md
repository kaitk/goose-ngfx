# 005: Create pipelines before the first draw

Status: done

Historical task: the problem statement describes behavior before the change.
The results record the implementation; see [the API](../../docs/api.md) for current behavior.

ngfx creates a pipeline at its first draw into a new set of target formats
(`native/ngfx_draw.cpp:51-76`), so the driver's shader compile happens mid-frame.
NoGraphicsAPI's examples create every pipeline before the loop. Task 001's subtask 01 has
the details as row 7. Creating pipelines lazily stays the fallback, because it keeps
gfx's surface.

## Acceptance criteria

- [x] A program can name a pipeline's target formats in advance: as `PipelineDesc`
      fields (color and depth formats, which default to lazy), or as
      `ngfx::prepare(pipeline, PassDesc)`. Choose one and record why in
      `docs/design.md` (`prepare`)
- [x] `ngfx.goose` and `native/ngfx_api.h` changed together, with
      `scripts/api_check.py` passing
- [x] The samples prepare their screen pipelines at startup
- [x] A test that draws with a prepared pipeline and one created lazily, and that
      misuses `prepare` (`test/ngfx_prepare.goose`, and
      `test/ngfx_prepare_misuse.goose`, since a misuse aborts the program)
- [x] Tests and samples pass plainly and under `GOOSE_NGFX_SYNC=full`

## Results

On the M1 Pro (Metal 4), 2026-10-11: every test passes plainly and under
`GOOSE_NGFX_SYNC=full`, and each sample prints what it did and saves a screenshot
byte-identical to the one before the change, both ways. The samples call
`prepare_screen` for each pipeline after creating it, and `ui_todo` calls
`ngfx_ui::prepare()` before its loop.

On the RTX 4090 (Vulkan), 2026-10-11: the same, and under the validation layer too, as
task 003 records.
