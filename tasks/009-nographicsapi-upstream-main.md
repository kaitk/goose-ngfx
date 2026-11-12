# 009: NoGraphicsAPI at upstream's main, its roots checked on Metal

Status: in-progress (on the branch `nographicsapi-main`; Vulkan done 2026-11-12, Metal to do)

The submodule follows `kaitk/NoGraphicsAPI`'s `main`: upstream's `main` (`ffd9f2a`) with
the fork's `astc-6x6` and `vsync-option` merged (`b80848e`). Upstream's `ffd9f2a` changed
what ngfx relies on:

- `create_texture` takes the device and records nothing; `initialize_texture` readies a
  placed texture before its first use (and replaces `aliasable` and
  `activate_texture_alias`). ngfx initializes each placed texture into the setup
  commands (`place_texture`).
- A PSO is bound inside each render pass; ngfx binds at the first draw after a pass
  begins already.
- **Roots take the constant-buffer layout on Metal** (`docs/slang.md` there): a root's
  size is a multiple of 16 bytes (a `static_assert` on Metal), two-component vectors align
  to 8 and four-component ones and matrices to 16, no three-component vectors. Vulkan's
  layout is unchanged. A Goose struct is packed, so a root such as `cube`'s (a `u64`, then
  a `float4x4`) passes the size check but puts the matrix at 8 where Metal reads it at 16.

## Done on Windows (Vulkan, RTX 4090)

- `place_texture` initializes; `ngfx_mips.slang`'s root and the test probe's padded to 16
  bytes (Goose can't name a field `pad`: `unused`).
- The 34 tests and samples pass, and with `GOOSE_NGFX_PASS_BARRIER=1`; Draughts' ngfx
  build draws its shots pixel for pixel as before (flat, 3D with SMAA and SSAA, portrait).
- Every embedded shader compiled for Metal with slangc on Windows: 20 still fail the root
  size check, in `ngfx_ui.goose`, `bench/draws_ngfx.goose`, `samples/mini_minecraft.goose`,
  and the tests `ngfx_compressed`, `ngfx_compute` (4), `ngfx_draw_ranges`, `ngfx_indirect`
  (3), `ngfx_render` (2), `ngfx_screen_frames`, `ngfx_slang_sources`, `ngfx_textures`;
  `mini_doom`'s two and one in `ngfx_slang_sources` don't parse standalone (not checked).
  Draughts' own `src/ngfx/shaders/` pass the size check but are unchecked for alignment.

## Acceptance criteria

- [x] The submodule at the fork's `main`, ngfx building and passing on Vulkan
- [ ] Every root padded and aligned to the constant-buffer layout, the Goose struct and
      the Slang one alike, checked with NoGraphicsAPI's `tools/check_root_layouts.py` on
      the Mac, Draughts' `src/ngfx/shaders/` included
- [ ] The tests, samples, and Draughts' ngfx shots passing on Metal (the Mac and the iPhone)
- [ ] Merged into `main`, and the fork's `ngfx` branch retired
