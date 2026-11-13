# Colour

The Rune view owns its colour. `ui/shim/src/theme.rs` holds every token as an
sRGB hex string and builds the rune-kit `Kit` from the dark/amber seed, pinning
the measured overlay tokens. The module converts each hex through Rune's colour
path, so a captured pixel matches the table. Rune premultiplies and composites
the result. The world palette is separate and stays linear.

## The view palette

| Token | Hex | Role |
| --- | --- | --- |
| Status surface | `#0F141A` at 70-100% | the top-left status panel |
| Dialog surface | `#141A21` | the settings dialog and palette panel |
| Raised surface | `#26303D` | the selected row |
| Primary text | `#EDF2F7` | values, title, selected label |
| Secondary text | `#A6B2BF` | labels, blocked values |
| Tertiary text | `#808C99` | notes, headers, key hints |
| Accent | `#E6B03B` | selected-row bar, filled slider track, primary action |
| Hairline | `#59616B` at 25% | menu separator |
| Slider track | white at 20% | the unfilled slider track |
| Scrim | black at 62% | behind the settings dialog and palette |

The kit derives the remaining states, text and surfaces from
`Kit::from_palette_focus` with `PaletteFocus::Accent`. The pins above override the
measured overlay roles. The status action row's primary `Settings` button reads
`bg_accent` and `text_inverse`; the dialog's `Resume` uses the kit Submit tokens
`bg_icon_button_contrast`, `submit_fg`, and `submit_icon`. The neutral action
reads `bg_button_neutral` and `text_base`. The rune-fx demo asks for `#7C5CFF`
with a `#F4F0FF` core; it is not part of the default interface.

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
row; selection must move it to secondary or primary. The HUD promotes tertiary
text to secondary below 94% opacity, and the floor is checked on the capture
because the surface is translucent.

## Choosing a colour

- A value, a title, or a selected label: primary.
- A label or a blocked value: secondary.
- A note, a header, or a key hint: tertiary.
- The selected-row bar, the filled slider track, and the primary action: accent.
- A separator: hairline. A slider track: the white 20% token.
- A kit surface: the matching `Kit` token. The status panel: `hud_surface()`.

## Bans

- No colour literal outside `ui/shim/src/theme.rs` and the game's content data.
- No hex or RGB literal in a view or component.
- No third hue in the view. The scene has its own palette; do not copy a world
  colour into the view and do not copy the accent into the world.
- No colour-only signal. Selection keeps both the raised surface and the accent
  bar.
- No dark-mode variant. There is one view and the scene is its backdrop.
