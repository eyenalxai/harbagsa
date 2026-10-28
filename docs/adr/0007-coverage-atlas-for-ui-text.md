# Coverage atlas for the 2D layer

> Updated by ADR 0016 and ADR 0033. The faces are now variable Geist and Geist
> Mono; the layer key carries the face and weight, and the mono set has a 14 px
> layer. The Noto role list below is the state at the time of this decision.

The overlay draws text from a coverage atlas rasterized at the device pixel
size. It replaces the signed distance field atlas of ADR 0006, which could not
draw a one-pixel stem.

## Context

ADR 0006 chose a signed distance field so one atlas could serve every size. The
field was rasterized at `TEXT_ATLAS_BASE_PX = 40`, and the tokens were assumed to
land within 5% of it. Two facts broke that assumption.

The first is the unit. `stbtt_ScaleForPixelHeight` maps the font's ascent–descent
span, not the em, so the field's em was 29.4 px, not 40. `text_scale` then read
`token / 40`, which made every role 27% smaller than its token: the 15 px body
drew at an 11.0 px em and the 14 px caption at 10.3 px. That is under the
legibility floor `docs/ui/type.md` sets and is why the shipped UI reads small.

The second is the field's reach. The atlas encoded `128 + 64 · d` and clamped to
8 bits, so the field was linear for only ±2 texels. At density 1 the body draws
2.67 texels per screen pixel: one pixel covers more than the whole useful range,
and the narrowest stroke — 1.0 px — has a half-width of 1.3 texels, less than the
antialiasing ramp it must cross. Measured on the shipped atlas, the distance at
the centre of a stem peaked at 197 of 255, or 1.08 texels, so the reconstructor
never reached full coverage inside the stroke. The text drew grey, with dropouts
where the interpolant dipped below the threshold.

Neither is a tuning error:

- Green 2007 presents the distance field as a **magnification** technique. The
  field stands in for the covered area only while the reconstructor's ramp stays
  inside the stored range, and a single field rounds off corners as its
  resolution drops. Both limits bind when the field is minified.
- Smith 1995 is the reason to prefer coverage. A pixel is a point sample of a
  continuous image, and the sample of a glyph for a pixel is the integral of the
  glyph over that pixel's filter footprint, not the value of a distance function
  at the pixel centre. A distance field can approximate that integral only when
  the feature is several pixels wide.

## Decision

Rasterize the glyph outline into an 8-bit **coverage** atlas at the device pixel
size, and sample it one texel per pixel.

- One atlas holds a layer per `(face, pixel size)` pair the theme can draw — six
  at density 1: title 21 Medium, body 15 Regular, label 15 Medium, detail 14
  Regular, section header 14 Medium, and mono 15. The theme derives the set.
- Four horizontal sub-pixel phases per glyph. Text positions are fractional, so
  each glyph stores a bitmap for each quarter-pixel offset. Four phases bound the
  placement error at 1/8 px.
- The line snaps vertically to a whole pixel, and each glyph snaps horizontally,
  taking its sub-pixel offset from the phase. One texel then lands on one pixel,
  so linear filtering is exact and there is no resampling blur.
- The fragment shader reads the coverage and multiplies it into alpha. There is
  no threshold, no derivative, and no reconstruction.
- The atlas is rebuilt when the UI density changes, which is a resize. It costs
  9 ms at density 1 and 13 ms at density 2 for 2,304 glyph phases, and the
  renderer already waits for the device when it rebuilds the swapchain.
- A text size token is an em in device pixels, rounded to an integer. Leading
  multiplies the rounded size so the line box and the glyphs share one unit.

## Considered options

- **Widen the distance field and fix the ramp.** Keeps one resolution-free atlas.
  Rejected: the field cannot represent a stem narrower than the reconstruction
  footprint. Averaging a signed distance across a one-pixel stem gives a value
  near zero, which is 50% coverage, when the stem covers most of the pixel. The
  text would stay thin and low-contrast at the small sizes.
- **Rasterize a distance field at the smallest size and magnify.** No
  minification, so no thin-stem loss. Rejected because the same field then
  magnifies 2.7× for the title: the shape is analytic, but the field's sampling
  grid is not, so corners round by a texel and curves facet.
- **Multi-channel SDF.** Sharpens corners, not thin stems. It answers the
  magnification problem this project does not have.
- **Per-size coverage without sub-pixel phases.** Simplest, and crisp on the
  integer grid. Rejected because the layout is fractional: a glyph at x.5 would
  resample across two texels and blur every edge by half a pixel.

## Consequences

- The atlas is 768x768 at density 1 and 1280x1280 at density 2, `R8_UNORM`:
  0.6 MB and 1.6 MB. It is smaller than a distance field that also carries
  padding, because a glyph needs one texel of border instead of a full ramp.
- The atlas is no longer resolution-free. A resize that changes a rounded pixel
  size repacks it, so a slow drag across a size boundary pays 13 ms once.
- Text is no longer resolution-free in the other direction either: there is no
  sensible render above the largest layer. A role larger than 42 px at density 2
  must add a token.
- No hinting. The faces rasterize at their true proportions, so a stem is 1.4 px
  and lands on two pixels at partial coverage rather than being forced to one.
  That is a deliberate choice for letterform fidelity; it is why the weight reads
  even instead of snapping from glyph to glyph.
- `stb_truetype`'s scanline rasterizer computes exact area coverage, so no
  supersampling pass is needed. Its `MakeCodepointBitmapSubpixel` runs the same
  routine FreeType's gray rasterizer does, and takes the sub-pixel shift
  directly.
- `pyftsubset` stays a development tool. The subset files and their provenance
  are unchanged.
- No future 2D layer may reintroduce a distance field for text under 21 px em.
  `docs/ui/type.md` is the rule.

## References

- Chris Green, "Improved Alpha-Tested Magnification for Vector Textures and
  Special Effects", SIGGRAPH 2007 course notes. The distance field technique and
  its magnification limits.
- Alvy Ray Smith, "A Pixel Is Not A Little Square, A Pixel Is Not A Little
  Square, A Pixel Is Not A Little Square!", Microsoft Tech Memo 6, 1995. Why the
  sample of a glyph is its area coverage.
- Stefan Gustavson and Robin Strand, "Anti-Aliased Euclidean Distance
  Transform", Pattern Recognition Letters 32(2), 2011. The correct way to build a
  distance field from antialiased coverage, kept for the record as the route not
  taken.
