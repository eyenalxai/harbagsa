# Spacing and surfaces

Rune lays out the view. The numbers below are Rune points in
`ui/shim/src/lib.rs`, not pixels computed in Odin. Rune scales the view by
`scale = clamp(target_height / 720, 1, 2)` and passes it to `Env::new`; a 720p
target gets 1, a 1080p target 1.5, a 1440p target 2.

## The scale

| Value | Use |
| --- | --- |
| 2 | the selected-row accent bar width |
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

The status panel is translucent. The menu surface is opaque. A selected row
lifts to the raised surface; it does not get a border.

## Settings menu

- Width 430 points, centred on the target.
- The scrim covers the whole target.
- Panel padding 16, row gap 8.
- A row pads 4 points and gaps label and value by 12.
- The selected row has a 2 point accent bar and an 18 point label-height band.
- The slider track is 4 points tall under the value row; the filled width is
  `ratio * 390`.
- The hint grid puts three hint pairs on a line.

## Object palette

The palette reuses the menu panel with the same 430 point width, padding, and
gap. Each item is a row. The selected row uses the same raised surface and accent
bar. The body note and hints sit below the list.

## Surfaces

| Surface | Fill | Edge |
| --- | --- | --- |
| Status panel | status surface, 94% | none |
| Menu and palette | menu surface over the scrim | 1 point hairline separator |
| Selected row | raised surface | 2 point accent bar on the leading edge |
| Notice and capture hint | no box of their own | text on the action column |

No rounded panel, no shadow, no gradient. The action buttons are the only
rounded edges Rune draws.

## Bans

- No per-row margin. The parent owns the gap.
- No measured width in Odin. Rune sizes the panel from its content.
- No clipping. The menu fits at 800x600; Rune scales the whole view, so a larger
  target keeps the same proportions.
- No Odin layout pass and no hit-test rectangle. Rune owns both.
