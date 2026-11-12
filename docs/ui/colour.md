# Colour

The Rune view owns its colour. The values are RGBA float literals in
`ui/shim/src/lib.rs`; Rune premultiplies and composites them. There is no theme
file and no sRGB-to-linear conversion in Odin. The world palette is separate and
stays linear.

## The view palette

| Token | RGBA in the shim | Hex reference | Role |
| --- | --- | --- | --- |
| Status surface | `0.06, 0.08, 0.10, 0.94` | `#0F141A` at 94% | the top-left status panel |
| Menu surface | `0.08, 0.10, 0.13, 1` | `#141A21` | the settings menu and palette panel |
| Raised surface | `0.15, 0.19, 0.24, 1` | `#26303D` | the selected row |
| Primary text | `0.93, 0.95, 0.97, 1` | `#EDF2F7` | values, title, selected label |
| Secondary text | `0.65, 0.70, 0.75, 1` | `#A6B2BF` | labels, blocked values |
| Tertiary text | `0.50, 0.55, 0.60, 1` | `#808C99` | notes, headers, key hints |
| Accent | `0.90, 0.69, 0.23, 1` | `#E6B03B` | selected-row bar, filled slider track, and `Close` button |
| Hairline | `0.35, 0.38, 0.42, 0.25` | `#59616B` at 25% | menu separator |
| Slider track | `1, 1, 1, 0.20` | white at 20% | the unfilled slider track |
| Scrim | `0, 0, 0, 0.62` | black at 62% | behind the settings menu |

The action buttons use the accent for `Close` and `0.16, 0.19, 0.24` for
`Debug`. The rune-fx demo asks for `#7C5CFF` with a `#F4F0FF` core; it is not part
of the default interface.

Object colours in the palette are content from `src/game/prefabs.odin`; they do
not come from this table.

## Contrast

Measured on the authored values, the WCAG 2 way. WCAG 2 is the gate; APCA is a
reference only.

| Foreground | On menu surface | On raised surface | On status surface |
| --- | --- | --- | --- |
| Primary text | 15.39:1 | 11.75:1 | 16.44:1 |
| Secondary text | 8.05:1 | 6.14:1 | 8.60:1 |
| Tertiary text | 5.07:1 | 3.86:1 | 5.40:1 |
| Accent | 8.70:1 | 6.64:1 | 9.30:1 |

The floor is 4.5:1 for text and 3:1 for a non-text element such as the accent
bar. Tertiary text is not allowed to become the label or value of a selectable
row; selection must move it to secondary or primary.

## Choosing a colour

- A value, a title, or a selected label: primary.
- A label or a blocked value: secondary.
- A note, a header, or a key hint: tertiary.
- The selected-row bar, the filled slider track, and the `Close` button: accent.
- A separator: hairline. A slider track: the white 20% token.

## Bans

- No colour literal outside `ui/shim/src/lib.rs` and the game's content data.
- No third hue in the view. The scene has its own palette; do not copy a world
  colour into the view and do not copy the accent into the world.
- No colour-only signal. Selection keeps both the raised surface and the accent
  bar.
- No dark-mode variant. There is one view and the scene is its backdrop.
