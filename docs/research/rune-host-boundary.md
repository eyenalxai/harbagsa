# Rune host boundary: what crosses to Odin, and what to patch

**Date:** 2026-11-10
**Status:** Code-read research note. No build, no run, no C ABI prototype, no pixel comparison. Source is `rune` at commit `f18ead8` (2026-11-10), crate version `0.0.1`.
**Question:** If a Rust shim owns a Rune `Runtime<S>` and runs headless on the game's main thread, what exactly crosses a C ABI to an Odin game, and what is the minimum patch to Rune to make synchronous stepping possible?

## Answer

The boundary is mostly data, not Rust objects. The shim should own `Runtime<S>` directly, call `Runtime::frame(dt)` once per game frame, and copy a few flat outputs to Odin: the instance stream, the two atlases, an optional element/hit record list, and an app-defined action queue. The Rust view, `S`, handlers, `Scene`, `Node`, `ElementInfo`, `GlyphQuad` and `SurfaceDraw` never cross as Rust types.

Synchronous stepping already exists at the `Runtime` level. `Runtime::frame(dt)` is public (`crates/rune/src/runtime/frame.rs:305-307`), and the headless harness and the `--desktop` compositor both drive frames with it (`crates/rune/src/tooling/headless.rs:311-313`, `crates/rune/src/desktop/window.rs:312`). There is no synchronous step on `App`: `App` has only `run` and `try_run` (`crates/rune/src/app.rs:578-604`). `App::windowless()` only starts with no window and `keep_running` on; it is not a headless or step API (`crates/rune/src/app.rs:353-358`).

So the minimum patch for stepping is **zero lines**, provided the shim uses `Runtime`, not `App`. The patches that remain are for optional outputs that are currently `pub(crate)` or private: the full hit list, standalone glyph quads, per-page atlas dirty rows, physical-plus-logical key dispatch, system materials, and some shell request fields. Those are listed below with exact visibility.

The largest real risk is not the ABI. It is that `Runtime::instances` is a **renderer contract**, not a scene description: Odin must implement Rune's uber shader, clipping/fade packing, layer records, backdrop blurs and text coverage rules to get parity. Copying the instance buffer alone gives geometry, not pixels.

## Evidence

All line ranges are from `rune` `f18ead8`.

### 1. How a frame runs today

#### 1.1 File map: the obvious filenames are not the frame loop

- `crates/rune/src/frame.rs` is 8 lines of module declarations: `clock`, `encoded`, `host_clock`, `present_time`, `present_worker`, `profile`, `surface_stats` (`frame.rs:1-8`). It contains no loop.
- `crates/rune/src/input.rs` is 13 lines of module declarations (`input.rs:1-13`). The event types live in `edit/keys.rs`, `edit/ime.rs`, `input/canvas_input.rs` and `input/physical_input.rs`.
- `crates/rune/src/desktop.rs` is the `--desktop BACKDROP.png` multi-window compositor (`desktop.rs:1-4`), not the single-window frame loop. Its per-frame loop is `desktop.rs:361-495`; each member advances with `rt.frame(dt)` (`desktop/window.rs:312`).
- `crates/rune/src/app.rs` owns the app lifetime and chooses native vs headless at startup (`app.rs:578-604`). It does not contain a per-frame function.
- The actual runtime frame pass is `Runtime::frame` / `frame_split` / `frame_step` in `crates/rune/src/runtime/frame.rs:305-647`.

#### 1.2 Phase order and owner

`Runtime::frame(dt)` calls `frame_split(0.0, dt)` (`runtime/frame.rs:305-307`). `frame_split` advances the logical clock by `elapsed` and may split the step at due timer deadlines (`runtime/frame.rs:345-371`). `frame_step` is the real pass (`runtime/frame.rs:384-647`):

1. **Frame begins / clock.** `interaction_frame_begins`, live wake, font family follow, virtual-list frame begin (`runtime/frame.rs:387-398`). Clock update: `self.clock = self.wall_clock().unwrap_or(self.clock + elapsed)` (`runtime/frame.rs:407`). Headless video/recorder virtual clocks advance (`runtime/frame.rs:408-413`).
2. **Catch-up and timers.** Running motion catches up before handlers (`runtime/frame.rs:427`), loop clocks step, due wake deadlines drain (`runtime/frame.rs:428-432`), hover delays and press repeats fire (`runtime/frame.rs:433-434`).
3. **Poll.** `self.poll` runs with `&mut S`, the clock and a `Tx`; a true return marks a model change (`runtime/frame.rs:438-447`).
4. **Queued input.** The action queue is consumed in order, each with its own input arrival time (`runtime/frame.rs:465-521`). Key/IME/paste/file actions may force a commit before routing so the new tree resolves focus (`runtime/frame.rs:480-496`). `run_action` calls `dispatch_action` (`runtime/input/action.rs:260-527`).
5. **Latch requests.** `latch_requests` folds `Tx` shell, clipboard, popup, file-dialog, focus, title and window-frame requests into runtime fields (`runtime/frame.rs:531-548`, `runtime/frame.rs:165-227`).
6. **Final commit.** If state, layout, settle, virtual window or a read moved, `commit_for` runs (`runtime/frame.rs:554-577`). This is a second commit in a frame that already committed for routing. `stats.commits` counts both (`runtime/commit/apply.rs:54`).
7. **Scroll/reveal/selection.** Scroll destinations, reveals, selection changes and caret follow run after the commit (`runtime/frame.rs:580-624`).
8. **Motion and paint.** `step_motion(dt, instant_scroll)` steps the `Scene`, then calls `build()` (`runtime/frame.rs:634-636`, `runtime/frame.rs:667-758`, build call at 732). `build` clears and refills `instances`, `marks`, `hits`, `surfaces`, `materials` and `drawn` (`runtime/paint/build.rs:5-36`), and sets `stats.glyphs` (`runtime/paint/build.rs:1280`).
9. **Present.** Not in `Runtime`. The native window host uploads and draws the instances with `Renderer::prepare` / `Renderer::draw`, then `gpu.queue.present(frame)` (`window/draw.rs:273-283`). Headless does the same plus readback (`tooling/headless.rs:362-363`). The `--desktop` compositor draws each window into a slot and composites (`desktop.rs:426-470`).

Commit internals:

- `Runtime::commit` is `pub(super)` (`runtime/commit.rs:79-116`). It calls `measure_commit` (`commit.rs:96`), may re-measure after focus/caret sync (`commit.rs:100-109`), then `apply` (`commit.rs:110`).
- `measure_commit` is `pub(super)` (`runtime/commit/relayout.rs:76`); `measure` is `pub(super)` (`runtime/commit/measure.rs:29-31`) and builds the view through `build_tree` (`measure.rs:152`).
- Layout is `compute_layout`, `pub(super)` (`runtime/commit/text_layout.rs:331-370`), backed by Taffy.
- `apply` is `pub(super)` (`runtime/commit/apply.rs:7-916`); it writes the retained nodes, text layouts and `Scene` frames.
- `build` is `pub(super)` (`runtime/paint/build.rs:5`).

Visibilities of the whole chain are therefore private to the runtime module. A host cannot call `commit`, `build` or `step_motion` directly. It can only call `frame`, which is public.

#### 1.3 Is there a synchronous step API?

Yes, at `Runtime`:

- `Runtime::new(state, view, viewport, env)` is public (`runtime.rs:817-819`).
- `Runtime::with_text(state, view, viewport, env, text)` is public (`runtime.rs:821-823`).
- `Runtime::frame(dt) -> bool` is public (`runtime/frame.rs:305-307`). It returns whether anything still animates, not whether state changed.
- `Runtime::update` / `update_if` are public and run immediately with `&mut S` and a `Tx` (`runtime/frame.rs:121-153`).
- `Runtime::invalidate` is public (`runtime/frame.rs:121-123`).
- `Runtime::settle_all` is public (`runtime/frame.rs:297-300`).
- `Runtime::set_viewport` is public (`runtime/frame.rs:11-17`).
- `Runtime::window_focus` is public (`runtime/frame.rs:51-84`).

The headless harness uses exactly this: `runtime_for` constructs a `Runtime` (`tooling.rs:135-150`), `headless_configured` calls `rt.frame(0.0)` once so events at t=0 find a laid-out tree (`tooling/headless.rs:225-229`), then each frame calls `rt.frame(step)` (`tooling/headless.rs:311-313`). The comment says events reach a real window only after it has drawn, so the first frame is required (`tooling/headless.rs:177-179`).

`App` has no step. `App::run` panics on failure (`app.rs:578-580`); `App::try_run` returns an error (`app.rs:585-604`). On native it either calls `crate::tooling::try_headless` or `crate::window::run` (`app.rs:598-603`). The window host then consumes the `App` and builds a `Runtime` internally (`window.rs:482-512`); nothing exposes it. `App::on_frame_drawn` receives `&Runtime<S>` after a Drawn frame (`app.rs:532-535`), but it does not control timing and does not return a step result.

#### 1.4 What `windowless()` does

`App::windowless` sets `self.open = false` and `self.keep_running = true` (`app.rs:353-358`). The comment says "Start without a window; `AppHandle::open` or `activate` shows it. Implies `keep_running`." It does not select the headless tooling path. Headless is chosen only when `Args::headless()` is true in `try_run` (`app.rs:598-600`), which is the `--snap`, `--tree`, `--desktop` and related agent-tooling mode. Without such an argument, a windowless app still builds a winit event loop and waits until `open`/`quit`; it needs a display and the main thread.

### 2. Minimum patch: exact items and current visibility

#### 2.1 Already reachable, no patch

| Need | Item | Visibility | Where |
|---|---|---|---|
| Run one frame with a given dt | `Runtime::frame(dt)` | public | `runtime/frame.rs:305-307` |
| Construct a runtime | `Runtime::new` / `with_text` | public | `runtime.rs:817-823` |
| Queue pointer move | `Runtime::pointer_move(x,y)` | public | `runtime/input/pointer.rs:8` |
| Queue pointer down/up | `Runtime::pointer_down` / `pointer_up` | public | `runtime/input/pointer.rs:177`, `:299` |
| Queue pointer leave | `Runtime::pointer_leave` | public | `runtime/input/pointer.rs:356` |
| Queue wheel | `Runtime::wheel_event`, `wheel_xy`, `wheel_began`, `wheel_ended`, `wheel` | public | `runtime/input/gesture.rs:25`, `runtime/scroll/x.rs:141`, `:188`, `:204`, `runtime/input/pointer.rs:427` |
| Queue key down/up/repeat | `Runtime::key`, `repeat_key`, `key_up` | public | `runtime/input/keys.rs:261`, `:275`, `runtime/input/gesture.rs:220` |
| Queue IME | `Runtime::ime` | public | `runtime/input/keys.rs:279` |
| Queue text/paste | `Key::Text(String)`, `Runtime::paste` | public | `edit/keys.rs:30`, `runtime/input/keys.rs:289` |
| Queue physical key | `Runtime::physical_input(PhysicalInput)` | public | `runtime/input/physical.rs:32-36` |
| Queue focus | `Runtime::window_focus(bool)` | public | `runtime/frame.rs:51-84` |
| Resize/scale | `Runtime::set_viewport((w,h), scale)` | public | `runtime/frame.rs:11-17` |
| Touch | `Runtime::touch` | public | `runtime/input/touch.rs:69-75` |
| State | `Runtime::state` | public | `runtime.rs:391` |
| Draw list | `Runtime::instances` | public | `runtime.rs:469` |
| Marks | `Runtime::marks`, `track_marks` | public | `runtime.rs:472-473` |
| Scene | `Runtime::scene` | public | `runtime.rs:408` |
| Glyph atlas | `Runtime::text.atlas`, `Atlas::page_data`, `page_count` | public | `runtime.rs:405`, `text.rs:188`, `text/atlas.rs:216-223` |
| Image atlas | `Runtime::images`, `ImageAtlas::pages`, `ImagePage::data/dirty` | public | `runtime.rs:407`, `pixels.rs:216-249` |
| Elements | `Runtime::elements()` | public | `runtime/elements.rs:201-377` |
| Picking | `Runtime::find` / `element_at` / `presented` / `presented_pose` / `contains` | public | `runtime/elements.rs:385`, `:402`, `:419`, `:493`, `:473` |
| Stats | `Runtime::stats` (`commits`, `layout_nodes`, `glyphs`, `shaped`) | public | `runtime.rs:755`, `runtime/types.rs:549-554` |
| Shell request | `Runtime::shell_request` | public | `runtime.rs:706` |

#### 2.2 Not reachable, and what to do

| Need | Item | Current visibility | Where | Minimal change |
|---|---|---|---|---|
| Full hit list | `Runtime::hits: Vec<(NodeId, [f32;4])>` | private | `runtime.rs:480` | Add `pub fn hit_list(&self) -> Vec<...>` returning paths plus rects. `overlay_hits` is not enough: `hit_regions()` exposes only `El::hit` native-overlay regions (`runtime/input/pointer.rs:375-376`, filled at `runtime/input/hit.rs:240-242`). |
| Standalone glyph quads | `TextSystem::glyphs_in_band` | `pub(crate)` | `text/glyph_emit.rs:47-99` | Make `pub` and add a runtime accessor for node text layouts. `Node.text_layout` is private (`runtime/types.rs:99`); `Runtime.nodes` is `pub(crate)` (`runtime.rs:444`). |
| Glyph cache | `TextSystem::glyph_cache` | `pub(crate)` | `text.rs:214` | Only needed if the host wants the flattened per-paragraph glyph replay, not just painted quads. |
| Per-page atlas dirty rows | `Atlas.pages` and `AtlasPage.dirty` | `pub(crate)` | `text/atlas.rs:188`, `:105-110` | Add `pub fn take_page_dirty(&mut self, page: usize) -> Option<(u32,u32)>`. `Atlas.dirty` is public for page 0 only (`text/atlas.rs:182-184`). |
| Physical + logical key together | `Runtime::physical_then` | `pub(crate)` | `runtime/input/physical.rs:65-72` | Make `pub` if the host must send a physical key and its logical fallback in one action, as the winit host does (`window/events.rs:398-401`). `physical_input` alone loses the logical fallback. |
| System material draw list | `Runtime::materials` | `pub(crate)` | `runtime.rs:476` | Make `pub` or add an accessor. `MaterialDraw` itself is `pub(crate)` (`system_material/mod.rs:29-42`). |
| Minimize request | `Runtime::minimize_request` | `pub(crate)` | `runtime.rs:708` | Add a `take_minimize_request` accessor if Odin owns the window. |
| Window frame request | `Runtime::window_frame` | `pub(crate)` | `runtime.rs:721` | Add accessor if `Tx::resize_window` must move the Odin window. |
| Window title | `Runtime::window_title` | `pub(crate)` | `runtime.rs:723` | Add accessor if `Tx::set_title` must reach Odin. |
| Popup/file-dialog requests | `Runtime::popups`, `file_dialog` | `pub(crate)` | `runtime.rs:714`, `:716` | Add accessors if the game renders menus/file dialogs itself. |
| Clipboard read/paste requests | `paste_request`, `read_requests`, `clear_secret_request` | `pub(crate)` | `runtime.rs:693`, `:695`, `:702` | Add accessors if Odin owns the clipboard. `copy_request` is already public (`runtime.rs:691`). |
| Text family registry | `TextSystem::for_window` | `pub(crate)` | `text/families.rs:38-45` | Make `pub` only if the shim wants Rune's process-wide chosen family slots; otherwise `TextSystem::new` is public (`text.rs:286`). |
| A batch event entry point | none | n/a | n/a | Not needed: call the public event methods in order, then `frame(dt)`. There is no single `step(events, dt)` in Rune. |
| `App`-level step | none | n/a | n/a | Do not add one. The window host owns the `Runtime` privately (`window.rs:482-512`); exposing it would be a refactor, not a small patch. Use `Runtime` directly. |

The important result: **no change to `Runtime::frame` is needed**. The function already does the whole commit + layout + apply + paint pass, and it already processes a queued event batch. The host must call it on the same thread that constructed the runtime.

### 3. Event model

#### 3.1 Event types a host must produce

Rune's public event entry points are all "queue it, then frame":

- Pointer: `pointer_move(x, y)` (`runtime/input/pointer.rs:8`), `pointer_down(x, y)` (`:177`), `pointer_up(x, y)` (`:299`), `pointer_leave()` (`:356`), `button_down/up(x, y, PointerButton)` (`runtime/input/gesture.rs:179`, `:208`), `secondary_down/up(x, y)` (`runtime/input/secondary.rs:27`, `:49`).
- Wheel: `wheel_event(WheelEvent)` (`runtime/input/gesture.rs:25-38`), `wheel_xy(x, y, dx, dy)` (`runtime/scroll/x.rs:141-143`), `wheel(x, y, dy)` (`runtime/input/pointer.rs:427`), `wheel_began()` / `wheel_ended()` (`runtime/scroll/x.rs:188-212`).
- Keys: `key(KeyEvent)` (`runtime/input/keys.rs:261-263`), `repeat_key(KeyEvent)` (`:275-277`), `key_up(KeyEvent)` (`runtime/input/gesture.rs:220-225`), `physical_input(PhysicalInput)` (`runtime/input/physical.rs:32-36`).
- Text: a typed character is `Key::Text(String)` inside `KeyEvent` (`edit/keys.rs:29-77`). A paste is `Runtime::paste` (`runtime/input/keys.rs:289-291`).
- IME: `Runtime::ime(Ime)` (`runtime/input/keys.rs:279-281`); `Ime` is `Preedit(String, Option<(usize,usize)>)`, `Commit(String)`, `Enabled`, `Disabled` (`edit/ime.rs:11-22`).
- Focus: `Runtime::window_focus(bool)` (`runtime/frame.rs:51-84`). Losing focus also queues `PhysicalInput::FocusLost` via `keys_lost` (`runtime/frame.rs:90-93`) and cancels the pointer and held activation (`runtime/frame.rs:66-71`).
- Resize/scale: `Runtime::set_viewport((w,h), scale)` (`runtime/frame.rs:11-17`). There is no separate scale event.
- Touch: `Runtime::touch(id, TouchPhase, x, y, time)` (`runtime/input/touch.rs:69-75`); `TouchPhase::{Started,Moved,Ended,Cancelled}` (`:15-21`).
- Gestures: `magnify_event`, `rotate_event`, `smart_magnify`, `pinch_wheel` (`runtime/input/gesture.rs:93-111`).

#### 3.2 Coordinate space and conversion

All `Runtime` input coordinates are **logical window points**, not device pixels:

- The winit host converts cursor positions with `position.x as f32 / scale` and `position.y / scale` (`window/events.rs:454-455`), where `scale` is the window's `scale_factor()` (`window/events.rs:228`).
- Pointer hit rects are stored in points (`runtime/input/hit.rs:223-238`), and `Runtime::pointer_down` hit-tests in points (`runtime/input/pointer.rs:193-297`).
- Wheel pixel deltas are divided by scale; line deltas are multiplied by 40 (`runtime/scroll/x.rs:114-120`). `MouseScrollDelta::LineDelta` has no scale conversion by design.
- The viewport is points: `Runtime::viewport: (f32,f32)` and `Env::scale` are separate (`runtime.rs:409-411`, `runtime/cx.rs:5-8`). `set_viewport` stores points and the device-pixel scale (`runtime/frame.rs:28-44`).
- `Instance` output is device pixels, not points (`render.rs:201`, comment "One instance, in device pixels"). The host must not divide instance coordinates by scale again. Element rects from `elements()` are in points (`runtime/elements.rs:25`; `drawn` is `screen_r / s` at `runtime/paint/build.rs:476`).

#### 3.3 `Mods`, `PointerButton`, key codes

`Mods` is five `bool`s (`edit/keys.rs:9-19`):

```rust
pub struct Mods { pub shift: bool, pub cmd: bool, pub alt: bool, pub ctrl: bool, pub logo: bool }
```

`cmd` is the platform's primary shortcut modifier: Command on macOS, Ctrl elsewhere; off macOS it is set together with `ctrl` (`edit/keys.rs:4-19`). A C ABI should therefore define its own stable bits (shift, ctrl, alt, super/logo, primary) and map to `Mods` in the shim, rather than assuming `cmd == ctrl`.

`Key` is a non-exhaustive Rust enum (`edit/keys.rs:26-77`): `Text(String)`, named keys (`Enter`, `Backspace`, arrows, `PageUp`, `Escape`, `Tab`, `Insert`, `Function(u8)`, `ContextMenu`, etc.), `Command(char)`, and `Modifier { modifier: Modifier, pressed: bool }` (`:76`). `KeyEvent { key, mods }` (`:116-119`). A C ABI must map a stable integer key code to this enum; do not pass the Rust enum.

`PointerButton` is a non-exhaustive enum (`input/canvas_input.rs:89-102`): `Primary`, `Secondary`, `Middle`, `Back`, `Forward`, `Other(u16)`.

`PhysicalInput` is `Key { key: PhysicalKeyCode, mods, pressed, repeat }`, `Modifiers(Mods)`, `FocusLost` (`input/physical_input.rs:5-9`). `PhysicalKeyCode` is `winit::keyboard::KeyCode` (`shortcuts/keys.rs:3`), i.e. a winit enum. The host should use logical `KeyEvent`s for a game UI unless physical layout parity is required.

#### 3.4 How events enter the runtime

Input methods do not run handlers immediately except for a few state updates. They enqueue `Action` values:

- `pointer_down` does an immediate hit-test against the **last built** `hits` list, updates focus/selection state and queues `Action::Press`, `Action::FocusControl`, `Action::Drag`, etc. (`runtime/input/pointer.rs:177-296`). `on_press` is queued on release inside the element, not on down (`runtime/input/pointer.rs:347-353`). So a click needs both `pointer_down` and `pointer_up` before the frame that fires it.
- `pointer_move` queues `on_pointer_move` and drag actions against the last `hits` list (`runtime/input/pointer.rs:13-62`).
- `key` / `repeat_key` / `ime` only push to the queue (`runtime/input/keys.rs:261-281`).
- `wheel_event` may scroll immediately or queue `on_wheel` handlers (`runtime/input/gesture.rs:25-38`).
- `window_focus` may run `App::on_focus` immediately via `self.update(...)` and queues `Action::WindowFocus` (`runtime/frame.rs:51-84`).

The queue is drained at the next `frame` (`runtime/frame.rs:465-521`). This is why a first `frame(0.0)` is needed before pointer input: `hits` is filled only by `build` (`runtime/paint/build.rs:23`, `:36`, registration at `runtime/input/hit.rs:209-243`), and the headless harness explicitly does that (`tooling/headless.rs:225-229`).

Ordering is queue order. A batch of move, down, up is processed in that order within one frame. `pointer_down` uses the previous frame's hit geometry, exactly as a native window does between frames.

### 4. State and handlers

`Runtime<S>` only requires `S: 'static` (`runtime.rs:390`, constructors `:817-823`). `S` can be a plain data struct. It is stored by value in `Runtime::state`, which is public (`runtime.rs:391`). If `S` contains only `#[repr(C)]` POD fields, the shim can expose it as bytes; if it contains `String`, `Vec` or `Rc`, the shim must expose typed getters or a packed snapshot instead. Do not pass `S` itself as a Rust type across the C ABI.

A view is a plain function pointer, not a closure:

```rust
fn(&S, &mut Cx<S>) -> El
```

`runtime.rs:400`, and `AppSpec::view` has the same type (`tooling.rs:23`). The owner's Rune views must therefore be free functions (or a single dispatcher function), not closures over host state.

Handlers are type-erased `Rc<dyn Fn(...)>` values. `El::on_press_tx` stores an `Rc` that downcasts to `S` (`el/handlers.rs:10-20`); the shared type is `PressFn = Rc<dyn Fn(States<'_>, &mut Tx)>` (`el.rs:182`). At dispatch time the runtime clones the handler and calls it with `States` (`runtime/input/action.rs:400-405`). `States::cast::<S>()` checks the `Any` type and downcasts (`states.rs:8-33`); the `downcast` helper panics with "handler registered for a different state type than the app's" (`states.rs:56-58`). A handler therefore mutates `S` through `&mut S`, inside the frame, before the commit. The commit sees the final state after all handlers in the batch.

`Tx` is the handler's request channel to Rune, not to the game. It has public methods for focus, scroll, selection, clipboard, title, window resize, close/quit, font settings, motion and tracing (`el/tx.rs:157-554`). Its fields are `pub(crate)` (`el/tx.rs:16-118`). Custom game actions do not belong in `Tx`.

Can a handler call a C function pointer safely? At the ABI level, yes if the callback is `extern "C"`, all arguments are POD, and the callback does not unwind. The handler has `&mut S` and runs on the owning thread. The danger is semantic, not the call itself:

- `frame_step` holds `&mut Runtime` while `run_action` holds `&mut self`; the handler gets `&mut S` and `&mut Tx` (`runtime/frame.rs:472-521`, `runtime/input/action.rs:260-527`). A C callback that calls any `rune_host_*` function which touches the same runtime would alias `&mut Runtime` and is undefined behavior. That includes read-only calls such as `rune_host_instances` if they borrow the runtime while the frame is active.
- A C callback that calls back into `Runtime::update`, `frame`, `pointer_down` or `Tx` would re-enter the commit/transaction mid-handler. State is half-applied and the borrow is live.
- A C callback that `longjmp`s or throws across the Rust frames is undefined behavior. A Rust panic that unwinds through an `extern "C"` callback is also undefined behavior.
- The handler is `Rc`, so the runtime is not `Send`; the callback must run on the same thread as the runtime.

Queuing into `S` avoids all of that. See section 8.

### 5. Reading the result

#### 5.1 `Runtime::elements()`

`Runtime::elements()` is public (`runtime/elements.rs:201-377`). It returns `Vec<ElementInfo>`. `ElementInfo` has public fields (`runtime/elements.rs:6-76`), including:

- identity: `path: String`, `key: Option<String>`, `role: &'static str`, `parent: Option<usize>`
- semantics: `label`, `text`, `selected`, `help`, `focusable`, `focused`, `focus_visible`, `inert`, `exiting`, `expanded`, `item_selected`, `level`, `drag_out`, `caret`
- geometry/pose: `rect`, `target`, `visible`, `opacity`, `scale`, `blur`, `radius`, `fill`, `text_color`, `hover`, `press`, `moving`, `scrolling`, `scrolled`, `stuck`, `revealing`, `in_growing_row`, `virtual_extent`
- accessibility-ish flags: `loop_phase`, `live_intent`

Cost: it iterates every node, calls `scene.presented(n.id)` and `subtree_exiting`, walks ancestors for opacity/scale/blur/scroll/row state (`runtime/elements.rs:216-353`), runs `selection_ranges`, `link_elements` and `highlight_elements` (`:215`, `:374-375`), and clones multiple `String`s per element (`path`, `key`, `label`, `text`, `selected`, `help`). It is not a cheap per-frame call. For a per-frame debug/HUD path it is acceptable only if the element count is small; for a 60 Hz boundary, prefer `instances` plus a small keyed snapshot that the shim builds itself.

#### 5.2 `Scene` accessors

`Runtime.scene` is public (`runtime.rs:408`). `rune_motion::Scene` has public accessors:

- `presented(id) -> Option<Presented>` (`rune-motion/src/scene.rs:440-442`)
- `rest(id) -> Option<Rect>` (`:447-450`)
- `world(id) -> Option<Rect>` (`:453-455`)
- `phase(id) -> Option<Phase>` (`:436-438`)
- `contains`, `len`, `is_empty` (`:433`, `:456-461`)
- `store()` / `store_mut()` (`:378-384`), `now`, `set_time`, `set_pixel_scale`, `set_reduced_motion` (`:386-409`)
- `frame()` / `frame_at(t)` (`:675-774`), `present()` (`:780-789`)

The limitation is that `Scene` uses `NodeId`, and the host cannot map a `NodeId` to a path/key because `Runtime.nodes` and `node_index` are private (`runtime.rs:444-451`). `ElementInfo` gives paths but no `NodeId`. If Odin needs to correlate scene ids with semantic elements, add a `NodeId` field to `ElementInfo` or expose a keyed lookup. Without a patch, use `ElementInfo` geometry (`rect`, `target`, `opacity`, `scale`) rather than `Scene` directly.

#### 5.3 `paint/build.rs` output

`build` produces:

- `instances: Vec<Instance>` - public (`runtime.rs:469`). `Instance` is `#[repr(C)]`, 128 bytes, eight `[f32;4]`/`[u32;4]` fields (`render.rs:201-224`). The kind is `params[1]` (`render.rs:35-100`). This is the complete ordinary draw list.
- `marks: Vec<u32>` - public, one per instance, only while `track_marks` (`runtime.rs:470-473`).
- `surfaces: Vec<SurfaceDraw>` - public (`runtime.rs:474`), for video/native surfaces. `SurfaceDraw` contains `NativeSurface`, which is an `Arc<Mutex<...>>` (`native_surface/mod.rs:144-146`, `:341-351`). It is not C-compatible; a host that ignores video can ignore it.
- `materials: Vec<MaterialDraw>` - `pub(crate)` (`runtime.rs:476`), not reachable. `MaterialDraw` is also `pub(crate)` (`system_material/mod.rs:29-42`).
- `hits: Vec<(NodeId, [f32;4])>` and `overlay_hits: Vec<[f32;4]>` - private (`runtime.rs:480-481`). `hit_regions()` exposes only `overlay_hits` (`runtime/input/pointer.rs:375-376`).
- `drawn: Vec<[f32;4]>`, `drawn_scale`, `seen` - private (`runtime.rs:551-556`). `ElementInfo.rect` is built from `drawn` (`runtime/elements.rs:224`).

No patch is needed for the ordinary draw list. A patch is needed only for the hit list and materials.

#### 5.4 What a host can read without a patch

- `Runtime::state` (`runtime.rs:391`)
- `Runtime::scene` and its public accessors (`runtime.rs:408`)
- `Runtime::instances`, `marks`, `surfaces` (`runtime.rs:469-474`)
- `Runtime::text.atlas.page_count()` / `page_data()` (`text/atlas.rs:216-223`)
- `Runtime::images.pages` and `ImagePage.data/dirty` (`pixels.rs:216-249`)
- `Runtime::elements()`, `find`, `presented`, `presented_pose`, `element_at`, `contains`, `element_is_secure` (`runtime/elements.rs:186-516`)
- `Runtime::stats` (`runtime.rs:755`, `runtime/types.rs:549-554`)
- `Runtime::copy_request` (`runtime.rs:691`), `Runtime::shell_request` (`runtime.rs:706`)
- `Runtime::t`, `clock`, `env`, `viewport`, `reduced_motion`, `time_scale`, `animating`, `settled`, `double_click_interval`, `help_delay` (`runtime.rs:409-435`, `:747`, `:799-804`)

Cannot without a patch:

- full `hits` list
- per-node `text_layout`, glyph quads, glyph cache
- per-page atlas dirty rows
- `materials`
- `minimize_request`, `window_frame`, `window_title`, `popups`, `file_dialog`, `paste_request`, `read_requests`, `clear_secret_request`
- `NodeId` mapping for `Scene`
- raw `nodes` / `drawn` / `drawn_scale` / `built`
- `Action` / `ActionQueue` internals (there is no public "fire action")

### 6. Text export

`TextSystem` public surface:

- `TextSystem::new(fonts, families)` (`text.rs:286-360`), `Default` (`:225-229`).
- `atlas: Atlas` public (`text.rs:188`), `shaped` / `rebroken` public counters (`:194-196`).
- `set_font_smoothing` / `font_smoothing` (`:457`, `:482`), `set_families` / `families` (`text/families.rs:49-63`).
- `build` / shaping entry points are internal; public glyph emitters are `glyphs(text, style, scale, origin, out)` (`text/glyph_emit.rs:11-14`), `glyphs_for_layout(layout, scale, origin, bytes, out)` (`:19-28`), and `glyphs_in(run, at, scale, origin, out)` (`:104-112`).
- `glyphs_in_band(layout, origin, k, bytes, band, out)` is `pub(crate)` (`text/glyph_emit.rs:47-99`). This is the function that paints the view's text line by line.
- `glyph_cache: GlyphCache` is `pub(crate)` (`text.rs:214`). It is the 8 MiB / 4096-entry flattened quads cache (`text/glyph_cache.rs:1-41`), replayed at `:204-273`.
- `begin_frame` is public (`text.rs:505-507`); `begin_frame_pinned` is `pub(crate)` (`:509`).

Atlas:

- `ATLAS_SIZE = 2048` (`text/atlas.rs:7`).
- `AtlasPage { pub data: Vec<u8>, pub dirty: Option<(u32,u32)>, ... }` (`text/atlas.rs:105-110`).
- `Atlas { pub data: Vec<u8>, pub dirty: Option<(u32,u32)>, pub(crate) pages: Vec<AtlasPage>, ... }` (`:181-202`).
- `Atlas::page_count()` returns `1 + pages.len()`, at least 1 (`:215-218`).
- `Atlas::page_data(page)` returns `data` for page 0 or `pages[page-1].data` (`:220-223`).
- `Atlas::invalidate`, `resets`, `rasterized` (`:206-232`).
- `GlyphQuad { rect: [f32;4], uv: [f32;2], ink: u16, byte: u32, color: u32, outline: Option<Outline>, lcd: bool }` (`:128-144`), with `atlas_page()` / `atlas_uv()` helpers (`:146-154`).
- `MAX_STEADY_PAGES = 2`, `MAX_OVERFLOW_PAGES = 8` (`:47-52`). Worst case is 8 pages of 4 MiB, 32 MiB (`page_count` can reach 8; the allocator refuses a ninth at `:371-381`); normal UI is page 0 plus maybe one secondary.

How to hand text to a foreign renderer without a patch: use the instance stream. `glyph_or_image` emits an alpha glyph as `KIND_GLYPH` with `params = [0, KIND_GLYPH, page, coverage_exponent]`, `uv.xy` the atlas origin, `radii[0]` the LCD flag, and `fill` the premultiplied ink (`runtime/paint/blend.rs:57-83`, `runtime/paint/helpers.rs:287-303`). A colour glyph becomes `KIND_IMAGE` with `params[0]` the image page, `params[2]` the premultiplied flag, and `uv` the image-atlas rect (`runtime/paint/helpers.rs:293-303`). The host needs no `GlyphQuad` list to draw what Rune drew; it needs the R8 atlas page and the shader's glyph branch.

What must be patched for a standalone glyph list:

- `text/glyph_emit.rs:47` `glyphs_in_band` to `pub`.
- An accessor for the view's layout: `Node.text_layout` is `Option<Rc<Layout<Ink>>>` and private (`runtime/types.rs:99`). Add `Runtime::text_layout(&self, key: &str) -> Option<&Layout<Ink>>` or a `Runtime::glyph_quads(&mut self)` that walks the node list and emits quads with the node's origin, padding, scale, rotation, clip and scroll already applied. The latter is a new paint path; the former makes Odin reproduce the placement in `runtime/paint/content.rs:463-521`.
- `text/atlas.rs:188` for per-page dirty rows, or upload whole pages.

The practical answer is: **do not patch for glyph quads unless the Odin renderer cannot consume `KIND_GLYPH` instances.** The instance stream is already the placed, clipped, tinted glyph representation.

### 7. Time, scale, density, determinism

`Env` has exactly two fields: `system_dark: bool` and `scale: f32` (`runtime/cx.rs:5-8`). There is no separate density value. `scale` is device pixels per logical point; it also sets the `Scene` pixel scale (`runtime/frame.rs:39`, `runtime.rs:823`).

Runtime time fields:

- `t: f64` - animation time in seconds, scaled by `time_scale` (`runtime.rs:422`).
- `time_scale: f32` - `1.0` by default (`runtime.rs:428`); `step_motion` does `let step = dt * self.time_scale as f64; self.t += step` (`runtime/frame.rs:669-673`).
- `reduced_motion: bool` - `false` by default (`runtime.rs:423`); `apply` calls `scene.set_reduced_motion` (`runtime/commit/apply.rs:14-17`).
- `system_reduced_motion: bool` - `false` by default in a headless runtime (`runtime.rs:424`, `runtime/system_settings.rs:71-74`); set with `set_system_reduced_motion` (`:65-70`).
- `clock: f64` - logical clock (`runtime.rs:435`), advanced in `frame_step` (`runtime/frame.rs:407`).
- `wall_start: Option<Instant>` - if `Some`, `now_clock` reads wall time (`runtime/frame.rs:7-9`) and `frame_step` uses the wall clock instead of adding `elapsed` (`runtime/frame.rs:407`).

Deterministic capture recipe:

1. Construct `Runtime::new` or `with_text` with `wall_start = None` (the default). Do not set it.
2. Set `env.scale` and `set_viewport((w,h), scale)` once. Do not change scale mid-capture unless you want a scale test.
3. Set `time_scale` explicitly (e.g. `1.0`), `reduced_motion` explicitly (`false`), and `set_system_reduced_motion(false)`.
4. Call `rt.frame(0.0)` once before any input. The constructor sets `dirty: true` (`runtime.rs:867`), so this builds the first tree and hit list, as the headless harness does (`tooling/headless.rs:225-229`).
5. For each captured frame: enqueue events, call `rt.frame(dt)` with a fixed `dt` (e.g. `1.0/60.0`), then read `instances` / atlas. Use `dt = 0.0` for a pure commit.
6. Set `double_click_interval` and `help_delay` explicitly if the app uses presses or tooltips; headless defaults are `0.5` (`runtime.rs:799-804`).
7. Pass explicit font bytes to `TextSystem::new` or `Runtime::with_text` if the capture must be identical across machines. `TextSystem::new` uses embedded Inter but loads system CJK fallbacks (`text/system_fonts.rs:124-142`) and may discover installed families (`text.rs:429`, `text/system_fonts.rs:148-164`). Those differ by machine.
8. Avoid `ImageCache`/video/recorder in a deterministic capture unless preloaded: image decoding has a worker thread (`image.rs:164`), video has decoder threads (`video/macos.rs:447`), recorder has a worker (`recorder/macos.rs:186`). `Runtime::new` resets the virtual media clocks (`runtime.rs:824-825`), but it does not make async decoding synchronous.

One subtlety: `Runtime::frame(dt)` can run more than one `frame_step` in a single call. If a wake deadline falls inside the step, `frame_split` loops over `frame_step` at each deadline and then finishes the remainder (`runtime/frame.rs:356-370`). A single call can therefore commit zero, one, two or more times, depending on queued `wake_after`/timer state. Cropping a capture by "one call = one commit" is wrong; use `rt.stats.commits` as the counter (`runtime.rs:755`, `runtime/commit/apply.rs:54`).

### 8. Actions: handler to Odin, Odin to handler

There are two directions, and Rune only helps with one.

#### 8.1 UI to game (handler tells Odin "Resume" or "sprint toggle")

The clean way: put an app-defined queue in `S`.

```rust
struct AppState {
    sprint: bool,
    actions: Vec<GameAction>,
}
```

A handler does `s.actions.push(GameAction::Resume)` or, better for a pure toggle, mutates `s.sprint = !s.sprint` directly. The view reads `s.sprint` in the same commit, so the UI reflects it immediately. After `rt.frame(dt)` returns, the shim drains `s.actions` into a C array. This has no reentrancy, no aliasing, no unwind risk, and the order is the handler order inside the frame.

The callback-inside-handler version is possible but worse:

- The handler has `&mut S` (`el/handlers.rs:10-20`, `runtime/input/action.rs:400-405`), so it can call `extern "C" fn(ctx, action)` safely if `ctx` is a raw pointer the shim owns and the callback does not touch Rune.
- But `Runtime` is mutably borrowed by `frame_step`/`run_action` for the whole call. Any callback that calls back into the shim while the frame is active risks aliasing. Even a read like `rune_host_instances` would need `&Runtime` while `&mut Runtime` is live.
- A panic unwinding through `extern "C"` is undefined behavior. A callback that takes a long time blocks the commit and all input; a callback that calls `rt.frame` recursively corrupts the transaction.
- The callback sees `S` mid-frame, before the commit. If it pushes state back into `S`, the view may or may not see it depending on whether it runs before the final commit. That is hard to reason about.

Use queued actions for anything that can wait until after the step. Use direct `S` mutation for toggles that the view owns. Do not use a C callback for an action that only needs to reach Odin after the frame.

#### 8.2 Game to UI (Odin tells the shim "set sprint mode" or "focus Resume")

Use `Runtime::update` (`runtime/frame.rs:128-130`) or `update_if` (`:142-153`), or mutate `rt.state` directly and call `rt.invalidate()` (`:121-123`). `update` runs now, latches `Tx` requests, sets `dirty`, and the next `frame` commits it. For a command that must not be a model change, use `update_if` returning `false`; its `Tx` requests still latch (`runtime/frame.rs:131-153`).

If Odin is authoritative and the Rust view is only a projection, have Odin write the new values through `rune_host_set_*` functions before `rune_host_step`. The shim applies them to `S` and calls `invalidate`; no `Tx` needed.

Do not add a public Rune `Action` enum for this. `Action` is the internal input-dispatch vocabulary (`runtime/input/action.rs:4-66`) and `ActionQueue` is private (`:72-106`). A public `fire_action` would expose focus, drag, modal and selection internals that are only meaningful to the input pipeline.

### 9. C ABI shape

Keep the handle opaque and every crossing type POD. `Instance` already satisfies `#[repr(C)]` and is exactly 128 bytes (`render.rs:201-224`), so the instance array can cross as bytes. Everything else is defined by the shim.

```c
/* Opaque. One per runtime, owned by one thread. */
typedef struct RuneHost RuneHost;

typedef struct {
    float width, height;   /* logical points */
    float scale;           /* device pixels per point */
    uint32_t system_dark;
    uint32_t reduced_motion;
} RuneConfig;

typedef struct {
    double dt;             /* seconds; 0 for a commit-only frame */
    float width, height;   /* points; copied to set_viewport */
    float scale;
    uint32_t flags;        /* reserved, 0 */
} RuneFrame;

typedef enum {
    RUNE_EV_POINTER_MOVE = 1,
    RUNE_EV_POINTER_DOWN,
    RUNE_EV_POINTER_UP,
    RUNE_EV_POINTER_LEAVE,
    RUNE_EV_POINTER_SECONDARY_DOWN,
    RUNE_EV_POINTER_SECONDARY_UP,
    RUNE_EV_WHEEL,
    RUNE_EV_KEY_DOWN,
    RUNE_EV_KEY_UP,
    RUNE_EV_TEXT,
    RUNE_EV_IME_PREEDIT,
    RUNE_EV_IME_COMMIT,
    RUNE_EV_IME_ENABLED,
    RUNE_EV_IME_DISABLED,
    RUNE_EV_FOCUS,
    RUNE_EV_MODIFIERS,
    RUNE_EV_RESIZE,
    RUNE_EV_TOUCH
} RuneEventKind;

typedef struct {
    uint32_t kind;          /* RuneEventKind */
    uint32_t flags;         /* modifier bits, precise, phase, pressed */
    float x, y;             /* points */
    float dx, dy;           /* wheel points */
    int32_t key;            /* shim key code, not Rust Key */
    uint32_t button;        /* 0 primary, 1 secondary, 2 middle, 3 back, 4 forward */
    const uint8_t *text;    /* UTF-8, copied by push_events */
    uint32_t text_len;
    uint32_t ime_sel_start; /* byte offsets, UINT32_MAX for none */
    uint32_t ime_sel_end;
    uint64_t touch_id;
    double time;            /* touch clock, seconds */
} RuneEvent;

typedef struct {
    const uint8_t *data;    /* Instance[] or atlas bytes */
    uint64_t len;           /* bytes */
    uint64_t stride;        /* bytes per element; 0 for byte arrays */
} RuneSpan;

typedef struct {
    const uint8_t *data;    /* 2048*2048 R8 page */
    uint32_t width, height;
    uint32_t dirty_y0, dirty_y1; /* 0,0 = full upload */
} RuneAtlasPage;

typedef struct {
    uint32_t page_count;
    const RuneAtlasPage *pages;
    uint64_t resets;
} RuneAtlas;

typedef struct {
    uint32_t kind;          /* app-defined GameAction */
    uint32_t id;
    float x, y;
    int32_t i;
    double f;
} RuneAction;

typedef struct {
    uint64_t revision;
    uint64_t len;
    const uint8_t *bytes;   /* app-defined snapshot, valid until next step */
} RuneStateSnapshot;
```

Functions:

```c
RuneHost *rune_host_new(const RuneConfig *config);
void rune_host_free(RuneHost *host);

/* One frame: begin, push a batch, step, read. All on the owning thread. */
void rune_host_frame_begin(RuneHost *host, const RuneFrame *frame);
void rune_host_push_events(RuneHost *host, const RuneEvent *events, uint64_t count);
void rune_host_step(RuneHost *host);          /* calls Runtime::frame(dt) */
void rune_host_frame_end(RuneHost *host);     /* optional: invalidates spans */

/* Outputs. Pointers are valid until the next rune_host_step. */
RuneSpan rune_host_instances(const RuneHost *host);   /* RuneSpan over Instance[] */
RuneSpan rune_host_marks(const RuneHost *host);       /* uint32_t[] or empty */
RuneAtlas rune_host_atlas(const RuneHost *host);      /* glyph atlas pages */
RuneSpan rune_host_images(const RuneHost *host);      /* app-defined ImagePage[] */
RuneSpan rune_host_hits(const RuneHost *host);        /* app-defined Hit[] */
RuneSpan rune_host_elements(const RuneHost *host);    /* app-defined Element[] */
RuneStateSnapshot rune_host_state(const RuneHost *host);

/* Actions the handlers queued in S. Drained by the shim after step. */
const RuneAction *rune_host_actions(RuneHost *host, uint64_t *count);
void rune_host_actions_clear(RuneHost *host);

/* Flags and counters for the host's scheduler. */
uint32_t rune_host_animating(const RuneHost *host);
uint64_t rune_host_commits(const RuneHost *host);
uint64_t rune_host_glyphs(const RuneHost *host);
```

Rules:

- No Rust `String`, `Vec`, `Rc`, `Scene`, `Node`, `ElementInfo`, `GlyphQuad` or `SurfaceDraw` in a public signature.
- No `bool` in a C struct; use `uint32_t`. No `usize`; use `uint64_t`.
- `RuneSpan::stride` is 128 for instances, 4 for marks, 0 for a byte blob.
- Atlas pages are 4 MiB per page (`2048 * 2048`). `dirty_y0..dirty_y1` is a row range; if the shim cannot provide it, set both to 0 and document "full upload".
- The instance stream is the source of truth for the ordinary draw list. `KIND_GLYPH` page is `params[2]`; `KIND_IMAGE` page is `params[0]`; `KIND_LAYER`/`KIND_LAYER_END` are structural records that occupy indices. Do not compact or reorder them.
- If the game has no video/native surfaces, `rune_host_surfaces` can be omitted. `SurfaceDraw` is not C-safe because `NativeSurface` owns an `Arc<Mutex<...>>` (`native_surface/mod.rs:144-146`, `:341-351`).
- The shim must keep `RuneHost` on one thread. It holds `Rc` handlers and `RefCell` scratch, so it is not `Send` (see section 10).

### 10. Threading

`Runtime<S>` is not `Send` or `Sync`:

- Handlers are `Rc<dyn Fn(...)>` (`el.rs:182`, `el/handlers.rs:10-20`), and `Runtime` stores `Rc`/`Weak` in several places, e.g. `matched: Vec<(Rc<str>, NodeId)>` (`runtime.rs:496`), `hover_gone: Vec<(String, WindowFocusFn)>` (`:643`), `clipboard_reads` (`:697`).
- It contains `std::cell::RefCell` scratch, e.g. `motion_scratch` (`runtime.rs:486`) and `sel_snapshot` (`:679`).
- It uses thread-local clocks: `COMMITS` (`runtime/cx.rs:38-40`), input arrival `CURRENT`/`LAST` (`input/time.rs:7-10`), video `HEADLESS` (`video/mod.rs:91-98`).
- No `unsafe impl Send`/`Sync` exists for `Runtime` in the files read.

`Runtime::new` calls `crate::recorder::headless_reset()` and `crate::video::headless_reset()` (`runtime.rs:824-825`), both thread-local. Construct and step on the same thread.

No renderer is required for a commit. `Runtime` has no `wgpu::Device`; `frame`/`build` only touch CPU state and `TextSystem` (Parley + swash). `Renderer` is a separate object the window/headless host creates (`window/draw.rs:273-274`, `tooling/headless.rs:141-148`). A headless commit on the main thread is safe. The GPU prewarm and render threads are only started by `App`/window/overlay paths (`render/prewarm.rs:35`, `render/warm.rs:65`), not by `Runtime::frame`.

Threads that can appear if the view uses those features:

- image decode worker (`image.rs:164`)
- clipboard worker (`clipboard/native.rs:32`)
- video decoder (`video/macos.rs:447`, `:849`)
- recorder writer (`recorder/macos.rs:186`, `tooling/record.rs:222`)
- accessibility AT-SPI (native window only)
- file dialogs, tray, global shortcuts, D-Bus services (host/platform paths)

For a pure headless UI commit, none of these are started unless the view calls them. Avoid `ImageCache`, `Video`, `Recorder`, clipboard reads and native menus in the Rust view if the boundary must stay single-threaded and deterministic.

`App` must run on the main thread because it builds a winit event loop and native windows (`window/event_loop.rs:14`, `window.rs:482-512`). The headless tooling path still creates a GPU (`tooling/headless.rs:141-148`) and is not the right host for a game main loop.

## Boundary table

| Boundary item | Direction | Data shape | Size per frame | Current visibility |
|---|---|---|---|---|
| Viewport and scale | host to shim | `(f32,f32)` points + `f32` scale | 12 B | public `Runtime::set_viewport` (`runtime/frame.rs:11`) |
| Frame dt | host to shim | `f64` seconds | 8 B | public `Runtime::frame` parameter (`runtime/frame.rs:305`) |
| Pointer move/down/up/leave | host to shim | two `f32` points, button id | ~12-16 B/event | public (`runtime/input/pointer.rs:8,177,299,356`) |
| Wheel / gesture | host to shim | dx,dy, x,y, phase, mods, precise | ~32-40 B/event | public `WheelEvent` (`input/canvas_input.rs:23-39`), `wheel_event` (`runtime/input/gesture.rs:25`) |
| Key down/up/repeat | host to shim | `Key` code + `Mods` | ~16-24 B + text | public (`runtime/input/keys.rs:261,275`; `runtime/input/gesture.rs:220`) |
| Text | host to shim | UTF-8 string | text length | public `Key::Text` (`edit/keys.rs:30`) |
| IME | host to shim | preedit/commit string, cursor range | text length + 8 B | public `Ime` (`edit/ime.rs:11-22`), `Runtime::ime` (`runtime/input/keys.rs:279`) |
| Focus | host to shim | `bool` | 1 B | public `window_focus` (`runtime/frame.rs:51`) |
| Modifiers | host to shim | five `bool`s | 5 B | public `Mods` (`edit/keys.rs:9-19`), `PhysicalInput::Modifiers` (`input/physical_input.rs:5-9`) |
| Resize | host to shim | points + scale | 12 B | public `set_viewport` (`runtime/frame.rs:11`) |
| Touch | host to shim | id, phase, x,y, time | ~32 B/event | public `touch` (`runtime/input/touch.rs:69`) |
| App state / command | host to shim | app-defined POD or `update` closure | app-defined | public `Runtime::state` / `update` (`runtime.rs:391`, `runtime/frame.rs:128`) |
| State snapshot | shim to host | app-defined POD | app-defined | app-owned; `Runtime.state` public |
| Instance draw list | shim to host | `Instance[128]` | `128 * N` B | public `Runtime.instances` (`runtime.rs:469`); `Instance` is `repr(C)` (`render.rs:201-224`) |
| Marks | shim to host | `u32[N]` | `4 * N` B | public, opt-in (`runtime.rs:470-473`) |
| Glyph atlas | shim to host | 2048x2048 R8 per page | 4,194,304 B/page full; rows if dirty | public `text.atlas` (`text.rs:188`), `page_data` (`text/atlas.rs:221`); per-page dirty `pub(crate)` (`:188`) |
| Image atlas | shim to host | RGBA8 pages | `4 * w * h` B/page | public `images.pages` (`pixels.rs:240-249`) |
| Native surfaces | shim to host | `SurfaceDraw` with `Arc` | ~96 B each | public field (`runtime.rs:474`) but not C-safe (`native_surface/mod.rs:144-146,341-351`) |
| System materials | shim to host | `MaterialDraw` | ~40 B each | `pub(crate)` (`runtime.rs:476`); `MaterialDraw` `pub(crate)` (`system_material/mod.rs:29-42`) |
| Elements | shim to host | `ElementInfo` with Strings | ~300+ B + heap each; not measured | public `elements()` (`runtime/elements.rs:201`) |
| Full hit list | shim to host | `(u64 NodeId, [f32;4])` | 24 B/hit | private `hits` (`runtime.rs:480`); `hit_regions()` only overlay (`runtime/input/pointer.rs:376`) |
| Glyph quads | shim to host | `GlyphQuad` (~76 B, not `repr(C)`) | ~76 B/glyph | private path: `glyphs_in_band` `pub(crate)` (`text/glyph_emit.rs:47`), `Node.text_layout` private (`runtime/types.rs:99`) |
| Shell request | shim to host | `Shell` enum | 1-4 B | `shell_request` public (`runtime.rs:706`); minimize/window frame/title private (`:708,721,723`) |
| Actions (UI to game) | shim to host | app-defined `GameAction[]` | app-defined | no Rune API; use a queue in `S` |
| Commands (game to UI) | host to shim | app-defined setter / `update` | app-defined | public `Runtime::update` (`runtime/frame.rs:128`); direct `state` mutation plus `invalidate` |
| Animating / commits / glyphs | shim to host | `bool`, `u64`, `u64` | ~20 B | public `animating` (`runtime.rs:735`), `stats` (`:755`, `runtime/types.rs:549-554`) |

## Minimal patch list

1. **`crates/rune/src/runtime.rs:480` - expose the full hit list.**
   Add `pub fn hit_list(&self) -> Vec<Hit>` where `Hit` has `path: String` (or key), `rect: [f32;4]`, and `node: Option<u64>`. Why: `hits` is private, `hit_regions()` returns only `overlay_hits` (`runtime/input/pointer.rs:375-376`), and `ElementInfo` does not expose the actual dispatch rect list. Needed only if Odin wants to do its own picking before forwarding input; a host that forwards points to Rune does not need it.

2. **`crates/rune/src/text/glyph_emit.rs:47` - make `glyphs_in_band` public.**
   Change `pub(crate) fn glyphs_in_band` to `pub fn`. Why: it is the only function that paints a laid-out view paragraph into `GlyphQuad`s; `glyphs_for_layout` is public but the host has no layout. Pair it with a new `Runtime::text_layout(&self, key: &str) -> Option<&Layout<Ink>>` because `Node.text_layout` is private (`runtime/types.rs:99`). If the host consumes `KIND_GLYPH` instances instead, skip this patch.

3. **`crates/rune/src/text/atlas.rs:188` - expose per-page dirty rows.**
   Add `pub fn take_page_dirty(&mut self, page: usize) -> Option<(u32,u32)>` (page 0 from `self.dirty`, pages >=1 from `self.pages[page-1].dirty`), or a read plus clear pair. Why: `page_data` is public but `pages` is `pub(crate)`, so a host with more than page 0 must upload a whole 4 MiB page per frame. This is a performance patch, not a correctness one.

4. **`crates/rune/src/runtime/input/physical.rs:65` - make `physical_then` public.**
   Change `pub(crate)` to `pub`. Why: `physical_input` queues only `PhysicalInput` and loses the logical fallback key. The winit host uses `physical_then(PhysicalInput::Key { ... }, logical, key_base, unhandled)` (`window/events.rs:398-401`). A UI that supports `on_physical_input` plus text editing needs both in one action. The signature also takes `Option<Unhandled>`; `Unhandled` is only `pub(crate)` (`runtime.rs:113-114`), so either make it public or add a narrower public wrapper taking `PhysicalInput` and `Option<KeyEvent>`.

5. **`crates/rune/src/runtime.rs:708,721,723,714,695,693,702` - add accessors for remaining shell requests.**
   At minimum `take_minimize_request()`, `take_window_frame()`, `window_title()`, and `take_popup()`/`take_file_dialog()` if Odin owns those surfaces. Why: a handler can call `Tx::minimize`, `Tx::resize_window`, `Tx::set_title`, `Tx::popup_menu`, `Tx::open_file`, `Tx::paste`, `Tx::read_clipboard`, but the corresponding fields are `pub(crate)` and the requests silently stay in the runtime. `shell_request` and `copy_request` are already public (`runtime.rs:706,691`).

6. **`crates/rune/src/runtime.rs:476` - expose `materials`.**
   Make the field public or add `pub fn materials(&self) -> &[MaterialDraw]` plus make `MaterialDraw` public. Why: `El::system_material` elements produce a native/fallback material list that is not in `instances`; a host that draws its own surfaces must see them. If the game uses only the fallback fill, skip this.

7. **`crates/rune/src/text/families.rs:38` - make `TextSystem::for_window` public (optional).**
   Why: `Runtime::new` uses `TextSystem::default()`, which is Inter only (`text.rs:225-229`); `for_window` applies the process-wide chosen family slots. `TextSystem::new` is already public, so this is only for matching `App` behavior exactly.

8. **No patch for `Runtime::frame`, events, instances, scene, elements, atlas page 0, or image atlas.**
   Those are already public. Do not add an `App::step`; it would require exposing the window host's private `rt` (`window.rs:482-512`) and would drag the shim into winit and the GPU.

## Three riskiest parts

1. **The instance stream is a renderer contract, not a scene graph.** `Instance` carries only 128 bytes per quad and raw kind-specific payloads (`render.rs:201-224`, kinds `:35-100`). To get pixels, Odin must implement Rune's uber shader (`shader.wgsl`), the clip/fade packing (`render.rs:226-292`, `clip.wgsl`), the layer planner and composite (`render/layers.rs:577-760`), backdrop blur (`render/backdrop_blur.rs:338-440`), effects (`render.rs:64-74`) and the sRGB/linear encoding choice (`render/pipelines.rs:205-217`, `runtime/paint/blend.rs:127-129`). A host that draws every instance as a plain textured quad will be wrong for borders, shadows, gradients, glyph coverage, rounded clips and layers. This is the largest work item in "full parity"; the ABI is the easy part.

2. **Text is the least exportable part.** `glyphs_in_band` and the glyph cache are `pub(crate)` (`text/glyph_emit.rs:47`, `text.rs:214`), node text layouts are private (`runtime/types.rs:99`), and per-page atlas dirty rows are private (`text/atlas.rs:188`). The instance stream is enough for painting, but standalone glyph export requires the patches above. Determinism is also weaker here: `TextSystem::new` loads system CJK fallbacks (`text/system_fonts.rs:124-142`) and can discover installed families, and the atlas has multiple pages with phase-dependent masks (`text/atlas.rs:47-52`, `text/glyph_emit.rs:7`). Two machines can shape or rasterize the same string differently unless the font bytes and family list are pinned.

3. **Calling a C callback inside a handler risks reentrancy and aliasing.** `frame_step` owns `&mut Runtime`, `run_action` owns `&mut self`, and the handler gets `&mut S` (`runtime/frame.rs:472-521`, `runtime/input/action.rs:260-527`). Any callback that calls back into the shim can create a second mutable borrow of the runtime, re-enter the commit, or unwind across `extern "C"`. It also blocks the commit for as long as the game takes. A queue in `S`, drained after `frame` returns, has none of these problems; the only cost is that Odin sees the action after the step, which is normally what it wants anyway.

## Conflicts

- **`frame.rs` is not a frame loop.** It is eight lines of module declarations (`crates/rune/src/frame.rs:1-8`). The loop is `crates/rune/src/runtime/frame.rs:305-647`. Likewise `input.rs` is thirteen module declarations (`crates/rune/src/input.rs:1-13`), not the event model.
- **`desktop.rs` is not the single-window frame loop.** It is the `--desktop` multi-window compositor (`desktop.rs:1-4`, loop at `:361-495`). The single-window host is `window/draw.rs`; the headless single-window host is `tooling/headless.rs`.
- **`App::windowless()` is not headless.** It sets `open = false` and `keep_running = true` (`app.rs:353-358`) but still runs the winit event loop. Headless is selected by `Args::headless()` in `try_run` (`app.rs:598-600`).
- **`Runtime::frame(dt)` is only fully "given dt" when `wall_start` is `None`.** `now_clock` reads the wall clock when `wall_start` is `Some` (`runtime/frame.rs:7-9`), and `frame_step` uses `wall_clock().unwrap_or(clock + elapsed)` (`:407`). Motion still uses the `dt` argument (`:669-673`), but timers, poll and handler clocks do not. Set `wall_start = None` for a deterministic harness.
- **One `frame(dt)` is not always one commit.** `frame_split` can run several `frame_step` passes at timer deadlines (`runtime/frame.rs:356-370`), and `frame_step` itself can commit before routing and again at the end (`:483-496`, `:558-577`). Use `stats.commits` (`runtime/commit/apply.rs:54`) rather than counting calls.
- **`hit_regions()` is not the full hit list.** It returns only `overlay_hits`, the regions marked `El::hit` for native overlay input (`runtime/input/pointer.rs:375-376`, `runtime/input/hit.rs:240-242`). The full list is private (`runtime.rs:480`).
- **`Runtime::elements()` is public but expensive.** It clones several `String`s per element and walks ancestors (`runtime/elements.rs:216-353`, `:374-375`). It is a tooling/inspection API, not a cheap per-frame stream. The per-frame stream is `instances`.
- **`TextSystem::glyphs` is public but the view's text is not.** `glyphs` and `glyphs_for_layout` are public (`text/glyph_emit.rs:11-28`), but the laid-out view text is in private `Node.text_layout` (`runtime/types.rs:99`) and painted by `pub(crate) glyphs_in_band` (`text/glyph_emit.rs:47`). A host can shape its own text, not read Rune's.
- **`Atlas::page_data` is public but `AtlasPage.dirty` is not reachable.** `Atlas.data`/`dirty` cover page 0 (`text/atlas.rs:182-184`); pages >=1 are `pub(crate)` (`:188`). The public `page_data` gives bytes but no dirty range.
- **`Runtime` is not `Send`.** Handlers are `Rc` (`el.rs:182`) and scratch is `RefCell` (`runtime.rs:486`); there is no `unsafe impl Send`. A C API must enforce one thread rather than pretending the handle is transferable.

## Not found

- No `App::step`, `App::frame`, or public accessor from `App` to its `Runtime`. `App` owns only `run`/`try_run` (`app.rs:578-604`); the window host builds the runtime privately (`window.rs:482-512`).
- No public `Runtime::commit`, `Runtime::build`, `Runtime::step_motion`, `Runtime::frame_split` or `Runtime::frame_step`. They are `pub(super)`/`pub(crate)` (`runtime/commit.rs:79`, `runtime/paint/build.rs:5`, `runtime/frame.rs:345,384,667`).
- No public per-frame glyph-quad list, node text layout, or glyph-cache access. `glyphs_in_band` is `pub(crate)` (`text/glyph_emit.rs:47`); `Node.text_layout` is private (`runtime/types.rs:99`); `glyph_cache` is `pub(crate)` (`text.rs:214`).
- No public full hit list. `hits` is private (`runtime.rs:480`); `hit_regions()` is overlay-only (`runtime/input/pointer.rs:376`).
- No public per-page atlas dirty range. `Atlas.pages` is `pub(crate)` (`text/atlas.rs:188`); only `Atlas.dirty` for page 0 is public (`:184`).
- No public `MaterialDraw` or `Runtime.materials`. Both are `pub(crate)` (`runtime.rs:476`, `system_material/mod.rs:29-42`).
- No public `Action` / `ActionQueue` / `fire_action`. `Action` and `ActionQueue` are `pub(super)` (`runtime/input/action.rs:4-106`); the only public action-like path is synthetic input (`Runtime::key`, pointer methods, `find`) or `Runtime::update`.
- No public `physical_then`; only `physical_input` (`runtime/input/physical.rs:32,65`).
- No public batch event entry such as `step(events, dt)`. Events are queued one public method at a time, then `frame(dt)`.
- No `#[repr(C)]` on `ElementInfo`, `GlyphQuad`, `SurfaceDraw`, `MaterialDraw`, `FrameStats`, or the event/handler types. Only `Instance` is `#[repr(C)]` and size-asserted (`render.rs:201-224`).
- No `unsafe impl Send`/`Sync` for `Runtime`, and no thread-safe runtime API. `Runtime` is thread-bound by `Rc`/`RefCell`/thread-locals.
- No exact measured size for `ElementInfo`, `GlyphQuad`, `SurfaceDraw` or `MaterialDraw`. The table uses field counts/approximations; I did not compile a size probe.
- No measurement of the owner's actual instance count, atlas page count, or per-frame `elements()` cost. The note gives formulas, not numbers from a run.
- No read of the platform window backends (macOS/Windows/X11/Wayland), the text shaping/fallback internals, `rune-taffy`, or `rune-motion` internals beyond the public `Scene` API. No tests were read as evidence. README/PLAN were deliberately not used as evidence of behavior.

## References

### Frame, app, and hosts

- `crates/rune/src/app.rs:353-358` - `windowless()` sets `open=false`, `keep_running=true`.
- `crates/rune/src/app.rs:578-604` - `run` / `try_run`; headless branch at `598-600`.
- `crates/rune/src/app.rs:532-535` - `on_frame_drawn` receives `&Runtime<S>` after a Drawn frame.
- `crates/rune/src/runtime.rs:390-814` - `Runtime<S>` fields and visibilities.
- `crates/rune/src/runtime.rs:817-823` - `Runtime::new` / `with_text`.
- `crates/rune/src/runtime/frame.rs:305-307` - public `frame(dt)`.
- `crates/rune/src/runtime/frame.rs:345-371` - `frame_split`, timer splitting.
- `crates/rune/src/runtime/frame.rs:384-647` - `frame_step`: clock, poll, queue, commit, scroll, motion.
- `crates/rune/src/runtime/frame.rs:667-758` - `step_motion`, `Scene::frame`, `build`.
- `crates/rune/src/runtime/frame.rs:128-153` - `update` / `update_if`.
- `crates/rune/src/runtime/frame.rs:11-44` - viewport and scale.
- `crates/rune/src/frame/clock.rs:44-53` - window frame `split` rule.
- `crates/rune/src/window/draw.rs:211` - `FrameClock::advance`.
- `crates/rune/src/window/draw.rs:273-283` - renderer prepare/draw/present.
- `crates/rune/src/tooling/headless.rs:225-229` - first frame before t=0 input.
- `crates/rune/src/tooling/headless.rs:311-313` - headless `rt.frame(step)`.
- `crates/rune/src/tooling.rs:135-150` - `runtime_for` (private helper).
- `crates/rune/src/desktop.rs:361-495` - `--desktop` per-frame loop.
- `crates/rune/src/desktop/window.rs:312` - `Member::advance` calls `rt.frame(dt)`.

### Commit, layout, paint

- `crates/rune/src/runtime/commit.rs:79-116` - `commit`.
- `crates/rune/src/runtime/commit/relayout.rs:76` - `measure_commit`.
- `crates/rune/src/runtime/commit/measure.rs:29-31` - `measure`; `:152` - `build_tree`.
- `crates/rune/src/runtime/commit/text_layout.rs:331` - `compute_layout`.
- `crates/rune/src/runtime/commit/apply.rs:7-916` - `apply`; `:54` - `stats.commits`.
- `crates/rune/src/runtime/paint/build.rs:5-36` - `build` clears instances/marks/hits/surfaces/materials.
- `crates/rune/src/runtime/paint/build.rs:1280` - `stats.glyphs`.
- `crates/rune/src/runtime/elements.rs:201-377` - `elements()` and its cost.
- `crates/rune/src/runtime/elements.rs:385-516` - `find`, `presented`, `element_at`, `presented_pose`.
- `crates/rune/src/runtime.rs:469-481` - instances, marks, surfaces, materials, hits.
- `crates/rune/src/render.rs:201-224` - `Instance` layout, 128-byte assertion.
- `crates/rune/src/render.rs:35-100` - `KIND_*` semantics.

### Input and events

- `crates/rune/src/edit/keys.rs:9-19` - `Mods`.
- `crates/rune/src/edit/keys.rs:26-77` - `Key`.
- `crates/rune/src/edit/keys.rs:116-119` - `KeyEvent`.
- `crates/rune/src/edit/ime.rs:11-22` - `Ime`.
- `crates/rune/src/input/canvas_input.rs:23-39` - `WheelEvent`.
- `crates/rune/src/input/canvas_input.rs:89-102` - `PointerButton`.
- `crates/rune/src/input/physical_input.rs:5-9` - `PhysicalInput`.
- `crates/rune/src/runtime/input/pointer.rs:8,13-62,177-354,356-376` - pointer entry points and queueing.
- `crates/rune/src/runtime/input/keys.rs:261-291` - key/repeat/ime/paste queueing.
- `crates/rune/src/runtime/input/gesture.rs:25-38,179-228` - wheel, buttons, key up.
- `crates/rune/src/runtime/input/secondary.rs:27-54` - secondary press.
- `crates/rune/src/runtime/input/touch.rs:15-21,69-75` - touch.
- `crates/rune/src/runtime/scroll/x.rs:114-120,141-143,188-212` - wheel delta conversion and phases.
- `crates/rune/src/window/events.rs:387-527` - winit host maps key/IME/wheel/pointer.
- `crates/rune/src/window/events.rs:454-455` - physical pixels to points.
- `crates/rune/src/runtime/input/action.rs:4-106,260-527` - internal `Action`/`ActionQueue` and dispatch.
- `crates/rune/src/runtime/input/hit.rs:209-243` - `hits` registration.

### State, handlers, Tx

- `crates/rune/src/states.rs:8-58` - `States`, downcast.
- `crates/rune/src/el/handlers.rs:10-20` - `on_press_tx` stores `Rc`.
- `crates/rune/src/el.rs:182` - `PressFn = Rc<dyn Fn(...)>`.
- `crates/rune/src/el/tx.rs:16-118,157-554` - `Tx` fields and public methods.
- `crates/rune/src/runtime/types.rs:89-110` - `Node`, `text`, `text_layout`.
- `crates/rune/src/tooling.rs:23` - `AppSpec::view` function pointer.

### Text and atlas

- `crates/rune/src/text.rs:148-223` - `TextSystem` fields, public `atlas`, private `glyph_cache`.
- `crates/rune/src/text.rs:286-360` - `TextSystem::new`.
- `crates/rune/src/text.rs:505-509` - `begin_frame` / `begin_frame_pinned`.
- `crates/rune/src/text/glyph_emit.rs:11-99` - public `glyphs`, `glyphs_for_layout`; `pub(crate)` `glyphs_in_band`.
- `crates/rune/src/text/glyph_cache.rs:1-41,204-273` - glyph cache.
- `crates/rune/src/text/atlas.rs:7,47-52` - `ATLAS_SIZE`, page budgets.
- `crates/rune/src/text/atlas.rs:105-110` - `AtlasPage`.
- `crates/rune/src/text/atlas.rs:128-154` - `GlyphQuad`.
- `crates/rune/src/text/atlas.rs:181-232` - `Atlas`, `page_count`, `page_data`, dirty.
- `crates/rune/src/runtime/paint/blend.rs:52-83` - glyph UV/page and instance packing.
- `crates/rune/src/runtime/paint/helpers.rs:287-303` - color glyph becomes `KIND_IMAGE`.
- `crates/rune/src/pixels.rs:216-249` - `ImagePage` / `ImageAtlas`.
- `crates/rune/src/runtime/cx.rs:5-15` - `Env`.

### Scene and motion

- `crates/rune-motion/src/scene.rs:307-327` - `Scene` fields.
- `crates/rune-motion/src/scene.rs:378-460` - store/time/presented/rest/world.
- `crates/rune-motion/src/scene.rs:675-789` - `frame`, `present`.

### Threading

- `crates/rune/src/runtime.rs:486,496,643,679,697` - `Rc`/`RefCell`/`Weak` in `Runtime`.
- `crates/rune/src/runtime.rs:824-825` - recorder/video headless resets.
- `crates/rune/src/input/time.rs:7-10` - thread-local input clock.
- `crates/rune/src/runtime/cx.rs:38-40` - thread-local `COMMITS`.
- `crates/rune/src/video/mod.rs:91-98` - thread-local video clock.
- `crates/rune/src/image.rs:164` - image worker thread.
- `crates/rune/src/clipboard/native.rs:32` - clipboard worker.
- `crates/rune/src/video/macos.rs:447,849` - video decoder threads.
- `crates/rune/src/recorder/macos.rs:186` - recorder thread.
- `crates/rune/src/render/prewarm.rs:35`, `render/warm.rs:65` - GPU warm threads.
- `crates/rune/src/window/event_loop.rs:14` - winit run entry (main thread).

## Companion note

`docs/research/rune-paint-contract.md` in this repository covers the shader, layer, backdrop-blur and atlas contract in more depth. It is a companion, not evidence for this note; every claim above cites Rune code directly.
