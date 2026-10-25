# Type

Five roles, two faces, one axis. The faces are Roboto Condensed and Roboto Mono,
both variable, subset to ASCII plus `·`, `×`, and `…`. Each face is one file; the
weight is a coordinate, not a separate asset. Both are SIL OFL 1.1;
`src/renderer/fonts/PROVENANCE.md` records how they were cut.

Text is drawn from a coverage atlas rasterized at the device pixel size. A texel
holds the fraction of the pixel the glyph covers, so the shader passes it
straight to alpha. One texture, one draw call.

A distance field was used until ADR 0007. It cannot draw a stem thinner than its
reconstruction footprint, and at these sizes every stem is thin. Do not bring it
back.

## The axis

Roboto Condensed runs from Thin 100 to Black 900. The named instances are Thin
100, ExtraLight 200, Light 300, Regular 400, Medium 500, SemiBold 600, Bold 700,
ExtraBold 800, and Black 900. Roboto Mono runs from Thin 100 to Bold 700.

The base weight defaults to 400 and is stored as a whole unit in
`Settings.type_weight`, clamped to 100..900. Every role derives from it:

| Role | Token | Size | Leading | Weight | Tracking |
| --- | --- | --- | --- | --- | --- |
| Panel title | `type_title` | 21 | 1.25 | base + 100 | -0.01 em |
| Body | `type_body` | 15 | 1.5 | base | 0 |
| Label | `type_body_strong` | 15 | 1.5 | base + 100 | 0 |
| Detail | `type_caption` | 14 | 1.45 | base | 0 |
| Section header | `type_caption_caps` | 14 | 1.45 | base + 100 | +0.06 em |

The strong offset clamps at 900. At base 900 the title and labels reach the
body's weight; size and colour still separate the roles. Mono uses
`min(base, 700)`, so above 700 the numbers stop gaining weight.

Never add a size outside this table. If a surface needs one, add a token, a
rationale, and a line here.

`type_caption_caps` also sets `caps = true`. That flag uppercases `a` to `z`
before shaping, so the source string stays in sentence case and a redesign
changes one boolean instead of every literal.

## The settings row

The settings menu draws a `Slider` row for the axis. It is two lines: label and
value on the first, a full-width track with nine ticks on the second. The ticks
mark the named instances. The value is the number only, right-aligned.

- Left and Right step by 10 and clamp to 100..900.
- A press on the track starts a drag. The cursor x maps onto the track, and the
  value follows it to the whole unit.
- The menu content width is measured on every layout with 5 % headroom. There
  is no frozen width; input and draw call the same `ui.menu_layout`, and a
  weight change may resize the panel once on the next frame.
- The weight applies to the menu and the HUD together. The first atlas builds
  synchronously at startup; later weight changes repack on a worker. The number
  and knob update immediately and the glyphs follow on the next swap.

## The atlas

The atlas holds one layer per `(face, weight, pixel size)` pair the theme can
draw. Seven are in use at the default base weight; at base 900 the strong layers
merge with the body and the count drops to five:

- title 21 at base + 100
- body 15 at base
- label 15 at base + 100
- detail 14 at base
- section header 14 at base + 100
- mono 15 at `min(base, 700)`
- mono 14 at `min(base, 700)`

`TEXT_LAYER_MAX` is 8. A style that names a layer the atlas does not have falls
back to the same face, then the nearest weight, then the nearest size.

FreeType instances each layer and rasterizes every glyph in the subset, keyed by
glyph ID. HarfBuzz supplies the advances and the pair positions. A glyph is
stored as four horizontal phase bitmaps:

- The baseline rounds to a whole pixel. A row moves by at most half a pixel, and
  the alternative is resampling every edge.
- Each glyph snaps horizontally and takes its sub-pixel offset from one of four
  phases, rasterized into the atlas. The advance stays fractional, so the phases
  absorb the fraction and the line's measured width is unchanged.

Do not draw text at a fractional baseline or bypass the phase. Either one
resamples the coverage across two texels and blurs the whole line.

## Leading and tracking

Leading is unitless in the source and baked into `line_height` in pixels. Display
sizes tighten, body sizes relax: 1.25 at 21 px, 1.5 at 15 px, 1.45 at 14 px.
Tracking appears on two roles only: the title tightens by `-0.01 em`, and the
section header opens by `+0.06 em`. The section header is the only role in
capitals. Body text gets none.

The baseline sits at
`(line_height - (ascent - descent)) / 2 + ascent` from the top of the line box, so
the ascent and descent centre inside the leading. Use `text_baseline`, never a
guessed offset.

The body line box is 22.5 px at density 1. Setting rows sit 28.5 px apart with
the 6 px row gap. The slider row is 40.5 px tall.

## Numbers

Any number that changes while the player moves uses two things together:

1. `Row.numeric = true`, which swaps the value to Roboto Mono and clamps the
   mono weight to 700.
2. A fixed-width field, so a value cannot change the string's width.

Roboto's default digits are tabular, so the digits stay equal inside a field.

| Value | Format | Example |
| --- | --- | --- |
| Speed | `"% 4.1f m/s"` | `" 0.0 m/s"`, `"11.0 m/s"` |
| Arena position | `"X % 5.1f  Y % 5.1f  Z % 5.1f"` | `"X   0.0  Y   0.0  Z  14.0"` |
| Debug position | `"X % 7.1f  Y % 7.1f  Z % 7.1f"` | for the unclamped debug camera |
| Crate count | `"% 2d"` | `" 3"`, `"64"` |
| Sun angles | `"az % 4.0f  el % 4.0f"` | `"az -128  el  -60"` |

The leading space flag is not cosmetic. Odin's `fmt` zero-pads when a width is
given, so `"%5.1f"` renders `"000.0"`; `"% 5.1f"` renders `"  0.0"`. Every fixed
field carries the space flag.

Why this matters: the status panel's width is the widest row. A value that can
grow a character makes the whole panel jump as the player walks.
`tests/frame/hud_rows.odin` fails if it does.

## Copy

- Sentence case in the source. Capitals come from `caps`, never from the literal.
- `·` separates peers inside one string: `"Standing · Walk"`. `Esc settings` uses
  spacing, not a separator.
- `×` for dimensions, never `x`.
- `…` for an ellipsis, never three periods.
- A label names the thing, the value carries the fact: `"Speed"` / `"0.0 m/s"`.
  Never merge them into `"Speed: 0.0"`, because the merged form cannot align.

## Bans

- No italic. The atlas has no italic face, and the browser never synthesises one
  here.
- No weight change on hover or selection. The Type weight slider is a settings
  value, not a state; a selection must not reflow the row.
- No weight outside 100..900. The axis ends at Thin and Black.
- No text under 14 px at density 1. The em is the em: a 14 px token draws a 14 px
  em. Smaller than that, a stem is under a pixel and the coverage has to spread
  it over two, which reads as a grey line.
- No truncation. A row that does not fit is a layout bug, not an ellipsis.
- No hinting and no stem darkening. The faces rasterize at their true
  proportions. Forcing a stem to a whole pixel would even the weight and distort
  the letterforms; this UI does not need the trade.
