# Variable-weight type with FreeType and HarfBuzz

The 2D layer draws Roboto Condensed and Roboto Mono from one variable file per
face. Weight is a settings value, the atlas is keyed by face, weight, and pixel
size, and HarfBuzz shapes every string. This replaces the three static Noto
faces and `stb_truetype`.

## Context

The coverage atlas of ADR 0007 rasterized three static faces. The theme named one
of `Regular`, `Medium`, or `Mono`, so the weight axis of the font could not be
used. `stb_truetype` reads the default outlines and ignores `fvar`, `gvar`, and
`HVAR`. Roboto Condensed also has no legacy `kern` table, so the old kerning path
would return nothing after the font swap. A numeric `Detail` row fell back to the
15 px mono layer because the theme added only one mono size. Separately,
`src/renderer/fonts/OFL.txt` held the Apache 2.0 text while the fonts were SIL
OFL 1.1.

The requested result was a continuous weight, 100 to 900, changeable at runtime
from the settings menu, with correct advances and kerning at every value, and no
frame stall during the change.

## Decision

- **Fonts.** Ship Roboto Condensed and Roboto Mono as variable TTF files, subset
  to ASCII plus `·` and `×`. Roboto Condensed covers `wght` 100 to 900; Roboto
  Mono covers 100 to 700. Both are SIL OFL 1.1.
- **Libraries.** Vendor FreeType 2.15.0 and HarfBuzz 15.0.0, built as static
  archives by the Makefile. FreeType is configured without the bytecode
  interpreter, autohinter, zlib, CFF, or Type 1. HarfBuzz builds its amalgamation
  as C++11 with `HB_NO_MT`; `HB_NO_VAR` stays off because it removes the axis.
- **Type model.** `Text_Face` is `Sans` or `Mono`; `Text_Type.weight` is a float.
  The settings row stores whole units. Body and Detail use the base; Title,
  Label, and Section header use `min(base + 100, 900)`; Mono uses
  `min(base, 700)`.
- **Atlas.** The layer key is `(face, weight: u16, px: u32)`. Every glyph in the
  subset is rasterized by FreeType at the device pixel size, keyed by glyph ID,
  with four horizontal subpixel phases. The theme uses seven layers of the eight
  available at one base weight, including a 14 px mono layer, so numeric Detail
  rows draw at their true size.
- **Shaping.** HarfBuzz shapes each string at the font UPM and the renderer
  scales positions by `px / upem`. Caps transforms uppercase before shaping.
  Tracking is applied after each advance and removed from the trailing gap.
  Unsupported codepoints are dropped. The 97x97 kerning table is gone.
- **Runtime.** The initial atlas builds synchronously. Later builds run on one
  worker, coalesce to the newest layer set, and apply on the main thread. The
  active atlas and its theme keep drawing until the swap, so the rasterization
  stays off the frame. The swap itself waits for the device once, as the old
  synchronous rebuild did.
- **Settings.** A `Slider` row sits after Resolution. It is two lines: label and
  value on the first, a full-width track with nine named-instance ticks on the
  second. Left and Right step by 10; a positional drag maps the cursor to the
  track. The value is the number only. The menu content width freezes on the
  open edge with 5 % headroom, so the track cannot move under the cursor.
- **Harness.** `menu` gains a `set` command for an exact weight.
  `settings.type_weight` is a state field and part of the digest. A capture
  waits for the pending atlas before it draws.

## Considered options

- **Runtime instancer in Odin over stb_truetype.** Parse `fvar`, `avar`, `gvar`,
  `HVAR`, apply IUP, rebuild a static TTF in memory, and hand it to stb. No new
  dependency and no C++ compiler, but several thousand lines of binary parsing
  and no GPOS kerning. Rejected: the port would be larger and riskier than the
  bindings it replaces.
- **A static ladder of named weights.** Nine pre-built faces. Simple, but the
  in-between values disappear, which contradicts the request.
- **FreeType only.** Correct instancing and rasterization, but Roboto has no
  legacy `kern` table, so pair kerning would vanish. HarfBuzz is needed for
  GPOS.
- **Keep the 97x97 pair table.** Shape every pair once per weight. It loses
  context and costs 9,409 shapes per weight; full shaping of a short row is
  cheaper and correct.

## Consequences

- The build needs a C++ compiler. A cold build compiles the HarfBuzz
  amalgamation in about 43 s and the FreeType module set in about 12 s; both are
  cached afterwards.
- The atlas is now weight-dependent. A new weight repacks every layer. The
  worker hides that cost, but the text lags the slider by a frame or two.
- The mono face stops at Bold 700. Above 700 the numbers stop gaining weight
  while the prose continues to Black 900.
- At base 900 the strong offset clamps, so the title and labels match the body.
  Size and colour still separate the roles.
- The menu panel is pinned to the width measured on open plus 5 %. It is 494 x
  517 px at 720p in a menu at the default weight.
- The `wdth` axis, italics, synthetic weights, complex scripts, bidi, per-role
  weights, animated weight, disk persistence, and hinting stay out of scope.
- ADR 0007 remains the record of the coverage atlas. This ADR extends it with
  variable instancing, shaping, the worker, and the settings row.

## References

- ADR 0007, the coverage atlas.
- FreeType 2.15.0, <https://freetype.org>.
- HarfBuzz 15.0.0, <https://harfbuzz.github.io>.
- OpenType `fvar`, `avar`, `gvar`, `HVAR`, and `GPOS` tables.
- Roboto Condensed and Roboto Mono, SIL OFL 1.1.
