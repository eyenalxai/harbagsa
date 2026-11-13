# Row states and actions

A row is drawn from `kind`, `numeric`, `selected`, `blocked`, and `ratio`. The
first four live in `ui.Row`; `selected` is the local list index. The shim reads
the flat values and decides the surface, text colour, and track.

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
Resolution is blocked with no modes or with one mode while Windowed. HUD opacity
is blocked at 70 and 100 percent; the status note is the signal there.

## Slider

The Settings dialog's HUD opacity control is the local Slider. It runs from 70
to 100 percent in one-point steps. It drags from the thumb, jumps to a track
press, steps with Left and Right, repeats while held, and restores the pre-drag
value when Esc cancels the drag. The value draws in Geist Mono. The track spans
the dialog body, the unfilled track is white at 20%, and the filled width and
knob follow the value in the accent colour.

Below 94 percent the status HUD promotes its tertiary text to secondary. The
surface opacity follows the setting; the text floor is checked on the capture,
not on the authored hex alone.

## Change results

`menu_change_setting` is the harness's direct path and returns `Change_Result`:

- `Not_A_Setting`: the menu is closed, `Resume` is selected, or the direction is
  zero.
- `Changed`: the setting changed through `settings_set`.
- `Blocked`: the value cannot change. The call sets `Menu_State.status`.

A blocked change sets one of five strings:

- `"One display · nothing to change"`
- `"No modes · nothing to change"`
- `"One mode · nothing to change"`
- `"Minimum opacity · nothing to change"`
- `"Maximum opacity · nothing to change"`

A window apply can fail after `Changed`: the setting reverts, the window is
restored, and the status note names the failed step. A failed restore is named in
the same note. The launch path shows the failure as a notice instead.

The status note holds for two seconds of frame time. A new blocked press restarts
the hold; a successful change clears it.

## Actions

The shim returns a flat queue. The full vocabulary is `UI_Action_Kind` in
`src/renderer/ui_frame.odin`; the Settings dialog uses:

| Kind | Action | Applied by |
| --- | --- | --- |
| 1 | `Close_Menu` | close the settings dialog when it is open |
| 5 | `Settings_Set` | `settings_set` with a setting id, an option index or boolean, and an opacity scalar |

A changed window mode, display, or resolution also calls
`apply_window_settings`; the other actions do not touch the window.

The game applies the queue after `ui_draw` and then clears it. A click that
produces no action is a harness error; the keyboard path never depends on a
click.

## Input

The Settings dialog owns its keyboard path through Rune: Tab traps focus inside
the modal, arrows step the focused control or slider, Enter or Space activates
it, and Esc dismisses the open Select before the dialog. Esc opens Settings when
nothing owns the keyboard. The pointer may click any control; every pointer
action keeps a keyboard path. Drag and key repeat are part of the Slider, not a
separate input mode.
