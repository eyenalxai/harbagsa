# Type

Five roles, three faces, one family. The faces are Noto Sans Regular, Noto Sans
Medium, and Noto Sans Mono Regular, subset to ASCII plus `·` and `×`. All three
are SIL OFL 1.1; `src/renderer/fonts/PROVENANCE.md` records how they were cut.

Text is drawn from one 1024x512 signed distance field atlas, rasterized at a
40 px em. The field carries the glyph's distance to its outline, so a fragment
shader reconstructs a crisp edge at any size. One texture, one draw call.

## The scale

Sizes are pixels at density 1 and multiply by density. Tokens are in
`src/renderer/ui_theme.odin`.

| Role | Token | Size | Leading | Weight | Tracking |
| --- | --- | --- | --- | --- | --- |
| Panel title | `type_title` | 21 | 1.25 | Medium | -0.01 em |
| Body | `type_body` | 15 | 1.5 | Regular | 0 |
| Label | `type_body_strong` | 15 | 1.5 | Medium | 0 |
| Detail | `type_caption` | 14 | 1.45 | Regular | 0 |
| Section header | `type_caption_caps` | 14 | 1.45 | Medium | +0.06 em |

Never add a size outside this table. If a surface needs one, add a token, a
rationale, and a line here.

`type_caption_caps` also sets `caps = true`. That flag uppercases `a` to `z` at
draw time, so the source string stays in sentence case and a redesign changes one
boolean instead of every literal.

## Leading and tracking

Leading is unitless in the source and baked into `line_height` in pixels. Display
sizes tighten, body sizes relax: 1.25 at 21 px, 1.5 at 15 px, 1.45 at 14 px.
Tracking appears only on capitals, and only positive. Body text gets none.

The baseline sits at
`(line_height - (ascent - descent)) / 2 + ascent` from the top of the line box, so
the ascent and descent centre inside the leading. Use `text_baseline`, never a
guessed offset.

## Numbers

Any number that changes while the player moves uses two things together:

1. `Row.numeric = true`, which swaps the value to Noto Sans Mono.
2. A fixed-width field, so a value cannot change the string's width.

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
- No weight change on interaction. There is no hover state in this UI, and a
  weight swap reflows the row.
- No text under 14 px at density 1. Below that a lowercase `l` is a single hairline
  with more space around it than its own width, and the word reads with a gap in
  it. That is a legibility floor, not a preference.
- No truncation. A row that does not fit is a layout bug, not an ellipsis.
