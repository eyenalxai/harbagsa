# Rows, controls, and states

The view is built from read-only rows and kit controls. The shim reads flat
values and decides the surface, text colour, and kit state. Rune owns hover,
press, focus, drag, and scroll; Odin owns the values and the open flags.

## The row kinds

A row is drawn from `kind`, `numeric`, and `blocked`. The status panel and the
keyboard-only debug rows use them as read-only text:

| Kind | Value | Reads as | Produced today |
| --- | --- | --- | --- |
| `Setting` | 0 | label left, value right | no |
| `Action` | 1 | label only, runs on activate | no |
| `Metric` | 2 | label and value in the body style | yes |
| `Detail` | 3 | label and value, quieter | yes |
| `Divider` | 5 | one separator line | yes |
| `Header` | 6 | quiet section label | yes |

Every row carries `flags` bit 0 = numeric and bit 1 = blocked. `Setting` and
`Action` stay in the closed wire enum, but no surface emits them today. Rows are
read-only: no row is focusable, selectable, or clickable. The old row band and
list selection are gone. A `Header` or `Detail` label uses tertiary text, the
other labels use secondary, a value uses primary unless the row is blocked, and
a numeric value draws in Geist Mono.

## Kit control states

Kit controls carry their own hover, press, focus, checked or selected, and
disabled states. Hover adds the kit fill overlay; press uses the kit pressed
fill; focus draws a 2-point accent ring. The action fires on release inside the
control, not on press. Hover and press are feedback, never the only way to reach
an action or read a value.

A `SegmentedControl` marks its active segment, a `Select` marks the current item,
a `Switch` shows its checked track, and a disabled control dims through the kit
layer opacity. Do not paint a second state palette in the Odin tree.

The palette uses the local selection helper instead of the kit control states:
the selected card lifts to the raised surface and carries a 2-point accent bar.
Hover adds the fill overlay, press uses the pressed fill, and focus draws the
2-point ring. Selection is persistent; hover is transient.

## Settings dialog

Window mode and Sprint mode are `SegmentedControl`s. Display and Resolution are
Select fields over a menu list; each item keeps its own index, so duplicate or
truncated names still choose the right row. The current item is marked. The
Display Select is disabled with zero or one display. The Resolution Select is
disabled with no modes or with one mode while Windowed. A current resolution
that is not in the list stays in the field and the Display header says
`Resolution unavailable`; picking a listed mode clears it.

HUD opacity is the local Slider. It runs from 70 to 100 percent in one-point
steps, and the 24-point slider row is the hit area; the label and percentage row
never changes the value. It drags from the thumb, jumps to a track press, steps
with Left and Right, repeats while held, and restores the pre-drag value when Esc
cancels the drag. It commits live. The value draws in Geist Mono. At 70 and 100
percent the Interface header shows `Minimum` or `Maximum`, and the step key is a
no-op. Below 94 percent the status HUD promotes its tertiary text to secondary;
the surface opacity follows the setting, and the text floor is checked on the
capture, not on the authored hex alone.

Reduce motion is a `Switch`. It sets `Cx::reduced_motion` for the Rune view:
kit geometry snaps and opacity fades. The status panel itself does not animate.
The setting applies live.

Resume is a footer Submit `Button`. `Esc`, the header close control, and Resume
dismiss the dialog. Rune traps Tab focus inside the modal, arrows step the
focused control or slider, and Enter or Space activates the control. `cx.web_focus`
makes Enter press a focused Button or Switch as a web form does; Space already
presses any focused control. `Esc` dismisses an open Select before the dialog.

The dialog has no row selection to block. A blocked choice is a disabled Select
or the Minimum/Maximum header at the ends of the opacity slider. The harness's
direct `menu_change_setting` path still returns a blocked result and sets the
dialog note; a failed window apply sets the same note. The note holds for two
seconds of frame time, a new blocked press restarts the hold, and a successful
change clears it.

## Object palette

The palette is a local modal built from the kit scrim, dialog surface, radius,
and elevation. It is a three-column grid of cards with a preview beside it, not
a list. Number keys 1-9 select the first nine cards; the last two carry a dash
badge and are reached with the arrow keys. Clicking a card returns
`Palette_Select` and updates the preview; it does not arm the placement. The
Place button, or Enter on the game keyboard path, returns `Palette_Pick` and
arms the selected prefab. The scrim returns `Palette_Close`; Esc closes the
palette through the game cancel path. The footer carries the key hints.

The grid and the modal are never shown while the inspector rail or the settings
dialog is open. Opening the palette closes the inspector.

## Inspector rail

`I` opens the 320-point rail in debug mode and frees the pointer; `Esc` closes
it and restores capture. The rail is hidden while Settings or the palette is
open. Opening it cancels an active tool or drag; opening the palette, arming a
placement, or opening Settings closes it. While the rail owns the frame, its
pointer stays free and the world pointer path does not run.

The Object section shows the selected prefab and id, a body control, an absolute
yaw slider, Duplicate, and Delete. With no selection it says
`No object selected`. A non-lamp body is a `SegmentedControl`; a lamp body is a
read-only row that says it follows the kind. The yaw slider runs from 0 to 359
degrees in one-degree steps and sends the absolute value. Duplicate and Delete
are small kit `Button`s.

The Placement section is read-only: the next prefab, height, yaw, and snap.

The Lamp section appears only for a selected lamp. Its kind is a
`SegmentedControl`, its five colours are fixed swatches with the accent border
on the selected one, and intensity and range are sliders. Intensity runs from
0.2 to 4.0 in 0.1 steps; range runs from 2 to 20 metres in 1-metre steps.

The Debug section holds the type weight slider and the physics debug `Switch`.
Type weight runs from 100 to 900 in 25-point steps. The inspector sliders preview
while dragging and commit on release; a keyboard step commits immediately.

The rail scrolls only when its sections overflow; it never clips. The close
control returns `Toggle_Inspector`.

## Actions

The shim returns a flat queue. The full vocabulary is `UI_Action_Kind` in
`src/renderer/ui_frame.odin`:

| Kind | Action | Applied by |
| --- | --- | --- |
| 1 | `Close_Menu` | close the settings dialog when it is open |
| 2 | `Debug_Inspector` | enter debug mode when needed and open the inspector |
| 3 | `Palette_Select` | select and preview the palette item at `value` |
| 4 | `Palette_Close` | close the palette |
| 5 | `Settings_Set` | `settings_set` with a setting id, an option index or boolean, and an opacity scalar |
| 6 | `Type_Weight_Set` | `settings.type_weight` with the slider scalar |
| 7 | `Palette_Pick` | arm the placement from the selected palette item |
| 8 | `Object_Set` | `Set_Body` or the absolute `Set_Selected_Yaw` for the selected object |
| 10, 11 | `Object_Duplicate`, `Object_Delete` | the selected object's history action |
| 12 | `Lamp_Set` | the selected lamp's intensity or range |
| 13, 14 | `Lamp_Kind`, `Lamp_Color` | the selected lamp's kind or fixed colour |
| 15 | `Toggle_Inspector` | open or close the inspector rail |
| 16 | `Physics_Debug` | the physics debug draw switch, independent of debug mode |

A changed window mode, display, or resolution also calls
`apply_window_settings`; the other actions do not touch the window.

The game applies the queue after `ui_draw` and then clears it. A click that
produces no action is a harness error; the keyboard path never depends on a
click.

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

## Input

The settings dialog owns its keyboard path through Rune: Tab traps focus inside
the modal, arrows step the focused control or slider, Enter or Space activates
the control, and Esc dismisses the open Select before the dialog. The palette
keeps its own game keyboard path: number keys 1-9 select, arrows step, and Enter
picks. The pointer may click a palette card, the Place button, or any dialog
control while the cursor is free; while it is captured, the pointer belongs to
the camera. Drag and key repeat are part of the Slider, not a separate input mode.

The resolver order is Settings, inspector, palette, placement, then world. `I`
toggles the inspector in debug mode and `Esc` closes it before it opens Settings.
While the inspector owns the frame, its pointer stays free and the world pointer
path does not run. Opening the inspector cancels an armed placement or a world
drag; opening the palette, arming a placement, or opening Settings closes it.

The status action row's `Debug` button is pointer-reachable only when the cursor
is free. Press `F2` and then `I` for the keyboard path.
