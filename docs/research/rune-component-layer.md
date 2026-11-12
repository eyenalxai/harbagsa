# The Rune component layer: input, settings, palette, HUD, and inspector

**Date:** 2026-11-12
**Status:** Code-read research note. No build, no run, no screenshot, no in-engine contrast measurement. Source is the vendored Rune at `vendor/rune`, commit `f18ead891aba2437674cd8c54e238287cceb8b3a` (2026-11-10), crate `rune 0.0.1`. Odin line ranges are from the working tree at `055367c`.
**Question:** What is the right way to build a reusable, high-quality Rune component layer for the game overlay at this Rune revision, including the input path from Odin, the settings dialog, the palette grid, the status HUD, and a new right-side debug inspector?

## Answer

Use `rune-kit` for interactive controls, keep the status HUD as a local compact panel, and build two local components the kit does not have: a `Slider` (copied from `examples/settings`) and a `PaletteGrid` (built on `equal_columns`/`grid_cell` with a `Shape` preview). Do not use `rune-kit::List`: it hardcodes a 14/500 font and truncates labels, so it breaks the type-weight control and the no-truncation rule.

The input path is the real problem, not the widgets. The current C ABI manually hit-tests keyed elements and never calls Rune's pointer, wheel, key-repeat, key-up, or focus APIs. That throws away hover, press, focus, drag, scroll, and kit component dispatch. Replace it with a real event batch: `pointer_move/down/up/leave`, `wheel_event`, `key/repeat_key/key_up`, `window_focus`, `set_viewport`, then one `Runtime::frame(dt)`. Keep Odin authoritative by treating every handler result as an intent in a flat `Ui_Action` queue; Odin applies, validates, and sends the next snapshot. Rune owns only transient interaction state and drag previews.

Recommended target shape:

| Surface | Component strategy | Input owner |
| --- | --- | --- |
| Status HUD | local `HudPanel` + rows + `Divider`-style hairline; no kit `Card`/`List` | Odin keyboard, no pointer targets while captured |
| Settings dialog | kit `Dialog` + `SegmentedControl` + `Select` + local `Slider` + `Switch` + `Button` + `Keybind` | Rune while open |
| Object palette | kit `Dialog` shell + local `PaletteGrid` + `Shape` preview + `Badge`/`Keybind` | Rune while open |
| Debug inspector | kit `Card` sections + `SegmentedControl`/`Select` + local `Slider` + `Switch` + `IconButton` + `ScrollBar` | Rune while interactive; pointer-free |
| Global shortcuts | none | Odin |

Theme: `Kit::from_palette(PaletteSeed { bg: #0F141A, fg: #EDF2F7, accent: #E6B03B })` with `PaletteFocus::Accent`, then pin the measured overlay tokens. `from_palette` gives every kit token a coherent value and sets `blend_over`, which is correct for the sRGB target; its derived `text_faint` only guarantees 3:1, so pin it to the existing tertiary `#808C99`. Use a local `#0F141A` at 94% for the HUD surface (translucent), and the pinned opaque `layer_01` `#141A21` for dialogs. HUD opacity is not safe below 94% with tertiary text: at 85% over a white scene, tertiary text falls to about 3.5:1. Either keep the HUD at its authored alpha, move the opacity control to the debug inspector, or promote tertiary text before lowering it.

## Evidence

### 1. Component inventory and builder API

- `Kit` is the only token surface components read: `dark`, `Palette c`, `Elevation`, `Glyphs`, `Type ty`, `Radius`, `Motion`, `blend_over`, `ring`, `invalid_text` (`vendor/rune/crates/rune-kit/src/kit.rs:230-249`). Components never name raw colours or sizes outside these fields (`kit.rs:1-3`).
- `Kit::neutral(dark)` builds a neutral kit from `rune::tok::theme` plus `tok::accent(0)`, whose accent is blue (`vendor/rune/crates/rune-kit/src/neutral.rs:17-40`; `vendor/rune/crates/rune/src/tok.rs:212-220`).
- `Kit::from_palette(PaletteSeed { bg, fg, accent })` derives surfaces, text, borders, states and elevation from three opaque colours, sets `blend_over = Some(bg)`, floors secondary text at 4.5:1 and faint text at 3:1, and sets a focus-ring colour (`vendor/rune/crates/rune-kit/src/palette.rs:10-14`, `:81-112`, `:123-159`, `:180-248`).
- `PaletteFocus::{Blue, Accent, Ink, Custom}` selects the focus ring; the default is a neutral blue (`vendor/rune/crates/rune-kit/src/palette.rs:21-34`, `:144-149`).
- `Button` is a builder ending in `.build(&Kit) -> El`; it supports `Neutral`, `Danger`, `Warning`, `Outline`, `Contrast`, `Submit`, `Ghost`, `GhostMuted`, `GhostFaint`, `Loading` (`vendor/rune/crates/rune-kit/src/actions.rs:26-39`, `:198-209`, `:317-376`).
- `IconButton` is the square icon form; it requires an accessible label (`vendor/rune/crates/rune-kit/src/actions.rs:389-529`; label requirement at `:445-450`).
- `Switch::new(checked)` with `.label`, `.description`, `.on_toggle`, `.disabled`, `.state`, and `.build(&Kit)` (`vendor/rune/crates/rune-kit/src/switch.rs:8-85`).
- `SegmentedControl::new(&labels, selected)` with `.label`, `.width`, `.fit`, `.segment_state`, `.on_pick`, and `.build(&Kit)` (`vendor/rune/crates/rune-kit/src/segmented.rs:20-71`).
- `Select::new(key, &options)` with `.current`, `.open`, `.label`, `.highlighted`, `.on_choose`, and `.build(&Kit, &mut Vec<El>)`; its listbox max height is 206 points (`4 + 6*30 + 22`) (`vendor/rune/crates/rune-kit/src/select.rs:14-16`, `:31-155`, `:157`).
- `Card::new()` with `.title`, `.description`, `.accent`, `.action`, `.child`; it is a content row, not a surface: the root is a `row().role("group")` with no fill, radius, or border (`vendor/rune/crates/rune-kit/src/card.rs:8-93`, root at `:81`).
- `Dialog::new(key, title)` with `.open`, `.description`, `.width`, `.fit`, `.click_outside`, `.on_close`, `.build(&Kit, &mut Vec<El>)`; it mounts a scrim and a panel into the layer list and uses `k.c.layer_01` plus `k.elevation.overlay` and `token_motion(k.motion.overlay)` (`vendor/rune/crates/rune-kit/src/dialog.rs:8-67`, panel at `:57-61`).
- `List` is a searchable grouped list with an active row and optional dividers; it hardcodes `TextStyle::new(14.0, 500.0)` for items and uses `.truncate()` on labels (`vendor/rune/crates/rune-kit/src/list.rs:8-232`, font at `:96`, truncate at `:186`).
- `Badge` is a status chip with `Neutral`, `Accent`, `Subtle`, `standard`, `high_contrast`; `Divider` is the same module (`vendor/rune/crates/rune-kit/src/badge.rs:8-82`).
- `Keybind::new(&["Esc"])` draws keycaps and joins them for the accessible label (`vendor/rune/crates/rune-kit/src/keybind.rs:9-58`).
- `Tooltip` is a builder that returns a trigger plus an overlay body; the simpler runtime tooltip is `El::help(text)`, which shows after `Runtime::help_delay` (`vendor/rune/crates/rune-kit/src/overlay.rs:431-544`; `vendor/rune/crates/rune/src/el.rs:1270-1282`).
- `ScrollBar` is `Kit::scroll_bar(viewport)` or `rune_kit::scroll_bar(&kit, area, key, viewport)`; it wraps a `scroll` element and follows the system overlay preference (`vendor/rune/crates/rune-kit/src/kit.rs:317-323`; `vendor/rune/crates/rune-kit/src/scroll_bar.rs:765-777`).
- Overlays (`Dialog`, `Select`, `Tooltip`) must be mounted above the base view with `rune_kit::root(base, overlays)`; mounting them inline lets later siblings paint over them (`vendor/rune/crates/rune-kit/src/lib.rs:274-283`; usage at `vendor/rune/examples/kit-gallery/src/main.rs:112-121`).
- The kit crate is 13,165 source lines including tests; `actions.rs` is 529, `scroll_bar.rs` 819, `text_input.rs` 682, `list.rs` 232, `dialog.rs` 67. It depends on `rune`, `rune-highlights`, `rune-motion`, `unicode-segmentation`, and optional `pulldown-cmark`/`rune-mermaid` (`vendor/rune/crates/rune-kit/Cargo.toml:5-15`). `unicode-segmentation` is already a `rune` dependency (`vendor/rune/crates/rune/Cargo.toml:90`), and `rune-motion` is already in the `rune` tree (`vendor/rune/Cargo.toml:66`), so the new runtime crate is `rune-highlights` (520 lines), which adds `unicode-ident` and a build-time `wasmparser` (`vendor/rune/crates/rune-highlights/Cargo.toml:8-12`). The syntax highlighter is compiled even though the overlay never uses it.
- There is no `Slider` in `rune-kit`: the component directory has `switch.rs`, `segmented.rs`, `select.rs`, etc., but no slider file (`ls vendor/rune/crates/rune-kit/src`). The settings example hand-builds one (`vendor/rune/examples/settings/src/main.rs:284-356`).
- The settings example is not a kit example: it uses `tok::theme` and hand-built controls rather than `rune-kit` (`vendor/rune/examples/settings/src/main.rs:3-7`, `:70-78`, `:176-356`). The actual kit showcase is `examples/kit-gallery` (`vendor/rune/examples/kit-gallery/src/main.rs:112-121`; stories at `stories.rs:265-290`).
- There is no `Grid` component in the kit. Rune itself has `equal_columns(n)` and `grid_cell(column)` on `El`, so a palette grid is a local component (`vendor/rune/crates/rune/src/el/layout.rs:550-560`).
- `Button` and `Switch` attach their own press handlers through the builder (`Button::on_press` at `actions.rs:308-315`; `Switch::on_toggle` at `switch.rs:76-80`), so a component used only as a visual needs its handler omitted and its press handled by a parent row, as the settings example does (`examples/settings/src/main.rs:176-183`).

Inventory table:

| Component | Use here | Price | Gap |
| --- | --- | --- | --- |
| `Button` | Resume/Apply, Duplicate, Delete, Place | 529-line module; no new dep | No action id; handlers are closures; `Danger` adds a red hue |
| `IconButton` | Close, duplicate, delete, cycle | same module | Needs a label; no trash/duplicate glyph in `Glyphs` (`vendor/rune/crates/rune-kit/src/glyphs.rs:167-184`) |
| `Switch` | Reduce motion, snap | 225 lines | Animates; disabled uses `layer_opacity`; conflicts with no-motion |
| `SegmentedControl` | Window mode, sprint mode, body, lamp kind | 160 lines | Labels only; animates its indicator |
| `Select` | Display, resolution, lamp colour | 332 lines + popup list | App owns `open`; needs a layer mount; max height 206 |
| `Card` | Settings/inspector sections | 93 lines | Not a surface; no fill/border/radius |
| `Divider` | Section rules | 82-line badge module | Uses `border_base`, not the HUD hairline |
| `Keybind` | Hint rows, shortcut hints | 58 lines | None |
| `Tooltip` | Icon-button labels | 597-line overlay module | App owns `open` unless using `El::help` |
| `Dialog` | Settings and palette shell | 67 lines | Requires `on_close` and a layer list; fixed 368 height unless `.fit()`; animates |
| `List` | Not recommended | 232 lines | Hardcoded 14/500 font; truncates; list not grid |
| `Badge` | Inspector id/body, bake status | 82 lines | `role="status"` live region is noisy per frame |
| `ScrollBar` | Inspector overflow | 819 lines | Only fits a `scroll` viewport; vertical by default |
| `Slider` | HUD opacity, yaw, intensity, range, type weight | missing; ~180 local | No kit component |
| `Grid` | Palette | missing; ~150 local | No kit component |

Settings mapping: `Window mode` and `Sprint mode` are two-option `SegmentedControl`s; `Display` and `Resolution` are `Select`s over the snapshot's option names; `HUD opacity` is the local `Slider`; `Reduce motion` is a `Switch`; `Resume` is a `Button`; the hint grid is `Keybind` rows; the shell is `Dialog` with `Card` sections. The HUD is not a kit surface: kit list rows use 14/21 type with 6-point vertical padding (`vendor/rune/crates/rune-kit/src/list.rs:96`, `:175-186`), while the HUD is a 380-point panel with 12-point padding, a 6-point gap, and fixed fields (`docs/ui/spacing.md:22-39`). A local `HudPanel` keeps the density and the fixed-field rule.

The palette's C ABI is behind its data model: `ui.Palette_Item` carries `half_extents`, `color`, `base_pitch`, `body`, `key`, and a light line (`src/ui/ui.odin:52-63`; `src/game/palette_view.odin:48-63`), but `Ui_Palette_Item` only carries name/short plus reserved `color` and `key` that the shim ignores (`ui/shim/src/lib.rs:133-144`; `src/renderer/ui_bridge.odin:85-93`). The grid preview needs `half_extents`, `body`, and the light line added to the C ABI.

### 2. Input: exact Runtime API, what the C ABI drops, and the recommended shape

- `Runtime::pointer_move(x, y)` is public (`vendor/rune/crates/rune/src/runtime/input/pointer.rs:8`); `pointer_down(x, y)` (`:177`); `pointer_up(x, y)` (`:299`); `pointer_leave()` (`:356`).
- `Runtime::wheel_event(WheelEvent)` is public (`vendor/rune/crates/rune/src/runtime/input/gesture.rs:25-38`); `WheelEvent` has `dx`, `dy`, `x`, `y`, `mods`, `phase`, `momentum`, `precise` (`vendor/rune/crates/rune/src/input/canvas_input.rs:20-49`).
- `Runtime::key(KeyEvent)` (`vendor/rune/crates/rune/src/runtime/input/keys.rs:261-263`), `repeat_key(KeyEvent)` (`:275-277`), `key_up(KeyEvent)` (`vendor/rune/crates/rune/src/runtime/input/gesture.rs:220-225`).
- `Runtime::window_focus(bool)` is public; losing focus cancels the pointer, drops held activation, and ends hover (`vendor/rune/crates/rune/src/runtime/frame.rs:51-84`).
- `Runtime::set_viewport((w,h), scale)` is public; it sets `relayout` and the scene pixel scale (`vendor/rune/crates/rune/src/runtime/frame.rs:11-17`, `:28-44`).
- `Runtime::frame(dt)` is public and is the only step; it may run more than one `frame_step` when a timer deadline falls inside the step (`vendor/rune/crates/rune/src/runtime/frame.rs:305-307`, `:345-371`).
- Pointer coordinates are logical window points, not device pixels; the winit host divides by `scale_factor` (`docs/research/rune-host-boundary.md:145-151`). The shim already converts the game's normalized pointer to points (`src/renderer/ui_bridge.odin:172-174`).
- `pointer_down` hit-tests against the hit list built by the last `frame`; a host must call `frame(0.0)` once before the first pointer event (`docs/research/rune-host-boundary.md:179`; the shim does this at `ui/shim/src/lib.rs:692`).
- `on_press` is queued on release inside the element, not on down; a click needs both `pointer_down` and `pointer_up` before the frame that fires it (`docs/research/rune-host-boundary.md:173`).
- `Drag` carries `phase`, local `x/y`, `w/h`, `start_x/start_y`, `dx/dy`, scratch `data`, click count, and `cancelled()`; it is dispatched via `El::on_drag` with Down, Move, Up (`vendor/rune/crates/rune/src/el.rs:112-153`; `vendor/rune/crates/rune/src/el/handlers.rs:34-41`).
- `El::on_step` gives a focused slider Left/Down = -1, Right/Up = +1, Page Down = -10, Page Up = +10, repeating while held; it makes the element focusable and role `slider` (`vendor/rune/crates/rune/src/el.rs:1093-1111`).
- `El::range_value(value, min, max)`, `range_step(step)`, and `a11y_value(text)` set the accessibility range and value (`vendor/rune/crates/rune/src/el/a11y.rs:136-153`).
- `El::focus_ring(width, offset, color)` draws the keyboard ring; kit components already set one (`vendor/rune/crates/rune/src/el.rs:1133-1138`; `vendor/rune/crates/rune-kit/src/actions.rs:125-146`).
- `Runtime::elements()` returns a `Vec<ElementInfo>` with `key`, `role`, `label`, `text`, `rect`, `target`, `focused`, `hover`, `press`, `selected`, `item_selected`, and more (`vendor/rune/crates/rune/src/runtime/elements.rs:6-76`, `:201-377`).
- `Runtime::find(key)` returns the centre of the keyed element's drawn rect in points (`vendor/rune/crates/rune/src/runtime/elements.rs:385-397`); `presented(key)` returns its drawn rect and effective opacity (`:402-405`); `element_at(x,y)` is the topmost element at a point in paint order (`:407-421`).
- `Runtime::elements()` is not cheap: it calls `scene.presented`, walks ancestors for opacity/scale/blur/scroll, and clones several strings per element (`docs/research/rune-host-boundary.md:219`).
- The current `UiEvent` is `{kind u32, flags u32, x f32, y f32, dx f32, dy f32, key i32}` (`ui/shim/src/lib.rs:179-187`; mirrored at `src/renderer/ui_bridge.odin:123-131`).
- The current event loop ignores pointer move (`kind 1`), records only an element key on down (`kind 2`), re-hit-tests on up (`kind 3`), and ignores leave (`kind 4`) (`ui/shim/src/lib.rs:863-880`). It never calls `Runtime::pointer_move`, `pointer_down`, `pointer_up`, or `pointer_leave`.
- `element_key_at` scans `runtime.elements()` in reverse and returns the first keyed element whose `target` rect contains the point; it clones `String`s and uses the layout rect, not the drawn rect or paint order (`ui/shim/src/lib.rs:1043-1049`). A kit button's root is often unkeyed while its label child is keyed `"label"`, so a click on the label returns a key that `push_key_action` ignores (`ui/shim/src/lib.rs:1051-1061`).
- The current key path maps only `Enter`, `Escape`, Up, Down, Left, Right, Tab; it has no modifiers, key up, repeat, text, or IME (`ui/shim/src/lib.rs:882-893`).
- `UI_Frame` carries only six menu keys in a `bit_set` and a pointer position plus pressed/down flags (`src/renderer/ui_frame.odin:6-15`, `:25-39`); two presses of the same key in one frame collapse.
- The platform drops key repeats entirely and has no `KEY_UP` branch (`src/platform/input.odin:132-145`); it accumulates wheel deltas only while the pointer is captured (`src/platform/input.odin:128-131`), so the menu, palette, and inspector never see a wheel.
- The platform has no focus event: `Events` has no focus field (`src/platform/input.odin:17-43`), so `Runtime::window_focus` is never called and a lost focus does not cancel a Rune drag or a world drag.
- `ui_attach` constructs a new `Runtime` and a new `UiState` every time it is called (`ui/shim/src/lib.rs:673-693`); the swapchain path calls it on target recreation (`src/renderer/swapchain.odin:207-210`), so a resize can discard menu/palette state and rebuild the text atlas.
- `ui_frame` clears `actions` at the start and calls `runtime.invalidate()` unconditionally every frame (`ui/shim/src/lib.rs:793`, `:898`), so the view rebuilds even when nothing changed and an undrained action from a previous call is lost.
- Recommended event shape (32 bytes, extend to 48 only if text/IME enters scope):

```c
typedef enum {
  UI_EV_NONE = 0,
  UI_EV_POINTER_MOVE = 1,
  UI_EV_POINTER_DOWN = 2,
  UI_EV_POINTER_UP = 3,
  UI_EV_POINTER_LEAVE = 4,
  UI_EV_POINTER_SECONDARY_DOWN = 5,
  UI_EV_POINTER_SECONDARY_UP = 6,
  UI_EV_WHEEL = 7,
  UI_EV_KEY_DOWN = 8,
  UI_EV_KEY_UP = 9,
  UI_EV_KEY_REPEAT = 10,
  UI_EV_FOCUS = 11,
} Ui_Event_Kind;

typedef struct {
  u32 kind;
  u32 flags;   /* bit0 shift, bit1 ctrl, bit2 alt, bit3 super, bit4 precise, bit5 focused */
  f32 x, y;    /* points */
  f32 dx, dy;  /* wheel points */
  i32 key;     /* stable shim key code, never a Rust enum */
  u32 button;  /* 0 primary, 1 secondary, 2 middle */
} Ui_Event;
```

- Recommended event order per frame: `set_viewport` first if the target changed; `window_focus` first if focus changed; then pointer moves, down, moves, up, leave in arrival order; wheel after the move that positions it; key down, repeats, up; then one `frame(dt)`. If the viewport changed, call `frame(0.0)` before pointer events so hit rects match the new layout; `set_viewport` only marks `relayout` (`vendor/rune/crates/rune/src/runtime/frame.rs:11-17`).
- Recommended ABI functions: `ui_frame(dt, snapshot, events, count)` stays, but the shim copies events and calls the Runtime methods; add `ui_set_viewport(w,h,scale)`, `ui_actions(count)`, `ui_actions_clear()`, and `ui_element(key, *Ui_Element)` for tests. Do not expose `Runtime` or `ElementInfo` as Rust types across the ABI (`docs/research/rune-host-boundary.md:486-494`).
- Focus: `pointer_down` on a focusable element queues `FocusControl`; Tab/Shift+Tab traverses; `on_step` makes a slider focusable; `focus_ring` draws the keyboard ring (`vendor/rune/crates/rune/src/runtime/input/pointer.rs:250-272`; `el.rs:1098-1100`, `:1133-1138`).
- Hover: `pointer_move` updates the hover target and starts help delays; kit hover/press overlays are property tracks, not view rebuilds (`vendor/rune/crates/rune/src/runtime/input/pointer.rs:13-62`; `docs/research/rune-ui-port.md:55-60`).
- Press: `pointer_down` captures the target and `pointer_up` fires `on_press` only if the release is inside; Escape/focus loss cancels (`vendor/rune/crates/rune/src/runtime/input/pointer.rs:177-297`, `:307-353`).
- Drag: `pointer_down` queues `Phase::Down`; `pointer_move` queues `Phase::Move`; release queues `Phase::Up` with `cancelled()` when the gesture was taken away (`vendor/rune/crates/rune/src/el/handlers.rs:34-41`; `vendor/rune/crates/rune/src/el.rs:148-153`).
- Wheel: `wheel_event` offers the delta to `on_wheel` handlers first, then scrolls the nearest scroll view; `precise` distinguishes a trackpad from a notched wheel (`vendor/rune/crates/rune/src/runtime/input/gesture.rs:21-38`; `canvas_input.rs:20-49`).
- Key repeat: `repeat_key` sets `Tx::key_repeat` true for the handler; `on_step` repeats while held (`vendor/rune/crates/rune/src/runtime/input/keys.rs:273-277`; `el.rs:1093-1097`).
- Keeping Odin authoritative: the shim's `UiState` is a view model; handlers push `UiAction` values into `state.actions`; Odin drains them after `frame`, validates, applies, and sends the next snapshot. No C callback runs inside a handler, so there is no `&mut Runtime` aliasing and no re-entrancy (`docs/research/rune-host-boundary.md:330-354`).
- The action queue is currently applied after `frame.draw` (`main.odin:227-253`), so a value changed by a UI action is one frame behind the drawn UI. That is acceptable for a toggle; a pointer slider needs a local preview in the shim so the knob tracks the pointer while the authoritative value arrives next frame.

### 3. Slider: what a local component needs, and the exact lines to copy

- The settings example's slider is an `el()` with `role("slider")`, `label`, `range_value(v, 0, 1)`, `range_step(0.05)`, `a11y_value(...)`, `on_step`, `size`, `motion`, and `on_drag` (`vendor/rune/examples/settings/src/main.rs:293-319`).
- The drag handler is the pattern to copy: on `Down`, save the value in `d.data` and jump to the track point if the press is not on the knob; on `Move`, compute the grab offset and set the value, then `tx.instant()`; on `Up`, restore `d.data` if `d.cancelled()` (`vendor/rune/examples/settings/src/main.rs:303-319`).
- The slider draws a track, a filled portion, and a knob as children with `absolute` positions; the track is `h=4`, the knob is 18, and the fill width is `k/2 + v*travel` (`vendor/rune/examples/settings/src/main.rs:320-345`).
- The value is drawn separately as a mono text with a fixed width, right-aligned, and marked `a11y_hidden` (`vendor/rune/examples/settings/src/main.rs:347-355`).
- A local slider needs: `role("slider")`, a label, `range_value(min,max)`, `range_step`, `a11y_value` for a formatted value, `on_step` for keyboard, `on_drag` for pointer, `focus_ring`, `focusable(true)`, and `.motion`/`tx.instant()` for the knob. The kit has no slider, so this is not a wrapper (`ls vendor/rune/crates/rune-kit/src`; `examples/settings/src/main.rs:284-356`).
- For HUD opacity, the contrast floor in section 5 makes a 40..100 settings slider dishonest. Put a 40..100 slider in the debug inspector if the feature is kept for tuning, or use three settings presets at 94/97/100; do not let the shim keep the authoritative value. Push `Settings_Set { id: Hud_Opacity, f: percent/100 }` on change.
- For debug type weight, use 100..900, `range_step(5)`, `a11y_value(format!("{weight}"))`, and push `Type_Weight_Set { f }`. Rebuild `Kit.ty` when the snapshot weight changes; do not use a span override, because kit components set their own `.font(...)` (`vendor/rune/crates/rune-kit/src/actions.rs:337-346`; `kit.rs:168-190`).
- The type weight is global: `Kit::neutral` builds 12 `TextStyle`s (`neutral.rs:111-130`), and `Button`, `Dialog`, `Switch`, `SegmentedControl`, `Keybind`, `Badge`, and `Card` read them (`actions.rs:337-346`; `dialog.rs:48-52`; `switch.rs:101-108`; `segmented.rs:74`; `keybind.rs:35`; `badge.rs:51-55`; `card.rs:71`). `List` hardcodes 14/500 and will not follow (`list.rs:96`), so avoid `List`.
- If the type weight is removed from settings, `MENU_ITEM_COUNT`, `MENU_ITEM_ROWS`, `Menu_Item`, `menu_change_setting`, and the type-weight row all change (`src/game/menu.odin:10-42`, `:111-155`, `:216-223`); `scenarios/rune-menu.json` and `scenarios/rune-weight.json` depend on the menu row.
- Settings ownership: use `Dialog::on_close` for Esc/outside dismiss, let the dialog's modal focus own Tab, and let the focused control own arrows/Enter (`SegmentedControl`/`Select`/`Slider`). Delete `apply_menu_input` (`settings_menu.odin:11-31`), `Menu_Input` (`src/input/input.odin:22-31`), and `UI_KEYS` (`src/renderer/ui_frame.odin:6-15`); keep `Menu_State` as the value model. `Esc` to open the menu when nothing is open stays in `resolve` (`src/input/resolve.odin:89-94`).

### 4. Rendering: what the kit needs and whether the current Renderer path supports it

- The kit needs isolated layers for disabled `layer_opacity` states (`Button` at `vendor/rune/crates/rune-kit/src/actions.rs:373`, `IconButton` at `:526`; `Switch` at `switch.rs:94`; `SegmentedControl` at `segmented.rs:144`; `Select` at `select.rs:325`). It does not need offscreen blur or backdrop blur for its default look; the only "blur" is the analytic `box_shadow` (`KIND_SHADOW`), not a Gaussian pass (`docs/research/rune-paint-contract.md:280-297`).
- The kit needs shadows: `Button` uses `k.elevation.button_neutral` (`actions.rs:132`), `Switch` uses `switch_on/off` plus `elements` (`switch.rs:151-166`), `Dialog` uses `k.elevation.overlay` (`dialog.rs:57-61`).
- The kit needs gradients: the compact switch track and thumb use `.gradient(...)` (`switch.rs:158-166`); `KIND_GRADIENT` is in the main pass (`docs/research/rune-paint-contract.md:34`, `:61`).
- The kit needs outline rings: focus rings are `El::outline`/`focus_ring` and paint as `KIND_RECT` rings in the main pass (`actions.rs:125-146`; `segmented.rs:121`; `docs/research/rune-paint-contract.md:49`).
- The current `Renderer` supports all of the above: `Renderer::new(device, format)` (`vendor/rune/crates/rune/src/render.rs:762-764`), `prepare` (`vendor/rune/crates/rune/src/render/upload.rs:187-215`), `encode_layers_with` (`vendor/rune/crates/rune/src/render/layers.rs:669-675`), `draw_target_range_with` (`render.rs:847-874`), and `submit` (`render.rs:947-950`).
- The shim already calls the full path: `prepare` at `ui/shim/src/lib.rs:710-716`, `encode_layers_with` at `:736-742`, `draw_target_range_with` at `:743-758`, and `submit` at `:759`. Rune's layer target is its internal `Rgba16Float` (`vendor/rune/crates/rune/src/render/layers.rs:8`, `:540-541`); the shim's `fx.add_format(Rgba16Float)` at `:670` is for the fx renderer, not the layer target.
- `Renderer::new` starts Windfoil on Linux (it passes `cfg!(target_os = "macos")`, false here) and Windfoil includes `outline.wgsl` and the outline store; the atlas fill pass is part of `prepare` (`vendor/rune/crates/rune/src/render/pipelines.rs:27-33`; `render/variant.rs:1-10`; `render/upload.rs:196-214`). `El::outline` is still a rect ring, not outline text.
- Missing for kit: nothing on the ordinary path. Missing if the design adds blur: `KIND_BACKDROP_BLUR` needs a viewport-sized backdrop copy and the full pyramid, and `ui_attach` wraps target images with `TextureUses::COLOR_TARGET` only (`ui/shim/src/lib.rs:630`, `:649-657`), so the swapchain/offscreen image would need `COPY_SRC`/`TRANSFER_SRC` usage and the backdrop path (`render.rs:827-874`). The docs forbid blur anyway (`docs/ui/spacing.md:67-68`).
- Missing for kit: `rune-kit::shell::Toolbar` uses `system_material`, whose `MaterialDraw` list is `pub(crate)` and not part of the instance stream (`docs/research/rune-paint-contract.md:295-297`; `vendor/rune/crates/rune/src/runtime.rs:476`). Do not use the shell toolbar.
- Missing for kit: `rune-light`/glass and video/native surfaces are separate renderers; they are out of scope (`docs/research/rune-paint-contract.md:270-278`, `:326-328`).
- `Renderer::set_format` sets `srgb_blend = !format.is_srgb()` (`vendor/rune/crates/rune/src/render/pipelines.rs:205-217`). The game's target is sRGB (`src/renderer/offscreen.odin:9-10`, `:64`), so the shim runs with linear-light blending; that is the case `Kit::from_palette`'s `blend_over` is for.
- The shim's `fx_plan` iterates `runtime.instances` and maps only `KIND_EFFECT` marks; kit components do not emit effects (`ui/shim/src/lib.rs:1074-1104`). No change is needed for kit.

### 5. Theme: comparing the three routes and pinning the overlay tokens

- Route A: `Kit::from_palette(PaletteSeed { bg, fg, accent })`. It derives surfaces, text, borders, hover/press, states and elevation; sets `blend_over = Some(bg)`; sets `ring = Some(border_base)`; floors muted at 4.5:1 and faint at 3:1 (`vendor/rune/crates/rune-kit/src/palette.rs:81-112`, `:123-159`, `:180-248`).
- Route B: `Kit::neutral(dark)` + overrides. It uses `rune::tok::theme` and a blue accent; its `Type` is 13/400, 13/500, 11/400, 14/400, 12/400, mono 12 (`neutral.rs:17-40`, `:111-130`). A blue accent leaks into `bg_accent`, `text_accent`, `icon_accent`, `border_focus`, and `border_active` (`neutral.rs:40`, `:50`, `:56`, `:60`, `:86`), so an amber overlay needs at least five overrides, plus the measured surfaces and text.
- Route C: `rune::tok::theme(dark)` + local components, as `examples/settings` does. `tok::theme` has 16 colours and no semantic states or component tokens (`vendor/rune/crates/rune/src/tok.rs:145-208`). The settings example is 375 lines for one settings window (`examples/settings/src/main.rs:1-375`). This is the fallback if the kit is rejected; it forfeits kit focus, hover, disabled, overlay and a11y work.
- Recommendation: Route A plus a small pin block. `bg = #0F141A` (page/behind), `fg = #EDF2F7`, `accent = #E6B03B`, `PaletteFocus::Accent` so the focus ring is amber, not a third blue hue (`palette.rs:21-34`, `:144-149`; `docs/ui/colour.md:56-58`).
- Pin `c.layer_01 = #141A21` opaque for dialogs/menu (`Dialog` uses `layer_01` at `dialog.rs:58`; the measured menu surface is `docs/ui/colour.md:13`). Pin `c.surface_raised`/`surface_raised_base = #26303D` for selected rows (`docs/ui/colour.md:14`). Pin `c.text_base = #EDF2F7`, `text_muted = #A6B2BF`, `text_faint = #808C99` (`docs/ui/colour.md:15-17`). Pin `c.scrim = black 0.62` (`docs/ui/colour.md:21`). Pin `c.bg_accent = #E6B03B`, `text_accent`, `icon_accent`, `border_focus` to the accent (`docs/ui/colour.md:18`).
- `from_palette`'s `text_faint` floor is 3:1 (`palette.rs:94-95`, `:139`), below the overlay's 4.5:1 text floor (`docs/ui/colour.md:42`). Pinning it to `#808C99` restores 5.07:1 on menu and 5.40:1 on status; on the raised `#26303D` it is 3.86:1, so do not use faint text as a label/value on a selected/raised row (`docs/ui/colour.md:35-44`).
- `from_palette`'s default focus is blue; using it with an amber accent adds a third hue and breaks `docs/ui/colour.md:56-58`. Use `PaletteFocus::Accent`.
- `Kit` is not `Copy`; it owns `Vec<Shadow>` elevation layers (`kit.rs:113-129`, `:230-249`). Build it once per weight/theme change, store it in `UiState` or `Host`, and rebuild only when `type_weight` or the dark/light choice changes. Do not rebuild it per frame.
- Global type weight: rebuild `Kit.ty` (12 styles) from the base weight, preserving relative emphasis with `weight + (style.weight - 400)` clamped to 1..1000. `Button` uses `ui_medium`/`small`, `Dialog` uses `ui_medium`, `Switch` uses `small`, `Segmented` uses `ui`, `Keybind`/`Badge` use `small_medium`, `Card` uses `body_medium` (`actions.rs:337-346`; `dialog.rs:48-52`; `switch.rs:101-108`; `segmented.rs:74`; `keybind.rs:35`; `badge.rs:51-55`; `card.rs:71`). `List` is the one component that will not follow (`list.rs:96`).
- The HUD is a local surface: `#0F141A` at 0.94, a 12-point inset and padding, a 6-point gap, and a 380-point width (`ui/shim/src/lib.rs:498-509`; `docs/ui/spacing.md:22-39`). Do not use `Kit::layer_01` for the HUD; it is opaque and would lose the scene backdrop.
- HUD opacity: the authored 0.94 over a white scene gives primary 14.21:1, secondary 7.43:1, tertiary 4.67:1 (computed from `#EDF2F7`/`#A6B2BF`/`#808C99` over `#0F141A` composited at 0.94 on white; WCAG 2 formula). At 0.85 it is 10.64/5.56/3.50; at 0.75 it is 7.33/3.83/2.41. The 4.5:1 floor for tertiary text fails below 0.94 (`docs/ui/colour.md:42`; `docs/design/review.md:57-58`). Do not ship a continuous HUD opacity slider under the current palette; either keep the HUD at 0.94, promote tertiary text to secondary below 0.9, or make opacity a debug-only control.
- Reduce motion is viable and cheap: add `reduce_motion` to the snapshot, call `cx.reduced_motion(state.reduce_motion)` in the view, and Rune applies it to the scene (`vendor/rune/crates/rune/src/runtime/cx.rs:260`; `runtime.rs:423`; `runtime/commit/apply.rs:14-17`). It is required if the kit's control motion is adopted (`docs/design/motion.md:100-118`).

### 6. Actions and state ownership

- Handlers run inside `frame_step` with `&mut S`; a handler that calls back into the shim aliases `&mut Runtime` and is undefined behavior (`docs/research/rune-host-boundary.md:199-206`, `:330-354`). The clean path is a `Vec<UiAction>` in `S`, drained after `frame` returns.
- The current `UiAction { kind, value }` is 8 bytes (`ui/shim/src/lib.rs:189-194`); the new surfaces need an id and a float. Recommend 16 bytes:

```c
typedef struct {
  u32 kind;   /* Ui_Action_Kind */
  u32 id;     /* setting, object id, palette index */
  i32 value;  /* option index, -1/+1, bool, field */
  f32 f;      /* opacity, weight, yaw, intensity, range */
} Ui_Action;
```

- Proposed action set:

| Action | Payload | Odin target |
| --- | --- | --- |
| `Close_Menu` | — | `game.menu_close` |
| `Toggle_Inspector` | — | `debug.inspector_open` |
| `Palette_Select` | `id = index` | preview only; `menu.selected` / palette selection |
| `Palette_Pick` | `id = index` | `game.Palette_Select` + `Palette_Pick` |
| `Settings_Set` | `id = setting`, `value = option`, `f = value` | `settings.*`; window changes go through `apply_window_settings` |
| `Object_Set` | `id = object`, `value = field`, `f = value` | `game.Set_Body` / new `Set_Selected_Yaw` |
| `Object_Toggle` | `id = object`, `value = field` | `game.Flip_Body` |
| `Object_Duplicate` | `id = object` | `game.Duplicate_Selected` |
| `Object_Delete` | `id = object` | `game.Delete_Selected` |
| `Lamp_Set` | `id = object`, `value = field`, `f = value` | `game.Light_Set_Intensity` / `Light_Set_Range` |
| `Lamp_Kind` | `id = object`, `value = kind` | `game.Light_Set_Kind` |
| `Lamp_Color` | `id = object`, `value = colour` | `game.Light_Set_Color` |
| `Type_Weight_Set` | `f = weight` | `settings.type_weight` (debug only) |

- Settings ids: `Window_Mode`, `Display`, `Resolution`, `Sprint_Mode`, `Hud_Opacity`, `Reduce_Motion`. `Settings_Set` covers all six; `value` is the option index for the first four and the boolean for reduce motion; `f` is the 0..1 opacity.
- The existing `game.Edit_Action` already has `Set_Body`, `Flip_Body`, `Delete_Selected`, `Duplicate_Selected`, `Light_Set_Kind`, `Light_Set_Color`, `Light_Set_Intensity`, `Light_Set_Range`, and `Placement_Set_Snap` (`src/game/editor_types.odin:14-45`, `:76-135`; dispatch at `src/game/editor_apply.odin:23-90`). Reuse them; do not add a parallel edit vocabulary.
- Yaw has no absolute setter. `Rotate_Selected` is relative (`src/game/editor_object.odin:120-144`), so an inspector slider either sends a delta (`target - current`) computed in Odin or adds `Set_Selected_Yaw { degrees }` to `Edit_Action` and `editor_set_yaw`. Prefer the absolute setter; it keeps the slider's value and the object's yaw from drifting.
- Snap is placement state, not selection state: `Placement_Set_Snap`/`Placement_Toggle_Snap` (`src/game/editor_apply.odin:69-73`). The inspector's object section should not show "snap" unless it is editing the next placement; put it under a Placement section.
- State ownership: Odin owns surface open flags, selected row/item/object, all setting values, all palette text, and all world state. Rune owns focus, hover, press, drag capture, scroll offset, and a local preview for a value being dragged. The snapshot overwrites the preview when it matches; a mismatch is not a second source of truth.
- The integration plan says "the shim owns the UI state; Odin never writes UI state" (`docs/research/rune-integration-plan.md:141`, `:176-181`), but the implemented shim writes menu, palette, and selection state from the snapshot every frame (`ui/shim/src/lib.rs:788-861`). The workable rule is the one above: Rune owns interaction state, Odin owns semantic state. Update the plan or the code; do not leave the contradiction.
- `ui_frame` clears `actions` at the start (`ui/shim/src/lib.rs:793`); Odin must drain before the next call. The harness `ui_click` calls `ui_frame` a second time and reads actions immediately, so it works; a second call before a drain would lose the first queue. Document one `ui_frame` per frame and one drain per frame, or stop clearing in `ui_frame` and clear only in `ui_actions_clear`.
- Window apply is a special case: `apply_window_settings` currently runs only when `apply_menu_input` changed `settings.window` (`app_loop.odin:97-101`). A `Settings_Set` applied after `draw` in `main.odin:228-253` will not call it, so a window-mode or resolution change from the new dialog would never reach the window. Route every settings action through one `apply_settings_change` helper that both paths call, or apply UI actions before the window check.

### 7. Debug inspector layout and pointer-free ownership

- The current debug inspector is the same top-left status panel with object rows (`docs/ui/README.md:79-86`; `src/game/hud_debug.odin:29-151`). The new direction is a right-side rail; the HUD keeps the player/status rows.
- Proposed geometry: 320 points wide, inset `12` from the top and right, max height `target_height - 24`, internal `scroll` + `ScrollBar` when the sections overflow. Sections: Object (id, prefab, body, yaw), Placement (prefab, height, yaw, snap), Lamp (kind, colour, intensity, range), Debug (type weight, HUD opacity). This fits at 800x600 with a 320-point rail if the palette/menu are closed.
- Proposed palette geometry: a 640-point `Dialog` with a 3-column x 4-row grid of 120x92 cards on the left and a 220x220 preview on the right; 11 prefabs fit, and the preview is a `Shape` isometric box built from `half_extents` with the prefab colour, a body line, and a light line. At 800x600 the dialog is 640x520 with 80/40 margins, inside the fit gate (`docs/design/review.md:54-55`).
- The palette is a centered 640-point dialog; at 800x600 it overlaps a 320-point right rail (`640` centered is x=80..720; the rail is x=468..788). Hide the inspector while the palette or settings dialog is open. The two debug surfaces are never visible together.
- Pointer-free is one bool today: `Editor_Focus.pointer_free = tool == .Palette` (`src/game/editor_focus.odin:13-20`), and `Focus.pointer_free = menu.open || editor.pointer_free` (`:32-39`). `input.Focus` is the whole frame's ownership: the game half plus the platform's `captured` and `pointer_available` (`src/input/input.odin:7-13`), and `sync_cursor` releases capture from `focus.pointer_free` (`cursor.odin:23-38`). Add `inspector: bool` to `Editor_Focus` and OR it: `pointer_free = tool == .Palette || inspector`.
- Extend the resolver order from "menu, then tool, then world" (`src/input/resolve.odin:11-17`, `:28-37`, `:56-59`) to "menu, then inspector, then tool, then world." When the inspector owns the pointer, return before `apply_debug_pointer`; when it does not, the existing palette/placement routes run unchanged.
- Coexistence with world drag/placement: make the interactive inspector and the world pointer tools mutually exclusive. Opening the inspector cancels an active placement or drag (`editor_cancel_editing`, `src/game/editor.odin:100-103`); arming a placement or starting a drag closes the interactive inspector. A read-only rail can stay visible while the world tools run, but it must not take pointer input and must not set `pointer_free`.
- The keyboard toggle is `I` (or `Tab` for the palette; `I` avoids a collision with `M`, `G`, `C`, `K`, `Q`, `E` used by the editor, `src/input/resolve.odin:114-157`). `Esc` closes the inspector before it opens the menu, matching the palette's cancel-first rule (`resolve.odin:89-94`).
- The inspector's controls return the actions in section 6; the selected object id in the snapshot is authoritative. If the object is deleted, the next snapshot clears the section; Odin validates the id before applying an edit.
- The current `Debug` button is not a debug-mode toggle: it returns `Toggle_Debug`, and `main.odin` flips `loop.debug_view` (physics debug lines), not `debug.active` (`main.odin:235-236`). `F2` is the debug-mode key (`resolve.odin:188-189`). This is a real defect for an inspector entry point; either remove the button, relabel it "Physics", or make it call `debug_mode_toggle` and open the inspector.

### 8. Harness: driving a pointer UI and proving the action applied

- `Runtime::find(key)` returns the centre of the keyed element in points (`vendor/rune/crates/rune/src/runtime/elements.rs:385-397`); `presented(key)` returns the drawn rect and opacity (`:402-405`); `elements()` returns role, label, focused, hover, press, selected, and rects (`:6-76`, `:201-377`). These are enough for a test harness to locate a control, drag from a point, wheel over it, and assert focus/selection.
- They are not enough to drive the game: `find` returns only the first key match, `presented` is a drawn rect not a dispatch hit list, and `elements()` is expensive and allocates strings. Do not use them in the input path; use real events (`docs/research/rune-host-boundary.md:210-219`).
- The harness `ui` command currently clicks by point and only checks that at least one action was produced (`src/harness/ui_command.odin:39-48`). It does not apply the action to the session, so `scenarios/rune-palette.json` does not prove the game selected a row; it proves the shim emitted an action. This is a false-green risk for the palette acceptance.
- `ui_click` also passes a zero `UiSnapshot` and null panel/menu/palette pointers (`src/renderer/ui_bridge.odin:340-351`), so a harness click resets the shim's weight, fx, and menu-open fields before it clicks. A click-by-key command must preserve the current snapshot or call a shim entry that queues events without rewriting the view model.
- Add `ui` forms: `{click: "palette:4"}`, `{drag: {from: "inspector.opacity", dx: 40, dy: 0, steps: 4}}`, `{wheel: {at: "inspector.scroll", dy: -120}}`, `{focus: false}`, `{key: {code: "Down", action: "repeat"}}`, `{expect: {kind: "Palette_Select", id: 4}}`. Resolve keys with `find`/`presented` in the shim; do not pass pixel coordinates from the scenario.
- A drag must span frames: move+down, `frame(dt)`, one move per step, `frame(dt)`, up, `frame(dt)`. `pointer_down` uses the last-built hit list, and `on_drag` dispatches Down/Move/Up in order (`vendor/rune/crates/rune/src/runtime/input/pointer.rs:177-297`; `el/handlers.rs:34-41`). A single batch with down/move/up can work for a click but is a poor test for a drag.
- Apply the action queue through the same helper the game uses; fail when the expected action is absent, and capture after the apply. Share the switch currently in `main.odin:228-253`; do not duplicate it in the harness.
- Proposed `state.ui` section: `{surface, focus, hover, pressed, pointer_free, actions: [{kind,id,value,f}], menu: {open, item}, palette: {open, selected}, inspector: {open, selected_id, section}}`. Add an optional `ui_tree` command that dumps `elements()` to `report.json`; do not include it in every `state` reply.
- Determinism: call `frame(0.0)` once after attach (the shim does at `ui/shim/src/lib.rs:692`), use a fixed `dt`, set `time_scale=1.0`, `reduced_motion` explicitly, and `help_delay` explicitly when a tooltip is asserted (`docs/research/rune-host-boundary.md:317-328`).
- Capture `state.ui` after the action is applied and before the next event; the current `ui_click` path returns actions but leaves them for the caller, so the harness must drain `ui_actions_clear` after applying (`src/renderer/ui_bridge.odin:340-351`).

### 9. File architecture for the 1,160-line shim

- `ui/shim/src/lib.rs` is 1,160 lines and owns the C ABI, Vulkan adoption, wgpu device, `UiState`, the view, menu, palette, fx planning, and string copying (`wc -l ui/shim/src/lib.rs`; contents at `ui/shim/src/lib.rs:1-1160`).
- The repo's 400-line gate applies to first-party `.odin` files only; `make check-lines` counts `.odin` sources and exits at 400 (`Makefile:162-171`). Rust has no repo gate; Rune's own convention is 800 non-test lines and 1,500 hard (`vendor/rune/AGENTS.md`, "Changes").
- Proposed split, target 250-350 lines per file, `lib.rs` under 150:

| File | Owns | Target |
| --- | --- | --- |
| `lib.rs` | `mod` list, `HOST` static, the `ui_*` extern entry points | 120 |
| `ffi.rs` | `#[repr(C)]` structs, event decode, string/row copy | 220 |
| `host.rs` | Vulkan adoption, wgpu device, target textures, `Renderer`/`FxRenderer` lifetime | 280 |
| `state.rs` | `UiState`, `PanelState`, `MenuState`, `PaletteState`, `InspectorState`, snapshot ingest, revision | 220 |
| `theme.rs` | every colour literal, `Kit` construction, `weighted_text`, weight application | 180 |
| `input.rs` | stable key codes, mods, event dispatch, action queue | 180 |
| `paint.rs` | `prepare`, `encode_layers`, `draw_target_range`, `submit` | 180 |
| `fx.rs` | `fx_plan`, `draw_effect` (the existing rune-fx demo) | 150 |
| `text.rs` | weighted span and mono helpers | 80 |
| `components/panel.rs` | surface, header, hairline, row | 100 |
| `components/slider.rs` | local slider | 180 |
| `components/grid.rs` | palette grid + card | 150 |
| `components/section.rs` | kit `Card` wrapper + section header | 80 |
| `views/hud.rs` | status panel and action column | 250 |
| `views/settings.rs` | dialog + rows/controls | 300 |
| `views/palette.rs` | grid + preview + hints | 300 |
| `views/inspector.rs` | right rail, object/placement/lamp/debug sections | 350 |

- Ownership rule: `theme.rs` is the only file with colour literals; `views/*` own layout; `components/*` own reusable behaviour; `state.rs` owns the snapshot; no view reads game state; no component reads `UiState`.
- `ui/shim/src/spike.rs` is a separate bin (284 lines) that duplicates Vulkan instance/device setup; keep it as a smoke test, do not fold its helpers into the library (`ui/shim/src/spike.rs:1-60`).
- Moving colour literals out of `lib.rs` requires a docs change: `docs/ui/colour.md:56` and `docs/design/review.md:32` name `ui/shim/src/lib.rs` as the only place. Rename that to `ui/shim/src/theme.rs` in the same change, or keep a single `theme.rs` and add it as an explicit exception.

## Conflicts

1. **`docs/research/rune-ui-port.md` is stale and contradicts the chosen route.** It recommends porting three Rune ideas into Odin and rejecting the Rune tree, layers, and `tok.rs` (`docs/research/rune-ui-port.md:11-42`, `:170-182`). It cites `src/ui/layout.odin`, `src/renderer/hud_rows.odin`, `src/renderer/hud_palette.odin`, and `src/renderer/menu_input.odin`; those files no longer exist. It predates HARB-342's "Rune is the UI layer" decision. Do not use it for the component layer; it is only useful for the "shape once" and "labeled rect list" ideas.
2. **The palette is documented as a list with a text preview; the new direction is a grid with a preview and card selection.** `docs/ui/README.md:71-78` and `docs/ui/components.md:46-57` say "a Rune list, not a grid" and "the preview is text, not an isometric drawing." The palette data already carries `half_extents`, `color`, `body`, and light text (`src/ui/ui.odin:52-63`; `src/game/palette_view.odin:48-63`), so the grid/preview is a view change, not a data gap.
3. **The debug inspector is documented as the same top-left panel; the new direction is a right-side rail.** `docs/ui/README.md:79-86` says it is the same top-left status panel. `src/game/hud_debug.odin:29-151` fills that panel with 12 rows. A right rail needs a separate `Hud`/`Inspector` section and a new `Ui_Inspector` payload.
4. **The UI docs ban hover, repeat, and drag; the component layer needs all three.** `docs/ui/states.md:87-92` says "There is no hover, no key repeat, and no drag." The slider needs drag and focus; kit controls need hover; `on_step` needs repeat. Update the rule or keep the overlay pointer-only on the old row path, which would make the kit controls non-functional.
5. **The UI docs ban shadows, rounded panels, gradients, and all overlay motion; the kit uses all four.** `docs/ui/spacing.md:67-68` says "No rounded panel, no shadow, no gradient"; `docs/ui/README.md:95` and `docs/design/motion.md:1-14`, `:100-118` say the overlay never animates. `Dialog` uses radius 6, `elevation.overlay`, and `token_motion` (`vendor/rune/crates/rune-kit/src/dialog.rs:57-61`); `Switch` uses gradients, shadows, outline, and motion (`switch.rs:151-166`); `SegmentedControl` uses an animated indicator (`segmented.rs:89-106`). This is a design change, not a tweak. `docs/design/motion.md:108-112` itself says a future motion feature needs a settings toggle, which is exactly the reduce-motion row.
6. **Type weight is in the settings menu; the new direction moves it to the debug inspector.** `docs/ui/type.md:31-39` and `docs/ui/states.md:40-47` put it in the menu; `src/game/menu.odin:10-42`, `:216-223` build the row. `scenarios/rune-menu.json` and `scenarios/rune-weight.json` depend on it. Moving it changes `MENU_ITEM_COUNT`, the item enum, the harness `menu` command, and both scenarios.
7. **Colour literals are required to live in `lib.rs`; the module split puts them in `theme.rs`.** `docs/ui/colour.md:56` and `docs/design/review.md:32` flag a literal outside `ui/shim/src/lib.rs`. The split is necessary to keep the shim maintainable; update the docs and the review checklist in the same change.
8. **The integration plan says the shim owns UI state and Odin never writes it; the shim mirrors all UI state from Odin.** `docs/research/rune-integration-plan.md:141`, `:176-181` versus `ui/shim/src/lib.rs:788-861`. Resolve as "Rune owns interaction state; Odin owns semantic state," and update the plan.
9. **The UI README says Rune hit-tests the view; the shim does its own key hit-test.** `docs/ui/README.md:41-42` says the pointer travels to Rune and Rune hit-tests; `ui/shim/src/lib.rs:863-880` uses `element_key_at`, not `Runtime::pointer_*`. The doc describes the intended design, not the code.
10. **The harness `ui` command does not apply the action it asserts.** `src/harness/ui_command.odin:39-48` only checks `len(actions) == 0`; it never calls `editor_apply` or the settings apply. `scenarios/rune-palette.json` therefore does not prove "the game applies the selection" (HARB-356 acceptance). Fix the harness before trusting the palette scenario.
11. **The `Debug` button does not toggle debug mode.** `docs/ui/components.md:20-22` says it toggles debug mode; `main.odin:235-236` toggles `loop.debug_view` (physics debug lines). `F2` is the debug-mode key (`resolve.odin:188-189`). This blocks using the button as an inspector entry point.
12. **The live palette pointer route is dead.** `main.odin:121` passes a zero `Palette_Hit` to `resolve`, while `resolve.odin:240-264` expects the renderer's card hit. The live palette click works only through the Rune `Palette_Select` action (`main.odin:237-250`); `Palette_Hit` should be deleted, not extended.
13. **`rune-kit::List` breaks two documented rules.** It hardcodes `TextStyle::new(14.0, 500.0)` (`vendor/rune/crates/rune-kit/src/list.rs:96`), so the type-weight control cannot reach it, and it uses `.truncate()` (`list.rs:186`), while `docs/ui/type.md:70` bans truncation. Do not use `List` for the inspector; use kit `Card`/rows or a local list.
14. **`rune-kit::ButtonVariant::Danger` adds a red hue.** `actions.rs:26-39` offers `Danger`; the overlay has a two-hue palette and says "No third hue in the view" (`docs/ui/colour.md:56-58`). Use a neutral/ghost "Delete" with the word carrying the result, or make the red a deliberate design change.
15. **The current `Ui_Action` set has three actions; the new surfaces need about thirteen.** `src/renderer/ui_frame.odin:17-21` and `docs/ui/states.md:73-85` list only `Close_Menu`, `Toggle_Debug`, `Palette_Select`. The action table in section 6 is an extension, not a contradiction; the docs must list the new set.

## Not found

- No build, `cargo check`, or link of `rune-kit` in this workspace. The dependency graph is code-read (`vendor/rune/crates/rune-kit/Cargo.toml:5-15`); compile time, binary size, and any feature conflict with the shim's `wgpu` feature set were not measured.
- No in-engine contrast measurement. The authored hex values are from `docs/ui/colour.md:35-40`; the alpha-over-white numbers in section 5 were computed with the WCAG 2 relative-luminance formula, not captured from a frame.
- No rendered test of `Kit::from_palette` with the proposed seed. The exact derived `layer_02/03`, `hover`, and `pressed` values are not known; they must be measured/reviewed before pinning the docs' table.
- No headless test of `Dialog`, `Select`, `Switch`, or `SegmentedControl` under `Runtime` with `LoadOp::Load`; code-read only.
- No test of `Runtime::find` with duplicate keys across surfaces. The harness must scope keys (`menu:*`, `palette:*`, `inspector:*`) or `find` returns the first match.
- No profile of `Runtime::elements()` at this overlay's element count. The host-boundary note says it is not cheap (`docs/research/rune-host-boundary.md:219`); no number was taken.
- No verification that `Kit::from_palette`'s `blend_over` matches the shim's actual target format at runtime. The target is sRGB (`src/renderer/offscreen.odin:9-10`), and `Renderer::set_format` sets `srgb_blend = !format.is_srgb()` (`vendor/rune/crates/rune/src/render/pipelines.rs:205-217`), which implies linear blending and `blend_over`; this was not run.
- No check of `rune-kit`'s `ScrollBar` with a non-scroll inspector rail; it expects a `scroll` viewport (`vendor/rune/crates/rune-kit/src/scroll_bar.rs:765-777`).
- No design decision on whether kit control motion replaces the no-motion rule. This note gives both branches; the owner must choose.
- `rata issue show HARB-321 --comments` returns a different project's "Rebuild UI around a dense ReUI shell" issue (jyoti/ReUI) with no comments. It is not a prior decision for this Rune layer; checked and not applicable.
- No source of a trash/duplicate glyph in `rune-kit::glyphs`; the built-ins are check, chevrons, caret, triangles, close, clear, copy, search, lock, eye, eye-off, circle-x, dash (`vendor/rune/crates/rune-kit/src/glyphs.rs:1-184`). Use text labels or local `Icon` paths.

## References

- `docs/ui/README.md` — the layer rule, the snapshot, the palette/inspector descriptions; lines 3-29, 41-46, 71-95 are the current contract that the new layer changes.
- `docs/ui/components.md` — status panel, settings menu, palette, notice, hint, fx; lines 13-57 and 79-84.
- `docs/ui/type.md` — type weight, numeric rule, copy, bans; lines 25-39, 64-71.
- `docs/ui/colour.md` — the authored palette, contrast table, and two-hue rule; lines 10-58.
- `docs/ui/spacing.md` — panel geometry, scale, surfaces, no-shadow/no-gradient rule; lines 22-68.
- `docs/ui/states.md` — row kinds, selection, blocked rows, slider, action set, input limits; lines 7-92.
- `docs/design/README.md` — the visual point of view; lines 6-25.
- `docs/design/review.md` — evidence rule, flag-on-sight list, ordered check; lines 6-69.
- `docs/design/motion.md` — the no-overlay-motion rule and the missing reduced-motion setting; lines 1-14, 100-118.
- `docs/research/rune-host-boundary.md` — public Runtime input, hit-test timing, action queue, C ABI proposal; lines 84-104, 173-181, 199-219, 330-362, 368-494.
- `docs/research/rune-paint-contract.md` — primitive kinds, kit coverage, layer/shadow/gradient facts; lines 24-80, 280-297, 315-328.
- `docs/research/rune-integration-plan.md` — the architecture and the "shim owns UI state" claim; lines 141, 176-181, 150-220.
- `docs/research/rune-ui-port.md` — the superseded "port ideas into Odin" recommendation; lines 11-42, 170-205.
- `ui/shim/src/lib.rs` — the current shim: C ABI, view, menu, palette, input drop, painting; lines 1-1160, especially 179-194, 490-594, 673-771, 774-901, 922-1061.
- `ui/shim/src/spike.rs` — the device-adoption smoke bin; lines 1-60.
- `src/renderer/ui_bridge.odin` — the C ABI marshalling, pointer conversion, and harness click; lines 123-131, 163-329, 340-351.
- `src/renderer/ui_frame.odin` — the UI frame and action kinds; lines 6-45.
- `src/ui/ui.odin` — the wire model; lines 9-80.
- `src/frame/frame.odin` — the HUD composition and snapshot; lines 158-199.
- `src/input/resolve.odin` — the resolver order, menu keys, palette/world pointer; lines 11-69, 198-296.
- `src/game/editor_focus.odin` — `Editor_Focus` and `Focus`/`pointer_free`; lines 6-39.
- `src/game/menu.odin` — items, settings change, type weight, menu view; lines 10-42, 111-155, 200-262.
- `src/game/hud_debug.odin` — the current inspector rows; lines 4-11, 29-151.
- `src/game/palette_view.odin` — palette data and light preview; lines 24-114.
- `src/game/editor_types.odin` — the `Edit_Action` vocabulary; lines 14-135.
- `src/game/editor_apply.odin` — the action dispatch; lines 1-90.
- `src/game/editor_object.odin` — body/yaw/rotate/duplicate/delete; lines 120-201.
- `src/platform/input.odin` — SDL event collapse, dropped repeats, captured-only wheel; lines 17-43, 128-145.
- `src/harness/ui_command.odin` — the `ui` command that checks only action count; lines 39-48.
- `src/harness/state_editor.odin` — the current `state.editor.focus.pointer_free`; lines 17-19, 54-60.
- `vendor/rune/crates/rune-kit/src/` — `kit.rs`, `neutral.rs`, `palette.rs`, `actions.rs`, `switch.rs`, `segmented.rs`, `select.rs`, `card.rs`, `dialog.rs`, `list.rs`, `badge.rs`, `keybind.rs`, `overlay.rs`, `scroll_bar.rs`, `lib.rs`.
- `vendor/rune/crates/rune/src/runtime/input/` — `pointer.rs`, `gesture.rs`, `keys.rs`, `touch.rs`.
- `vendor/rune/crates/rune/src/runtime/` — `frame.rs`, `elements.rs`, `commit/apply.rs`, `paint/build.rs`.
- `vendor/rune/crates/rune/src/render.rs`, `render/pipelines.rs`, `render/upload.rs`, `render/layers.rs`, `render/variant.rs` — the renderer path.
- `vendor/rune/crates/rune/src/el.rs`, `el/handlers.rs`, `el/a11y.rs`, `el/visuals.rs`, `el/tx.rs` — focus, drag, range, opacity, actions.
- `vendor/rune/crates/rune/src/shape.rs` — `Shape` fills/strokes for the palette preview; lines 38-80.
- `vendor/rune/examples/settings/src/main.rs` — the hand-built slider and row/toggle/segmented patterns; lines 45-60, 176-198, 203-252, 284-356.
- `vendor/rune/examples/kit-gallery/src/main.rs` and `stories.rs` — the working `rune_kit::root` + `Dialog`/`Switch`/`SegmentedControl` usage; `main.rs:112-121`, `stories.rs:265-290`.
- `vendor/rune/AGENTS.md` — the Rust file-size convention; "Changes" section.
