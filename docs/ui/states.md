# Row states and actions

A row is drawn from `kind`, `numeric`, `selected`, `blocked`, and `ratio`. The
first four live in `ui.Row`; `selected` is the menu's index. The shim reads the
flat values and decides the surface, text colour, and track.

## The row kinds

| Kind | Value | Reads as | Selectable |
| --- | --- | --- | --- |
| `Setting` | 0 | label left, value right | yes |
| `Action` | 1 | label only, runs on activate | yes |
| `Metric` | 2 | label and value in the body style | no |
| `Detail` | 3 | label and value, quieter | no |
| `Slider` | 4 | label and number, track below | yes |
| `Header` | 6 | quiet section label | no |
| `Divider` | 5 | one separator line | no |

Every row carries `flags bit 0 = numeric` and `flags bit 1 = blocked`.
`ui.Row.ratio` is 0..1 and drives the slider.

## Selection

Selection takes two signals: the row lifts to the raised surface, and a 2 point
accent bar fills its leading edge. The label becomes primary; the value keeps its
own colour. Neither signal alone is selection.

Only `Setting`, `Action`, and `Slider` rows are selectable. `Header`, `Divider`,
`Metric`, and `Detail` never take the band.

## Blocked rows

A blocked value draws in secondary text. Display is blocked with one display;
Resolution is blocked with no modes or with one mode while Windowed. The Type
weight row is not dimmed at the axis ends because one direction still moves; the
status note is the signal there.

## Slider

The Type weight row is the only slider. Left and Right step by 10 within
100..900. The value is the number only. The track spans the panel inner width,
the unfilled track is white at 20%, and the filled width follows the ratio in the
accent colour. There is no knob and no tick mark. The slider has no drag path;
the menu is keyboard-driven and the Rune view does not return a drag action.
The Type weight value applies to every Rune text node as a span weight. A value
of 400 leaves Rune's default.

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

A window apply can fail after `Changed`: the setting reverts, the window is
restored, and the status note names the failed step. A failed restore is named in
the same note. The launch path shows the failure as a notice instead.

The status note holds for two seconds of frame time. A new blocked press restarts
the hold; a successful change clears it.

## Actions

The shim returns a flat queue:

| Kind | Action | Applied by |
| --- | --- | --- |
| 1 | `Close_Menu` | close the settings menu when it is open; ignored from the status view, where the menu is already closed |
| 2 | `Toggle_Debug` | toggle the debug camera |
| 3 | `Palette_Select` | arm the palette item at `value` |

The game applies the queue after `ui_draw` and then clears it. A click that
produces no action is a harness error; the keyboard path never depends on a
click.

## Input

One press is one action. Up and Down move the selection, Left and Right change a
setting, Enter changes or closes, and Esc opens or closes the menu. The pointer
may click a palette row or an action button. There is no hover, no key repeat,
and no drag.
