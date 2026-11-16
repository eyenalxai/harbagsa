# One owner and one sink per input event

The live overlay read one platform frame twice: once as game intent and once as
the full Rune event batch. One Escape press could open the settings dialog in
the engine and close it in Rune in the same frame. Tab focused a HUD control
while the world owned the pointer, and Space pressed both the jump and the
focused control. The palette had an engine navigator and a second Rune focus
path.

## Decisions

- The engine owns the input source and the routing pass. `src/input/route.odin`
  derives one owner from the frame focus and copies each raw platform event to
  exactly one sink: the game intent or the UI batch.
- The owners are World, Menu, Inspector, Palette, and Placement. Menu sends keys
  and pointer to Rune; the world and placement send both to the game; the
  palette sends keys to the engine navigator and pointer to Rune; the inspector
  sends widget keys to Rune but keeps `Escape` and `I` in the engine. Tab moves
  focus in the inspector; the palette toggle is available while the rail is
  closed.
- Every input source holds the key it pressed. A repeat or release follows the
  press to the same sink even after the owner changes, and an unpaired release
  is dropped rather than routed by the current owner.
- Sources that press the same key share one sink edge. Releasing one source does
  not clear a key another source still holds, and two sources pressing `Escape`
  do not produce two Rune presses.
- Rune keeps focus, tab order, modal traps, sliders, and text semantics for the
  events it receives. It is not given an event that the game owns.
- Gamepad buttons and sticks are read by the engine and mapped to the same game
  intents and normalized key codes. No gamepad type crosses the UI ABI. The
  left stick and d-pad navigate the palette.
- Only the first gamepad is opened. Button edges come from SDL's event queue,
  so a tap between polls is retained. An unplug is detected, releases its held
  keys to their sinks, and leaves input on the keyboard. Hot-plug is not
  supported.
- The held state is cleared on window blur and on a dropped raw event. A full
  key or UI queue reports a warning.
- Cursor capture follows the end-of-frame focus, so opening or closing a surface
  takes effect before the next poll.
- The palette cards are not focusable. `Palette_Step`, `Palette_Select`, and
  `Palette_Pick` are the only palette navigator.

## Considered Options

- **Filter Escape only**: rejected. The Tab and Space collisions are the same
  double-routing class, and a special case would not cover gamepad input.
- **Engine owns every key semantic**: rejected. It reimplements Rune focus, tab
  order, dialogs, sliders, and text fields.
- **Rune owns gamepad input**: rejected. Rune has no gamepad API, and the game
  still needs the pad for movement.

## Consequences

- The menu opens on the frame Escape is consumed by the game and closes through
  Rune's `Close_Menu` action after the draw. The opening press never reaches
  Rune.
- A new keyed Rune surface must join the owner table or its keys fall to the
  game.
- The harness still drives the shim directly and does not exercise the live
  route. The shared raw-event harness frame and its proof are a separate change
  (HARB-375).
