# Components

Six surfaces live in one Rune view. Each exists for a reason; if a new one is not
one of these, read [README.md](README.md#adding-a-surface) first. The view is
built in `ui/shim/src/lib.rs`; the data is in `src/ui/ui.odin`.

## Status panel

Use for the player's live state. It is the persistent top-left surface while the
menu is closed. It draws `ui.Hud.rows` as a list and appends the notice, the
capture hint, and the action row below the panel.

The row kinds map to Rune elements:

- `Divider`: a 1 point full-width line.
- `Header`: tertiary text.
- `Setting`, `Action`, `Metric`, `Detail`, `Slider`: a label row with a spacer and
  a value. A slider also draws the track.

The action row has two buttons: `Debug` returns `Toggle_Debug` and toggles debug
mode. `Close` returns `Close_Menu`, but the status view is shown only while the
menu is closed, so the game ignores it there. The menu closes with `Esc` or
`Resume`.

Incorrect: measuring a row in Odin and sizing a rectangle from it. Rune measures
the text.

## Settings menu

Use for a paused decision. The view returns the menu before the status panel, so
the status panel is not drawn while the menu is open. Order is fixed: scrim,
panel, title, separator, rows, note, hints.

A `Slider` row is two lines: label and value, then a full-width 4 point track.
The unfilled track is white at 20%; the filled width is `ratio * 390` points in
the accent colour. There is no knob and no tick mark. The menu is a row list, not
a knob control.

The menu title is a text row. The note is tertiary text under the rows. The hint
grid is three key/action pairs per line.

The Type weight row edits a stored setting. The Rune view applies it to every
text node as a span weight; 400 leaves Rune's default. See [type.md](type.md).

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

`view.fx` asks the shim to put a rune-fx glow over the `Close`/`Debug` action row.
It is a demonstration of the effect layer, not a notification and not a state
signal. It is off by default and no scenario may assume it. The glow uses
`#7C5CFF` with a `#F4F0FF` core and a 12 point radius.

Incorrect: turning the glow on for every UI frame, or using it to mean
"selected". The default interface has no glow.
