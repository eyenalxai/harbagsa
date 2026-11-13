# Row states and actions

A row is drawn from `kind`, `numeric`, and `blocked`. The list view supplies the
local selected index. The shim reads the flat values and decides the surface and
text colour.

## The row kinds

| Kind | Value | Reads as | Selectable |
| --- | --- | --- | --- |
| `Setting` | 0 | label left, value right | yes |
| `Action` | 1 | label only, runs on activate | yes |
| `Metric` | 2 | label and value in the body style | no |
| `Detail` | 3 | label and value, quieter | no |
| `Divider` | 5 | one separator line | no |
| `Header` | 6 | quiet section label | no |

Every row carries `flags bit 0 = numeric` and `flags bit 1 = blocked`.

## Selection

Selection takes two signals: the row lifts to the raised surface, and a 2 point
accent bar fills its leading edge. The label becomes primary; the value keeps its
own colour. Neither signal alone is selection.

Only `Setting` and `Action` rows are selectable. `Header`, `Divider`, `Metric`,
and `Detail` never take the band.

## Blocked rows

A blocked value draws in secondary text. Display is blocked with one display;
Resolution is blocked with no modes, a current mode that is not listed, or one
mode while Windowed. A missing current mode keeps its value in the field and the
Display header says `Resolution unavailable`. HUD opacity is blocked at 70 and
100 percent; the Interface header shows `Minimum` or `Maximum` there and the step
key is a no-op.

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

- `Not_A_Setting`: the settings dialog is closed, `Resume` is selected, or the
  direction is zero.
- `Changed`: the setting changed through `settings_set`.
- `Blocked`: the value cannot change. The call sets `Menu_State.status`.

A blocked change sets one of six strings:

- `"One display · nothing to change"`
- `"No modes · nothing to change"`
- `"One mode · nothing to change"`
- `"Current mode is not listed · nothing to change"`
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
| 1 | `Close_Menu` | close the settings dialog when it is open; the status row's `Close` is a handled no-op while it is closed |
| 5 | `Settings_Set` | `settings_set` with a setting id, an option index or boolean, and an opacity scalar |

A changed window mode, display, or resolution also calls
`apply_window_settings`; the other actions do not touch the window.

The game applies the queue after `ui_draw` and then clears it. A click that
produces no action is a harness error; the keyboard path never depends on a
click.

## Input

The Settings dialog owns its keyboard path through Rune: Tab traps focus inside
the modal and reaches the switch and Resume, arrows step the focused control or
slider, Enter or Space activates the control, and Esc dismisses the open Select
before the dialog. Enter presses a focused button or switch like a web form. Esc
opens Settings when nothing owns the keyboard. The pointer may click any dialog
control while the cursor is free; while it is captured, the pointer belongs to
the camera. Drag and key repeat are part of the Slider, not a separate input
mode.
