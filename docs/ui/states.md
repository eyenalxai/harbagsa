# Row states

A row is drawn from six inputs: `kind`, `numeric`, `selected`, `blocked`,
`value_align`, and `frame_width`. `kind`, `numeric`, and `blocked` live on
`ui.Row`; `selected`, `value_align`, and `frame_width` live on `Rows_Options`. A
`Slider` also reads `ratio` and `ticks` to draw its track.

`selected` matches an index only when `frame_width > 0` and the kind is
`Setting`, `Action`, or `Slider`. A zero `frame_width` means the row block is
its own frame: the dividers use the measured block width and no band is drawn.
`value_align` has two values: `.Left` starts the value at `value_column`, and
`.Right` ends it at `value_column + value_width`. The HUD uses `.Left`; the
settings menu uses `.Right`.

## The state table

| State | Rows | Surface | Accent bar | Label | Value |
| --- | --- | --- | --- | --- | --- |
| Default | `Setting`, `Action`, `Metric`, `Slider` | none | none | `text_secondary` | `text_primary` |
| Selected | `Setting`, `Action`, `Slider` | `surface_raised` | yes | `text_primary` | `text_primary`, or `text_secondary` if blocked |
| Detail | `Detail` | none | none | `text_tertiary` caption | `text_tertiary` caption |
| Header | `Header` | none | none | `text_tertiary` caption caps | no value |
| Blocked | `Display`, `Resolution` | unchanged | unchanged | unchanged | `text_secondary` |
| Slider | `Slider` | as Default or Selected | as Selected | as Default or Selected | `text_primary`, plus the track |

A default label uses `type_body_strong` for `Setting`, `Action`, and `Slider`, and
`type_body` for `Metric`. A `Slider` row uses the text state above it and adds
the track, ticks, fill, and knob below. A blocked row keeps the band when it is
selected. `Action` rows carry no value; `Divider` rows draw only the separator
line.

## Selection

Selection takes two signals: the row lifts to `surface_raised`, and the accent
bar fills its leading edge. The label lifts to `text_primary`; the value keeps
its own style. Neither signal alone is selection.

The band extends `spacing.xxs` above and below the row height. It spans
`frame_x .. frame_x + frame_width`, so it shares an edge with every divider.

## Blocked rows

A blocked value draws in `text_secondary`, never `text_tertiary`: tertiary is
3.9:1 on `surface_raised`, under the 4.5:1 text floor.

Blocked rows stay selectable and keep the band. Only `Display` and `Resolution`
set `Row.blocked`. `Display` is blocked with one display; `Resolution` is blocked
with no modes, or with one mode while Windowed. The Type weight row is not
dimmed at the axis ends because one direction still moves; the status note is
the signal there.

## Change results

`menu_change_setting` returns `Change_Result`:

- `Not_A_Setting`: the menu is closed, `Resume` is selected, or the direction is
  zero.
- `Changed`: the setting changed.
- `Blocked`: the value cannot change. The call sets `Menu_State.status`.

A blocked change sets one of five strings:

- `"One display · nothing to change"`
- `"No modes · nothing to change"`
- `"One mode · nothing to change"`
- `"Minimum weight · nothing to change"`
- `"Maximum weight · nothing to change"`

The status note holds for two seconds of frame time. A new blocked press
restarts the hold; a successful change clears it immediately. When the hold
ends, the default note returns.

## Applying a change

A change applies immediately. There is no OK, Cancel, or dirty state, and
closing the menu does not revert anything. `Shift+R` resets the scene, not the
settings.

One press is one action. `Left` and `Right` step a setting; `Enter` tries to
change the selected setting, or closes on `Resume`. The slider also accepts a
drag, because the pointer is an addition, not a requirement. Key repeat does not
exist, and every list is short: eight items and eighteen hint cells.
