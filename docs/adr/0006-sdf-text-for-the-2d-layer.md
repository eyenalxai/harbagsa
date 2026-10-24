# SDF text for the 2D layer

The overlay draws text from one signed distance field atlas, rasterized at
startup from three subset Noto faces. It replaced `stb_easy_font`, a debug font
of 1 px strokes and one weight that had shipped as product UI.

## Context

`stb_easy_font` covers ASCII as axis-aligned rectangles in a 7 px cell. It has
one weight, no antialiasing, no kerning, and no tracking. The HUD drew it at a
continuous 2 to 4 times scale, so every stroke landed on a fraction and the
result read as a debug overlay. The menu padded labels with `%-12s`, which put
the value column anywhere within a 16 px range because the font is proportional.
The selected row measured 4.2:1 against white text.

The project needs text at three sizes from a small window to a 4K display, with
no asset pipeline and no build step.

## Decision

Embed three faces as compile-time byte arrays, rasterize one 1024x512 `R8`
signed distance field atlas at startup with `vendor:stb/truetype`, and sample it
in `hud.frag` with a `fwidth`-based threshold.

- Faces: Noto Sans Regular, Noto Sans Medium, Noto Sans Mono Regular, subset to
  ASCII plus `·` and `×`, 13 KB each, SIL OFL 1.1.
- Base size 40 px, padding 6, `onedge 128`, `dist_scale 64`. 291 glyphs at 45%
  occupancy. About 105 ms to build, once.
- One texture, one sampler, one descriptor set, one draw call. The HUD vertex
  carries a `uv`; rectangles pass a negative `u` and skip the sample.
- Text is measured and drawn by the same cursor, so a centred string cannot
  drift from its own width.

## Considered options

- **Refine the pixel font.** No asset and no dependency, but one weight and no
  antialiasing leaves hierarchy to size and colour alone. Rejected because the
  request was better typography, and this cannot deliver it.
- **Exact-size grayscale atlas.** Sharpest at the exact pixel size, but the atlas
  must be rebuilt on every resize and every size step needs its own copy.
  Rejected as more lifecycle for a marginal gain at the sizes used.
- **Offline MSDF atlas.** Scales further and needs no font binary, but adds a
  generator, a build step, and a committed PNG plus JSON, and the repo currently
  has no asset pipeline. Rejected until text needs to render above 42 px.

## Consequences

- The Odin vendor tree ships `stb_truetype.a` (65 KB) inside the compiler
  installation, and the binding links it with a relative `foreign import`. The
  archive is not committed and the build system does not change.
- Startup pays about 105 ms and 1 MB of texture memory.
- The atlas has a maximum useful size. At density 2 the largest role draws at
  42 px, a 5% upscale from the 40 px field; a role larger than 21 px at density 1
  would soften. Raise `TEXT_ATLAS_BASE_PX` before adding one.
- The smallest role is 14 px at density 1. Smaller text was tried and rejected:
  a lowercase `l` became a hairline with more space around it than its own
  width, so the word read with a gap in it.
- `pyftsubset` is a development tool, not a build dependency. The subset files
  and their provenance are committed.
- No future 2D layer may reintroduce a bitmap debug font. `docs/ui/type.md` is
  the rule; `make check` and the contrast test in `tests/renderer/text.odin` are
  the enforcement.
