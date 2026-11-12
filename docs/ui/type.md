# Type

The Rune view owns type. The Odin side ships no font, no atlas, no shaper, and no
type tokens. Rune bundles Inter for native builds and falls back to the system
faces for characters Inter does not cover. The shim does not set a font family,
size, or tracking; it uses Rune's default text style, except for weight, which
follows the Type weight setting. Change a text style in `ui/shim/src/lib.rs` and
let Rune lay it out.

## The status panel

The panel is a `col` with a 12 point inset, a 6 point gap, and Rune's default
text. A row is either a label alone, a divider, a header, or a label with a
right-aligned value. The value is the string the game already formatted, so a
number does not change the shape of the panel.

`ui.Row.numeric` survives in the snapshot, but the current shim draws every
value with the default Rune style. Do not rely on the flag for a typeface; use
it when a future view needs a numeric treatment.

## The settings menu

The menu title is the first row, followed by a separator. A `Setting` row shows a
label and a value; the selected row adds the raised surface and the accent bar. A
`Slider` row adds a 4 point filled track below the label and value; the filled
width follows `ui.Row.ratio`. It is a row list, not a knob slider, and `ticks` is
unused.

The Type weight row edits `Settings.type_weight` from 100 to 900. The game sends
the value in the UI snapshot and the shim applies it to every text node through
`weighted_text`, a span over the whole string. The status panel, the menu title
and rows, the hints, and the palette all get it. A weight of 400 leaves Rune's
default; a zero or absent weight leaves the default text style untouched.
`scenarios/rune-weight.json` captures the status panel at 400 and 900 after the
menu sets the weight.

## Numbers

Any number that changes while the player moves keeps a fixed field and sets
`ui.Row.numeric = true`. The field is what keeps the panel still; the flag is
the hint a view would use to pick a numeric style. Use the space flag in Odin's
`fmt` (`"% 4.1f"`, not `"%4.1f"`) because a zero-padded value still changes the
string width.

| Value | Format | Example |
| --- | --- | --- |
| Speed | `"% 4.1f m/s"` | `" 0.0 m/s"`, `"11.0 m/s"` |
| Arena position | `"X % 5.1f  Y % 5.1f  Z % 5.1f"` | `"X   0.0  Y   0.0  Z  14.0"` |
| Debug position | `"X % 7.1f  Y % 7.1f  Z % 7.1f"` | for the unclamped debug camera |
| Crate count | `"% 2d"` | `" 3"`, `"64"` |

## Copy

- Sentence case in the source.
- `·` separates peers inside one string: `"Standing · Walk"`.
- `×` for dimensions, never `x`.
- `…` for an ellipsis, never three periods.
- A label names the thing, the value carries the fact: `"Speed"` / `"0.0 m/s"`.
  Never merge them into `"Speed: 0.0"`, because the merged form cannot align.

## Bans

- No font file, atlas, glyph cache, or shaper in the Odin tree.
- No type size or colour literal in `src/ui`, `src/frame`, or `src/renderer`.
  Rune view code is the one place those values live.
- No truncation. A row that does not fit is a layout bug, not an ellipsis.
- No animation on text. The menu swaps in one frame.
