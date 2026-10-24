# Components

Four surfaces. Each one exists for a reason; if a new panel is not one of these,
read [README.md](README.md#adding-a-surface) first.

## Status panel

Use for the player's live state. It is the only persistent overlay. It draws in
the top-left margin and never moves.

```odin
theme := o.theme
padding := theme.spacing.lg
options := Rows_Options{value_align = .Left}
layout := rows_measure(&o.atlas, theme, rows, options)

x := theme.spacing.md
y := theme.spacing.md
hud_emit_rect(o, x, y, layout.width + padding * 2, layout.height + padding * 2, theme.surface_hud)
hud_emit_frame(o, x, y, layout.width + padding * 2, layout.height + padding * 2, theme.hairline, theme.line_hairline)
rows_emit(o, theme, x + padding, y + padding, layout, rows, options)
```

Incorrect: measuring one line and sizing the panel from it.

```odin
width := text_measure(&o.atlas, theme.type_body, rows[0].value)
hud_emit_rect(o, x, y, width + 20, 140, {0.01, 0.015, 0.02, 0.65})
```

The panel resizes as soon as a value grows a character, and the colour is a
literal that no longer matches the theme.

## Capture hint

Use when the cursor is not captured and the player needs one instruction. It is
transient: it disappears the moment the player clicks.

```odin
box_y := height * 0.5 + hud_crosshair_reach(theme) + theme.spacing.md
```

Incorrect: centring it on the crosshair.

```odin
box_y := height * 0.5 - box_height * 0.5
```

The crosshair draws last, so it cuts through the text.

## Crosshair

Always present while the menu is closed. Four arms, one hairline thick, with a
dark outline so it reads against sky and floor alike. Arm and gap scale with
density.

Do not animate it, do not give it a colour, and do not draw it above a menu.

## Settings panel

Use for a paused decision. It draws a scrim over the whole target, then the
panel, then the rows, then the legend, then the note.

Order matters and is fixed: scrim, panel, ring, title, separator, rows, legend,
note. Each later element lands on top of the earlier ones.

```odin
hud_emit_rect(o, 0, 0, width, height, theme.scrim)
hud_emit_rect(o, panel_x, panel_y, panel_width, panel_height, theme.surface_menu)
hud_emit_frame(o, panel_x, panel_y, panel_width, panel_height, theme.hairline, theme.line_hairline)
```

Incorrect: filling a larger rect behind the panel to fake a border.

```odin
hud_emit_rect(o, panel_x - 1, panel_y - 1, panel_width + 2, panel_height + 2, theme.line_hairline)
hud_emit_rect(o, panel_x, panel_y, panel_width, panel_height, theme.surface_menu)
```

The panel is opaque but the ring is 9% white; the fill shows through and the edge
turns grey instead of a hairline.

## Selection band

Use on a `Setting`, `Action`, or `Slider` row only. Two signals together: the row lifts to
`surface_raised`, and a two-pixel `accent` bar sits on its leading edge.

```odin
if options.frame_width > 0 && index == options.selected && selectable {
	hud_emit_rect(o, options.frame_x, y - pad, options.frame_width, height + pad * 2, theme.surface_raised)
	hud_emit_rect(o, options.frame_x, y - pad, max(theme.hairline * 2, 2), height + pad * 2, theme.accent)
	row_style.color = theme.text_primary
}
```

Incorrect: a bright band behind white text, or a colour change alone.

```odin
hud_emit_rect(o, x, y, width, height, {0.28, 0.45, 0.6, 0.45})
```

That composite measures 4.2:1 against white, under the 4.5:1 floor, and it was the
original bug.

## Legend grid

Use for the control list, and only there. Keys are right-aligned against their
action so a one-letter key does not float in a column sized by the longest
shortcut.

```odin
text_emit_aligned(o, cell_x + grid.key_width[column], baseline, keys_style, cell.keys, .Right)
text_emit(o, cell_x + grid.key_width[column] + theme.spacing.xs, baseline, action_style, cell.action)
```

Incorrect: padding a string with runs of spaces.

```odin
text_emit(o, x, baseline, style, "WASD move    Mouse look    Left click capture")
```

A proportional font gives every run of spaces a different width, so nothing lines
up; the original panel shipped exactly this.

## Rows

`ui.Row_Kind` is closed. Each kind has one meaning.

| Kind | Reads as | Selectable |
| --- | --- | --- |
| `Setting` | label left, value right | yes |
| `Action` | label only, runs on activate | yes |
| `Metric` | label and value in body size | no |
| `Detail` | label and value in caption, dimmed | no |
| `Slider` | label and number, full-width ticked track below | yes |
| `Header` | tracked capitals, starts a section | no |
| `Divider` | one separator line | no |
| `Spacer` | a gap, for rhythm only | no |

An unlisted kind does not exist. If a surface needs one, extend `Row_Kind` and all
four of `row_label_style`, `row_value_style`, `row_gap`, and `row_height` in the
same change. A kind that only two of the four know about draws at the wrong
height. A kind that draws a control also needs its emitter: the `Slider` adds
`rows_emit_slider` and publishes its travel rect for the pointer.

## Slider row

Use for one continuous value with named stops. The settings menu uses it for the
Type weight. At density 1:

- Line one is 22.5 px tall. The label sits at the left in `type_body_strong`,
  the value right-aligned at the inner edge in `type_body`, numeric.
- A 6 px gap, then a 12 px track zone: a 2 px track, nine 1x6 ticks, and an 8x8
  knob. The row is 40.5 px tall.
- The track spans the panel inner width. The knob travel is `inner_width - knob`;
  stop `i` centres at `inner_x + knob / 2 + i * travel / 8`. The fill runs from
  the inner edge to the knob centre.
- The track uses `line_separator`; the ticks use `text_tertiary`; the fill uses
  `text_secondary`; the knob uses `text_primary`. `accent` stays the selection
  bar.
- The selection band grows to 44.5 px and still carries the 2 px accent bar.

Incorrect: drawing the fill in `accent`, or sizing the track from the value
column. The track is the inner width, and a selected row already has the accent
bar.
