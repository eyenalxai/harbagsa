# Spacing and surfaces

Rune lays out the view. The numbers below are Rune points in
`ui/shim/src/views.rs` and `ui/shim/src/palette.rs`, not pixels computed in
Odin. Rune scales the view by `scale = clamp(target_height / 720, 1, 2)` and
passes it to `Env::new`; a 720p target gets 1, a 1080p target 1.5, a 1440p target
2.

## The scale

| Value | Use |
| --- | --- |
| 2 | the selection bar width |
| 4 | menu row padding |
| 6 | status panel gap between rows |
| 8 | status action gap, menu gap, button padding |
| 12 | status panel inset and padding, gap between a menu label and its value |
| 16 | bottom action column padding, menu panel padding |

Use the nearest existing value. A new number is a layout change, not a token
addition.

## Status panel

```
┌──────────────────────────────────────────┐ 12 pt from the top-left corner
│ 12 pt padding                            │
│ row                                      │
│ row                                      │
└──────────────────────────────────────────┘
```

- Width 380 points.
- Inset `12, 12` from the target's top-left.
- Padding 12, row gap 6.
- The bottom action row is a separate full-width column: `justify_end`,
  `items_center`, padding 16, gap 8.
- The inspector rail is 320 points wide, inset 12 from the top and right. Its
  content is capped below the bottom action row and scrolls only when the
  sections overflow.

The status panel is translucent. The dialog surface is opaque. A selected row
or card lifts to the raised surface; it does not get a border.

## Settings dialog

- Width 520 points, centred on the target with a 16 point gutter.
- The scrim covers the whole target.
- Header: 16 point padding, title 15/20, description 13/20, close control 20.
- Body padding 20, section gap 4.
- A section header is 32 points high; a control row is 40 points high with a
  160 point label column and a 240 point control column.
- Window mode and Sprint mode are 240 point segmented controls.
- Display and Resolution are 240 point field selects.
- The HUD opacity slider is the 480 point body width: a 16 point label/value line
  above a 24 point track hit area with a 4 point track and a 14 point knob.
- The Controls section is two lines of three `Keybind` pairs.
- The footer is right-aligned with a 28 point (`ControlSize::Large`) Resume button
  and a top hairline.

## Object palette

- Width 640 points, centred on the target.
- Panel padding 16, gap 12.
- Grid 3 columns × 4 rows; card 120×92, gap 8.
- Preview 220 points wide, the height of the grid.
- Footer holds the key hints and the `Place` button.

The selected card uses the raised surface and a 2-point accent bar. Hover uses
the fill overlay; focus uses the 2-point focus ring. The grid is 376
points wide and the preview adds 220 with a 12-point gap, so the inner width is
608 and the panel is 640 with its padding. At 800×600 the panel is 640×517 with
80 points of horizontal margin and 41 points above and below.

## Surfaces

| Surface | Fill | Edge |
| --- | --- | --- |
| Status panel | status surface, 70-100% | none |
| Settings dialog | dialog surface over the scrim | kit elevation |
| Palette | menu surface over the scrim | 1 point hairline separator |
| Selected row or card | raised surface | 2 point accent bar on the leading edge |
| Notice and capture hint | no box of their own | text on the action column |

Kit surfaces use the kit radius, elevation, and motion; the status panel keeps
its square translucent fill. Panels use the kit's 6-point radius and overlay
elevation; cards use the same radius and are flat. Motion follows the
reduce-motion setting. There is no gradient.

## Bans

- No per-row margin. The parent owns the gap.
- No measured width in Odin. Rune sizes the panel from its content.
- No clipping. The settings dialog fits at 800x600; Rune scales the whole view, so
  a larger target keeps the same proportions.
- No Odin layout pass and no hit-test rectangle. Rune owns both.
