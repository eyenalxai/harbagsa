# Input ownership: who owns one input event?

Date: 2026-11-14
Status: answered
Scope: repo `ddf6585`; vendored Rune `f18ead8` (2026-11-10)

## Answer

**The engine should own the input source and the routing; Rune should own key
semantics for the events it is given.** One reader (`src/platform`) produces one
ordered list; one pass (`src/input/route.odin`) writes each event to exactly one
sink: `Frame_Input` or a UI batch.

Test:

- **Source and gamepad: yes.** Rune has no gamepad API: 0 matches for
  gamepad/joystick/gilrs under `vendor/rune/crates`, and its window
  dependency is winit (`crates/rune/Cargo.toml:72`). The engine has none
  either (0 in `src`), but SDL3 supplies it
  (`/usr/lib/odin/vendor/sdl3/sdl3_gamepad.odin:5-73`,
  `sdl3_events.odin:121-130`).
- **Every key's semantics: no.** Rune consumes raw keys inside its focus
  machine — modal Escape
  (`vendor/rune/crates/rune/src/runtime/input/focus.rs:407-413`), Tab
  (`:416-441`), sliders (`:445-462`), group arrows (`:471-493`), Space/Return
  (`:498-510`), text and IME (`runtime/input/keys.rs:1-20`) — and
  `Runtime::key` returns nothing (`keys.rs:261-263`). That is option C.

### The live double handling

1. Escape, menu closed: `resolve` sets `menu_toggle`
   (`src/input/resolve.odin:104-109`), `apply_frame_input` opens the menu
   (`main.odin:122-124`), then the batch is built (`main.odin:197`).
2. `build_ui_events` sends every key (`ui_events.odin:52-63`); only pointers
   are gated (`:27-51`).
3. The snapshot lands before dispatch (`ui/shim/src/state.rs:252-293`); a key
   commits before routing (`crates/rune/src/runtime/frame.rs:479-491`); the
   modal takes Escape (`focus.rs:407-413`, `crates/rune/src/el.rs:1173-1180`)
   and closes (`crates/rune-kit/src/dialog.rs:34-43`) → `Close_Menu`
   (`ui/shim/src/settings.rs:326-330`), applied after the draw
   (`main.odin:205-226`). The menu closes in the frame it opened.

Same class without the menu: Tab focuses HUD `Debug`
(`ui/shim/src/components.rs:42-50`); Space jumps (`resolve.odin:192-195`) and
presses it (`focus.rs:498-510`). The palette has two navigators
(`resolve.odin:115-133`, `ui/shim/src/palette.rs:140-155`).

### Seam

- `platform.Events`: one ordered list, gamepad state, a `source` per event.
- `route`: owner from `game.Focus` (`src/game/editor_focus.odin:29-43`),
  updated by intents made in the pass, as `apply_key` tracks `pointer_tool`
  (`resolve.odin:36-39`).
- Surface modes: the dialog owns all keys; the palette and world own none for
  Rune; the inspector reserves `Escape` and `I` (`resolve.odin:88-98`). Drop
  palette card focus so `Palette_Step` is the only navigator.
- Gamepad: one intent table. UI open → one of eight UI keys
  (`src/renderer/ui_frame.odin:53-61`): d-pad/stick = arrows, A = Enter, B =
  Escape, shoulders = Tab. World → stick move/look, A jump, B cancel, Start
  menu. No gamepad type crosses the ABI.

Stays in Rune: focus and tab order, modal trap and Escape, slider steps, group
arrows, Space/Return, text/IME, hover, drag, scroll. Moves: routing, surface
modes, game/editor/view bindings, gamepad, key-up matching.

### Invariants

1. One reader, one pass, one sink; `build_ui_events` becomes a converter and
   loses `pointer_ui`.
2. One ownership value, never re-derived.
3. Release follows press: a key the engine consumed keeps its up and repeats.
4. Drawing never gates input: `ui_frame` always steps; only `ui_draw` follows
   `hud` (`src/renderer/ui_step.odin:7-9`,
   `src/renderer/frames.odin:70-72,219`).
5. Only `Ui_Action` mutates game state from Rune (`main.odin:205-226`).

### Options

| Option | Verdict |
| --- | --- |
| A. Engine source + routing, Rune semantics | Recommended |
| B. Rune owns keyboard focus, engine only gamepad | Keeps the bug: the engine binds Escape, I, Tab. Rune-first inverts frame order (`ui_frame` under `frame.draw`, `main.odin:204`) or uses `on_key` residuals (`crates/rune/src/runtime.rs:443`), lagging actions and tying bindings to what Rune left. |
| C. Engine owns all semantics, Rune renders | Reimplements focus, tab, modal, slider, text, IME (`focus.rs:407-510`); contradicts `docs/ui/README.md:138-140`. |

Tradeoff of A: the engine models which surface owns input, not focus. A new
keyed Rune surface must join the list, or its keys fall to the game.

## Evidence

- Keys are unfiltered (`ui_events.odin:52-63`) while pointers are filtered
  (`:27-51`).
- SDL3 has gamepad (`/usr/lib/odin/vendor/sdl3/sdl3_gamepad.odin:5-73`) and
  `GAMEPAD_*` events (`sdl3_events.odin:121-130`); ADR 0002 names gamepad as a
  later SDL3 need.

## Conflicts

- `docs/ui/README.md:57-66` says Rune owns keyboard state and
  `docs/design/README.md:24-25` says Odin sends flat data; `ui_events.odin:52-63`
  sends every key to Rune while `resolve.odin:104-109` acts on it. The docs win.
- `resolve.odin:28-31` says Rune owns the dialog's keys, but no code filters
  keys by menu state; `docs/agents/harness.md:192-193` says the dialog owns its
  keyboard path, but the harness has none (`src/harness/session_menu.odin:12-34`).

## Not found

- A host API to clear focus: `Runtime::set_focus` is `pub(super)`
  (`focus.rs:232`); no public blur exists. Needed to drop the ring.
- A key-press consumption result: `Runtime::key` returns `()` (`keys.rs:261-263`);
  `key_up` returns only a wants-gate (`runtime/input/gesture.rs:220-225`).

## Harness consequences

- No command sends a key: `ui` calls the shim directly
  (`src/harness/ui_execute.odin:10-50`), `menu` calls game procs
  (`session_menu.odin:12-34`), `editor` mirrors intents
  (`editor_input_command.odin:8-20`). Scenarios cannot see it.
- Add an `input` command that builds `platform.Events`, runs `route`, and
  applies both outputs. Scenarios: Escape opens and stays open; Escape closes;
  Tab opens the palette once; Space with Debug focused; gamepad A/B.
- Extract `apply_frame_input` (`app_loop.odin:26-83`) into a shared package, or
  the harness `menu` path drifts.
- Update `docs/agents/harness.md:147-154,192-198,260-262,291`. The router is
  pure; the shim's fixed `FRAME_DT` (`ui/shim/src/input.rs:17`) keeps runs
  deterministic.

## Files to change

1. `src/platform/input.odin` — gamepad state and events; event `source`.
2. `src/input/input.odin`, `src/input/route.odin` — `Route`, `Owner`, latches;
   the one pass.
3. `src/input/bindings.odin` — new; key and gamepad intents.
4. `src/input/resolve.odin` — semantics only; owner comes in.
5. `src/game/editor_focus.odin` — surface mode on `Focus`.
6. `ui_events.odin`, `main.odin` — converter only; one route, one batch.
7. `app_loop.odin` — move intent application out.
8. `src/frame/apply.odin` — new; shared application.
9. `src/renderer/ui_step.odin` — step decoupled from `hud`.
10. `src/renderer/ui_frame.odin` — event `source`.
11. `ui/shim/src/input.rs`, `ui/shim/src/palette.rs` — source field; no card
    keyboard focus.
12. `src/harness/input_command.odin` plus `command.odin`,
    `command_parse.odin`, `command_registry.odin`, `command_execute.odin`;
    `session_menu.odin` opens through the shared apply.
13. `docs/agents/harness.md`, `docs/ui/README.md`, `GLOSSARY.md:440-445`, new
    `docs/adr/00xx-input-ownership.md`.

## References

- `vendor/rune/crates/rune/src/runtime/input/focus.rs` — focus, tab, modal, and
  slider key path.
- `docs/research/rune-host-boundary.md` — commit-before-route frame order.
- `docs/adr/0002-sdl3-platform-and-raw-vulkan.md` — SDL3 owns gamepad later.
