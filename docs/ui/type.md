# Type

The Rune view owns type. The Odin side ships no font, no atlas, no shaper, and no
type tokens. The shim ships Geist Variable and Geist Mono Variable in
`ui/shim/assets/`, embeds them with `include_bytes!`, and registers the `Geist`
and `Geist Mono` families with Rune. Rune falls back to the system faces for
characters the subsets do not cover.

Most text uses Rune's default style. The HUD does not set a size or tracking;
the kit surfaces use the kit's type scale. The palette uses the kit's type
styles and one view-local 18/24 title style in `ui/shim/src/palette.rs`. Weight
follows the Type weight setting, and numeric values use the Geist Mono family.
Change a text style in `ui/shim/src` and let Rune lay it out.

## The status panel

The panel is a `col` with a 12 point inset, a 6 point gap, and Rune's default
text. A row is either a label alone, a divider, a header, or a label with a
right-aligned value. The value is the string the game already formatted, so a
number does not change the shape of the panel.

`ui.Row.numeric` reaches the shim as `flags` bit 0. The value of a numeric row
draws in Geist Mono; its label stays in Geist. The palette cards are not
numeric.

## The settings dialog

Settings is a kit `Dialog`; its labels use the kit styles and inherit the type
weight. The HUD opacity value draws in Geist Mono. Type weight remains a stored setting but is not part of
Settings.

The game sends the weight in the UI snapshot and the shim rebuilds the kit when
it changes, so every kit control and every local text node follows. Geist
Variable and Geist Mono Variable carry a continuous `wght` axis, so an odd value
such as 565 interpolates instead of snapping to a named instance. A weight of
400 is the old default; a zero or absent weight leaves the default text style
untouched. `scenarios/rune-weight.json` captures the status panel at 400, 565,
and 900, plus the settings dialog at 565.

## Numbers

Any number that changes while the player moves keeps a fixed field and sets
`ui.Row.numeric = true`. The fixed field keeps the panel still; the flag selects
Geist Mono for the value. Use the space flag in Odin's `fmt` (`"% 4.1f"`, not
`"%4.1f"`) because a zero-padded value still changes the string width.

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

- No font file, atlas, glyph cache, or shaper in the Odin tree. The faces live
  in `ui/shim/assets/`.
- No type size or colour literal in `src/ui`, `src/frame`, or `src/renderer`.
  Rune view code is the one place those values live.
- No truncation. A row that does not fit is a layout bug, not an ellipsis.
- No animation on text. Kit motion belongs to the surrounding control.
