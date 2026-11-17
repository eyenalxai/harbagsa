# How should the agent harness drive input through the real call stack?

Date: 2026-11-14
Status: answered; implemented in HARB-375 (the appframe path, raw event and resize commands, and the offscreen recreation)
Commit: `ddf6585e4ab8c23b0a99b92846886d388349ab8c`; Rune submodule `f18ead891aba2437674cd8c54e238287cceb8b3a`

## Answer

**One raw-event value, one frame path.** Make `platform.Events` (`src/platform/input.odin:41`) the only input a frame sees, and extract the live loop (`main.odin:108-237`) into one shared proc, proposed `src/appframe/app_frame.odin`. It runs: drain events, `renderer.notify_resize` on `events.resized`, `game.focus` + `input.resolve`, `apply_frame_input` (root `app_loop.odin:26`), `frame.runtime_step`, `frame.runtime_compose` with `build_ui_events`, `frame.draw`, then one `uiaction.apply` pass. Live and harness differ only in event source and window/cursor side effects; neither may call Rune or the menu directly. Move root `ui_events.odin` into that package (`package main` is not importable) and pass the ownership result to the batch builder.

**Ownership is part of the seam.** `input.resolve` (`src/input/resolve.odin:13`) returns only `Frame_Input`; keys reach Rune unconditionally (`ui_events.odin:52-63`). Add a per-key route (`Game` or `UI`) to its result and have `build_ui_events(events, route, buffer)` drop game-owned keys, as pointer events are already dropped (`ui_events.odin:27-50`). Invariant: one raw event has exactly one actor per frame.

**Escape bug.** Escape with the menu closed sets `view.menu_toggle` (`resolve.odin:104-109`), which opens the menu (`app_loop.odin:34-44`) before compose; the same key is still in the batch, so the now-open dialog's modal dismiss (`ui/shim/src/settings.rs:34-36`; Rune `vendor/rune/crates/rune/src/runtime/input/focus.rs:407-414`) emits `Close_Menu` (`src/uiaction/ui_action.odin:29-34`). One frame opens and closes it. The harness cannot reproduce this: `ui` has no key form and calls the shim directly (`src/harness/ui_execute.odin:18-37`; `src/renderer/ui_bridge.odin:18-24`; `ui/shim/src/input.rs:68-150`), and each draw passes no `ui_events` (`src/harness/backend.odin:202-216`).

**Resize text bug.** `Host::attach` replaces the wgpu `Renderer` but keeps the runtime text atlas (`ui/shim/src/host.rs:307-334`). The new renderer has a blank atlas; `Renderer::prepare` uploads only `atlas.dirty` rows (`vendor/rune/crates/rune/src/render/upload.rs:211-226`), and a cached glyph adds no dirty row (`vendor/rune/crates/rune/src/text/atlas.rs:386-408`). If `ui_step`'s `clamp(height/720,1,2)` scale is unchanged (`src/renderer/ui_step.odin:11-34`), glyph keys are unchanged, nothing rasterizes, and text samples blank. A scale-changing resize re-rasterizes and can hide it. Invariant: reuse the renderer when the format is unchanged, or call `runtime.text.atlas.invalidate()` (`vendor/rune/crates/rune/src/text/atlas.rs:206-209`) whenever a new one is attached.

**Offscreen resize.** No offscreen path exists: `notify_resize` marks only `.Swapchain` (`src/renderer/renderer.odin:253-257`), `begin_frame` calls swapchain-only `recreate_swapchain` (`src/renderer/frames.odin:111-119`, `src/renderer/swapchain.odin:160-213`), and `Headless` size is fixed (`src/platform/headless.odin:13-29`). Rename it `recreate_target`, dispatch on `target.kind`, recreate the offscreen colour image, frame targets, TAA, then `ui_attach_target`; give `Headless` a setter that `pixel_size` reads. `resize` sets it and queues `events.resized`, so the live sequence — `ui_step` using the old extent that frame, then reattach — is preserved.

**Determinism.** Harness runs `present: false`, `.Offscreen`, no SDL init or OS poll. `Session` owns `pending_events`; one command drains one raw frame at zero fixed steps, `step` runs frames at one fixed step each. Use `game.SIMULATION_STEP` and `frame.Options.delta_seconds`, never wall time. `frame.fixed_step` must stop hardcoding `motion.captured = true` (`src/frame/runtime.odin:31-38`) and take the raw frame's captured fact (`resolve.odin:61-68`). Queue overflow must fail the command; today it logs and drops (`src/platform/input.odin:203-209`).

**Gamepad.** No gamepad code exists (`docs/adr/0002-sdl3-platform-and-raw-vulkan.md:3` defers it). Add SDL-free `platform.Gamepad_Button`, `Gamepad_Axis`, and `Gamepad_Event` fields to `Events`, collapse held sticks into movement/look fields, and map buttons in `resolve`. The harness `event` command fills the same queue. Rune gets a UI key only through `build_ui_events` when the route says UI.

**Commands.** Add `event`: key (`down`/`up`/`repeat`, mods), pointer (`move`/`down`/`up`, button, view points), wheel, focus (with `captured`), and gamepad forms; one frame, post-frame state. Add `resize` (`size: "WIDTHxHEIGHT"`). Rebuild `ui` click/drag/wheel/focus as recipes over `event`; keep `ui_element_center` as the only read query. Delete the shim's `click_point`/`drag_point`/`wheel_point`/`focus` exports. Register both rows in `src/harness/command_registry.odin:37`.

**Assertions.** Add `state.input` (resolved snapshot/look/motion/actions/view intents plus each raw event's route), `state.ui.events`, `state.ui.viewport`/`scale`, and `state.renderer.extent`/`ui_scale`. They join `state_sections.odin:12-40` and `state_schema.odin`. `state.ui.actions` becomes the last frame's actions (`ui_state.odin:98-139`). Add `event.expect_no_action`; add capture `require` thresholds (`lit_fraction_min`, `zero_fraction_max`), since stats report coverage but never fail (`capture_stats.odin:20-43`).

**Regression scenarios.** `ui-escape-ownership.json`: open the dialog with `event` Escape, assert `menu.open` true and no `Close_Menu`; then `menu open:true`, one Escape, assert one close; then editor palette plus Escape, assert one owner. `ui-resize-text.json`: at 1280x720 settle text, assert a label region's `lit_fraction`; resize to same-scale 1200x700, frame, assert extent/scale and `lit_fraction`; resize back. The menu rejects `step` (`src/harness/session.odin:196-198`), so the event frame runs at zero fixed steps. Add the scenarios and update `docs/agents/harness.md` in the same change; there is no CI or test gate.

## Evidence

- Live order: `main.odin:110-124,165-198`; menu toggle `app_loop.odin:34-44`; key batch `ui_events.odin:52-63`.
- Harness bypass: `src/harness/ui_execute.odin:18-37,42-62`; `src/renderer/ui_bridge.odin:18-24,179-201`; `ui/shim/src/input.rs:21-66`; batch in `package main` `ui_events.odin:1`; no events `src/harness/backend.odin:202-216`.
- Resize: `src/renderer/renderer.odin:253-257`; `src/renderer/frames.odin:111-119`; `src/renderer/swapchain.odin:160-213`; `src/platform/headless.odin:13-29`; `src/renderer/offscreen.odin:10-51`.
- Reattach/atlas: `ui/shim/src/host.rs:307-334`; `vendor/rune/crates/rune/src/render/upload.rs:211-226`; `vendor/rune/crates/rune/src/text/atlas.rs:206-209,386-408`; Rune `vendor/rune/crates/rune/src/runtime/frame.rs:28-44`.

## Conflicts

- `docs/agents/harness.md:260-262` says harness clicks and keys share the live batch. It does not: `ui_execute.odin` calls the shim directly and has no key form. The seam follows the docs.
- `docs/agents/harness.md:225-228` says live wheel is negated and scaled by 40 points. The batch does that (`ui/shim/src/input.rs:38-41`), but harness `ui_wheel_at` calls `wheel_xy` with raw values.
- `resolve.odin:28-32` says Rune owns the open dialog's keys, implying the game does not; the live batch still forwards Escape after the game opens it, so one press changes both.

## Not found

- Gamepad/joystick: none in `src/` or `ui/shim/src/`; ADR 0002 names SDL3.
- Offscreen resize: checked `notify_resize`, `recreate_swapchain`, `Headless`; no path.
- Harness key/focus commands or resolver-state report: none in `COMMANDS`, `ui_command.odin`, `state_sections.odin`.
- Capture pass/fail thresholds: none in `capture`, `capture_stats`, `ui_execute`.
- Resize cause: not run; source-level only.

## References

- `src/platform/input.odin`, `src/input/resolve.odin`, `src/frame/runtime.odin`: event value, resolver, step seam.
- `src/harness/backend.odin`, `ui_execute.odin`, `command_registry.odin`: bypass and command table.
- `src/renderer/ui_step.odin`, `frames.odin`, `swapchain.odin`: frame/UI order and target recreation.
- `ui/shim/src/host.rs`, `input.rs`, Rune `vendor/rune/crates/rune/src/render/upload.rs`: renderer/atlas ownership.
