# Spacing and surfaces

Rune lays out the view. The numbers below are Rune points in
`ui/shim/src/views.rs`, `ui/shim/src/settings.rs`, `ui/shim/src/palette.rs`, and
`ui/shim/src/inspector.rs`, not pixels computed in Odin. Rune scales the view by
`scale = clamp(target_height / 720, 1, 2)` and passes it to `Env::new`; a 720p
target gets 1, a 1080p target 1.5, a 1440p target 2.

## The scale

| Value | Use |
| --- | --- |
| 2 | the selection bar width; the focus ring |
| 4 | section gap; slider heading gap; card content gap |
| 6 | status panel and inspector gap |
| 8 | action column gap; palette grid gap; preview gap |
| 12 | status inset and padding; inspector inset and padding; palette panel gap; row label gap |
| 16 | action column padding; palette panel padding; section header line height |
| 20 | settings body padding |
| 32 | section header height |
| 40 | settings control row height |

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
- The bottom action column is a separate full-width column: `justify_end`,
  `items_center`, padding 16, gap 8.
- The inspector rail is 320 points wide, inset 12 from the top and right. Its
  content is capped at `target height - 24 - 60` with a 240-point floor and
  scrolls only when the sections overflow.

The status panel is a local kit-styled surface: the kit medium radius, the kit
raised elevation, and `hud_surface(opacity)` at 70-100 percent. It is not a kit
`Card`; it keeps its own 380-point density and row layout. The dialog surface is
opaque. A selected card lifts to the raised surface and gets the accent bar; it
does not get a border.

## Settings dialog

- Width 520 points, centred on the target with a 16 point gutter.
- The scrim covers the whole target.
- The panel uses the kit medium radius and overlay elevation.
- Header: 16 point padding, title 15/20, description 13/20, close control 20.
- Body padding 20, section gap 4.
- A section header is 32 points high; a control row is 40 points high with a
  160 point label column and a 240 point control column.
- Window mode and Sprint mode are 240 point segmented controls.
- Display and Resolution are 240 point field selects.
- The HUD opacity slider is the 480 point body width: a 16 point label/value line
  above a 24 point slider row with a 4 point track and a 14 point knob.
- The Controls section is two lines of three `Keybind` pairs.
- The footer is right-aligned with a 28 point (`ControlSize::Large`) Resume button
  and a top hairline.

## Object palette

- Width 640 points, centred on the target.
- Panel padding 16, gap 12.
- Grid 3 columns; card 120×92, gap 8. The row count is
  `ceil(items / 3)`, so eleven prefabs fill four rows.
- Preview 220 points wide, the height of the grid; its isometric art is 168
  points high.
- Footer holds the key hints and the `Place` button.

The selected card uses the raised surface and a 2-point accent bar. Hover uses
the fill overlay; press uses the pressed fill; focus uses the 2-point focus ring.
The grid is 376 points wide and the preview adds 220 with a 12-point gap, so the
inner width is 608 and the panel is 640 with its padding. At 800×600 the panel is
640×517 with 80 points of horizontal margin and 41 points above and below.

## Surfaces

| Surface | Fill | Edge |
| --- | --- | --- |
| Status panel | status surface, 70-100% | kit raised elevation, medium radius |
| Settings dialog | dialog surface over the scrim | kit overlay elevation, medium radius |
| Palette | dialog surface over the scrim | kit overlay elevation, medium radius, title hairline |
| Inspector rail | HUD surface at 96% | kit raised elevation, 1 point hairline border |
| Selected card | raised surface | 2 point accent bar on the leading edge |
| Notice and capture hint | no box of their own | text on the action column |

Kit surfaces use the kit radius and elevation. The settings dialog is a kit
`Dialog`; the status panel, palette shell, and inspector rail are local surfaces
that borrow the radius and elevation tokens. Motion follows the reduce-motion
setting. The world has no gradient. A view gradient lives inside a kit control
such as the `Switch` track or the `Button` skin; do not paint one on a panel or
card.

## Bans

- No per-row margin. The parent owns the gap.
- No measured width in Odin. Rune sizes the panel from its content.
- No clipping. The settings dialog and the palette fit at 800x600; the inspector
  scrolls. Rune scales the whole view, so a larger target keeps the same
  proportions.
- No Odin layout pass and no hit-test rectangle. Rune owns both.
