# Components

Six surfaces live in one Rune view. Each exists for a reason; if a new one is not
one of these, read [README.md](README.md#adding-a-surface) first. The view is
built in `ui/shim/src`; the data is in `src/ui/ui.odin`.

## Status panel

Use for the player's live state. It is the persistent top-left surface while the
settings dialog is closed. It draws `ui.Hud.rows` as a list and appends the notice, the
capture hint, and the action row below the panel.

The row kinds map to Rune elements:

- `Divider`: a 1 point full-width line.
- `Header`: tertiary text.
- `Setting`, `Action`, `Metric`, `Detail`, `Slider`: a label row with a spacer and
  a value. A slider also draws the track.

The action row has two buttons: `Settings` returns `Open_Menu` and opens the
dialog, and `Debug` returns `Toggle_Debug` and toggles debug mode. The dialog
closes with `Esc`, its close control, or `Resume`.

Incorrect: measuring a row in Odin and sizing a rectangle from it. Rune measures
the text.

## Settings dialog

Use for a paused decision. Settings is a `rune-kit::Dialog` over a scrim. The
dialog width is 520 points and the body holds three sections: Display,
Interface, and Controls. Window mode and Sprint mode are `SegmentedControl`s;
Display and Resolution use the kit Select field over a menu list whose items keep
their own indices, so duplicate or truncated names still choose the right row;
HUD opacity is the local Slider;
Reduce motion is a `Switch`; Resume is a footer `Button`. `Esc`, the header close
control, and Resume dismiss it.

The HUD opacity Slider runs from 70 to 100 percent in one-point steps. Only the
track is the hit area: it drags from the thumb, jumps on a track press, steps
with Left and Right, repeats while held, and restores the pre-drag value when Esc
cancels the drag. The label and percentage row never changes the value. Its value
draws in Geist Mono. Below 94 percent the status HUD's tertiary text promotes to
secondary, keeping the text floor on the translucent surface.

The dialog owns its keyboard path: Rune traps focus, draws the focus ring, and
routes arrows and Enter to the focused control. `src/game/settings_view.odin`
names every option and index; the shim never derives a display or mode name.

Incorrect: measuring a row in Odin and sizing a rectangle from it. Rune measures
the text. Incorrect: a second window-apply path; a changed display, mode, or
resolution goes through `apply_window_settings`.

## Object palette

Use only in debug mode. The shim turns every `ui.Palette` item into a row with
the short name as the label and the full name as the value, marks the selected
row, and puts the body note and hints below. The panel is the same menu panel.

A click on a row returns `Palette_Select` with the row index. The game arms the
placement from that index. The palette is a list, not a grid and not an
isometric preview.

Incorrect: adding a card thumbnail in Odin. The shim owns the view and the
palette carries text only.

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

`view.fx` asks the shim to put a rune-fx glow over the `Settings`/`Debug` action row.
It is a demonstration of the effect layer, not a notification and not a state
signal. It is off by default and no scenario may assume it. The glow uses
`#7C5CFF` with a `#F4F0FF` core and a 12 point radius.

Incorrect: turning the glow on for every UI frame, or using it to mean
"selected". The default interface has no glow.
