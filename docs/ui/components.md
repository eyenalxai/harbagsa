# Components

Seven surfaces live in one Rune view. Each exists for a reason; if a new one is
not one of these, read [README.md](README.md#adding-a-surface) first. The view is
built in `ui/shim/src/views.rs`, the palette grid and preview in
`ui/shim/src/palette.rs`, the debug rail in `ui/shim/src/inspector.rs`, and the
data is in `src/ui/ui.odin`.

## Status panel

Use for the player's live state. It is the persistent top-left surface while the
settings dialog is closed. It draws `ui.Hud.rows` as a list and appends the notice, the
capture hint, and the action row below the panel.

The row kinds map to Rune elements:

- `Divider`: a 1 point full-width line.
- `Header`: tertiary text.
- `Setting`, `Action`, `Metric`, `Detail`: a label row with a spacer and a value.

The action row has one primary button: `Debug` returns `Debug_Inspector`, which
enters debug mode when needed and opens the inspector rail. The settings dialog
closes with `Esc`, its close control, or `Resume`. The row is drawn while the
pointer is captured; live pointer events reach it only when the cursor is free.

Incorrect: measuring a row in Odin and sizing a rectangle from it. Rune measures
the text.

## Settings dialog

Use for a paused decision. Settings is a `rune-kit::Dialog` over a scrim. The
dialog width is 520 points and the body holds three sections: Display,
Interface, and Controls. Window mode and Sprint mode are `SegmentedControl`s;
Display and Resolution use the kit Select field over a menu list whose items keep
their own indices, so duplicate or truncated names still choose the right row;
HUD opacity is the local Slider;
Reduce motion is a `Switch`; Resume is a footer `Button`. If the current
resolution is not in the display's mode list, the field keeps it and the Display
header says `Resolution unavailable`. `Esc`, the header close
control, and Resume dismiss it.

The HUD opacity Slider runs from 70 to 100 percent in one-point steps. Only the
track is the hit area: it drags from the thumb, jumps on a track press, steps
with Left and Right, repeats while held, and restores the pre-drag value when Esc
cancels the drag. The label and percentage row never changes the value. Its value
draws in Geist Mono. At 70 and 100 percent the Interface header shows `Minimum`
or `Maximum`, so the blocked end is visible. Below 94 percent the status HUD's
tertiary text promotes to secondary, keeping the text floor on the translucent
surface.

The dialog owns its keyboard path: Rune traps focus, draws the focus ring, and
routes arrows, Enter, and Space to the focused control. `src/game/settings_view.odin`
names every option and index; the shim never derives a display or mode name. The
Controls section is a compact reference, not the full shortcut list; the full
list stays in `README.md`.

Incorrect: measuring a row in Odin and sizing a rectangle from it. Rune measures
the text. Incorrect: a second window-apply path; a changed display, mode, or
resolution goes through `apply_window_settings`.

## Debug inspector

Use in debug mode for object and lamp edits. The shim builds a 320-point rail at
the top-right, inset 12, with a 1-point hairline and the HUD surface at 96%. It
has Object, Placement, Lamp, and Debug sections. Object carries the selected
prefab and id, the body control, the absolute yaw slider, Duplicate, and Delete.
Placement is the next placement's prefab, height, yaw, and snap. Lamp carries the
kind segmented control, the fixed colour swatches, the intensity slider, and the
range slider; the body row says it follows the kind. Debug carries the type
weight slider and the physics debug switch. The rail scrolls only if its sections
overflow; the close control returns `Toggle_Inspector`.

Incorrect: a colour picker. The light colours are the game's fixed set. Incorrect:
a relative yaw action; the rail sends an absolute yaw. Incorrect: showing the rail
while Settings or the palette is open.

## Object palette

Use only in debug mode. The shim builds a 640-point dialog with a 3×4 grid of
120×92 cards and a 220-point preview beside it. Each card draws the prefab colour
chip, short name, full name, and key badge. Number keys 1-9 select the first nine
cards; the last two carry a dash badge and are reached with the arrow keys. The
selected card lifts to the raised surface with a 2-point accent bar, hover adds a
fill overlay, and focus adds a 2-point accent ring. The Place button sits in the
footer with the key hints.

A click on a card returns `Palette_Select` with the item index and updates the
preview; it does not arm the placement. The Place button, or Enter on the game
keyboard path, returns `Palette_Pick`; the game arms the placement from the
selected prefab. The preview shows the colour, dimensions, body, light line, and
an isometric box built from the half extents and base pitch.

Incorrect: drawing the card or preview in Odin. The shim owns the view; the
palette carries the half extents, base pitch, body, light line, colour, and key
it reads.

## Notice

Use after an action whose result is not on screen, such as the `F5` scene
snapshot write. It is one line in the bottom action column, above the capture
hint. The text is primary. A failed write says `failed` in the same colour; the
word carries the result.

Incorrect: a colour for failure. The accent means selection.

## Capture hint

Use when the cursor is not captured and the player needs one instruction. It is
the same bottom action column, above the buttons. It is hidden when the frame is
captured or the palette is open.

Incorrect: centring it over the spider. It sits on the bottom margin.

## Rune fx demo

`view.fx` asks the shim to put a rune-fx glow over the `Debug` action row.
It is a demonstration of the effect layer, not a notification and not a state
signal. It is off by default and no scenario may assume it. The glow uses
`#7C5CFF` with a `#F4F0FF` core and a 12 point radius.

Incorrect: turning the glow on for every UI frame, or using it to mean
"selected". The default interface has no glow.
