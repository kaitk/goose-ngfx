# 005: Create pipelines before the first draw

Status: todo

ngfx creates a pipeline at its first draw into a new set of target formats
(`native/ngfx_draw.cpp:51-76`), so the driver's shader compile happens mid-frame.
NoGraphicsAPI's examples create every pipeline before the loop. Task 001's subtask 01 has
the details as row 7. Creating pipelines lazily stays the fallback, because it keeps
gfx's surface.

## Acceptance criteria

- [ ] A program can name a pipeline's target formats in advance: as `PipelineDesc`
      fields (color and depth formats, which default to lazy), or as
      `ngfx::prepare(pipeline, PassDesc)`. Choose one and record why in
      `docs/design.md`
- [ ] `ngfx.goose` and `native/ngfx_api.h` changed together, with
      `scripts/api_check.py` passing
- [ ] The samples prepare their screen pipelines at startup
- [ ] A test that draws with a prepared pipeline and one created lazily, and that
      misuses `prepare`
- [ ] Tests and samples pass plainly and under `GOOSE_NGFX_SYNC=full`
