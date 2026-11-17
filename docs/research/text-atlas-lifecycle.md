# Why live HUD text is lost across a target re-attach

Date: 2026-11-14
Status: answered
Scope: repository at ddf6585; vendored Rune at that commit; parley 0.12.0 (Cargo.lock).

## Answer

The mechanism is confirmed: **the CPU atlas is intact, the new GPU atlas is
empty, and only glyphs rasterized after the attach are uploaded.** `Host::attach`
installs a fresh `Renderer` on every call
(`ui/shim/src/host.rs:310`) while keeping the runtime and its text atlas
(`host.rs:317-334`). A new renderer starts with a zero-filled 2048² `R8Unorm`
atlas (`vendor/rune/crates/rune/src/render/fill.rs:130-144`) and empty upload
state. `Renderer::prepare` sends only `atlas.dirty.take()` rows
(`render/upload.rs:211-214`), plus lazily created page textures (`:218-229`). A
glyph already in `atlas.map` is a cache hit and never reaches `Atlas::put`, the
only other writer of `dirty` (`text/glyph_emit.rs:139-146`;
`text/atlas.rs:384-413`). Nothing marks the rows of glyphs placed before the
resize, so they never reach the new texture.

`Atlas::invalidate` is the missing call. It marks every row of every page dirty,
clears `resident_caches`, and invalidates the outline store
(`text/atlas.rs:204-213`). Rune calls it exactly where the GPU side is replaced:
a recreated outline atlas (`render/upload.rs:203-208`), a fresh overlay renderer
(`overlay/surface.rs:119-123`), a dropped GPU (`window/lifecycle.rs:398-402`).
A format switch keeps the renderer and atlases (`window.rs:709-716`).

**Fix.** Keep the renderer when the device is unchanged: replace
`host.renderer = Some(Renderer::new(..))` with
`renderer.set_format(&host.device, format)` on the existing renderer; construct
one only when `host.renderer` is `None`. If a new `Renderer` is ever made while
a runtime exists, immediately call `runtime.text.atlas.invalidate()` and
`runtime.images.invalidate()`. Also delete `runtime.env.scale = scale` before
`set_viewport` (`host.rs:320-321`): it makes `change_viewport` observe no change,
so `relayout` stays false and `scene.set_pixel_scale` is skipped
(`runtime/frame.rs:28-41`); `set_viewport` sets `env.scale` itself.

**Invariant.** The renderer's atlas is a dirty-row mirror of the runtime `Atlas`.
A GPU owner may only be replaced together with `Atlas::invalidate` (and the image
atlas), because a CPU atlas cannot re-send a row that is not dirty.

## Evidence

Shorthand: `vendor/rune/crates/rune/src/`.

- The renderer is recreated on every attach, the runtime is not: `ui/shim/src/host.rs:310`, `:317-334`.
- `prepare` uploads only dirty rows; `put` is the only other dirty writer: `render/upload.rs:211-214`, `text/atlas.rs:384-413`.
- A resident glyph takes the cache-hit path and is only touched: `text/glyph_emit.rs:139-146`.
- `invalidate` re-seeds every row and the outline store: `text/atlas.rs:204-213`; GPU-filled masks re-queue on the row upload (`text/atlas_fill.rs:59-63`).
- Rune's own replacement sites invalidate: `render/upload.rs:203-208`, `overlay/surface.rs:119-123`, `window/lifecycle.rs:398-402`.
- The harness never re-attaches: `ui_attach_target` is called only from init (`src/renderer/renderer.odin:156`) and swapchain recreation (`swapchain.odin:208`); the offscreen target has no resize path (`target.odin:55-77`); `size` pins the extent for the whole run (`docs/agents/harness.md:114-115`).
- Scale is `clamp(height/720, 1, 2)` (`src/renderer/ui_step.odin:15`, `ui_bridge.odin:183`); parley resolves font size as `size * scale` (`parley-0.12.0/src/resolve/mod.rs:184`), and every rebuild lays all text out at `env.scale` (`runtime/commit/relayout.rs:230-266`).

## Conflicts

- Observation says the loss persists at 1920x1080 → 2560x1440. The code says the
  next rebuild re-lays out all text at scale 2.0 and rasterizes every glyph
  (`relayout.rs:230-266`), so the loss should last one frame. Resolution: fix
  both defects, then run the repro at 1440p → 2160p (both clamp to 2.0), where
  no re-shape can mask the empty atlas.

## Repro design

1. The `resize` command recreates the offscreen target: wait idle, destroy the
   colour image, views, and readback, create at the new extent, rebuild frame
   targets and TAA history, then call `ui_attach_target`
   (`src/renderer/recreate.odin`).
2. `scenarios/harness-resize.json`: `size` 1280x720, capture `text-1280`,
   `resize` 1200x700, capture `text-1200`, `resize` 800x600, capture `text-800`,
   then back to 1280x720. Every extent clamps to UI scale 1.0, so no relayout
   can hide an empty atlas.
3. A `stats` capture with `coverage.lit` over the status-panel region and
   `require.lit_fraction_min` fails the run when the region goes dark. Reverting
   the renderer reuse in `ui/shim/src/host.rs` collapses the fraction to 0.
4. Determinism: one image, one readback, one step, no TAA carry.

## Fast live check

Resize between two sizes in the same clamp band (1280x720 and 1024x768). If all
HUD text vanishes and stays gone, the atlas is empty. Then change Type weight in
the inspector Debug section, which changes every glyph key: if the HUD returns,
the CPU atlas was fine and only re-rasterization could upload.

## Not found

- The exact path that makes the 1080p → 1440p loss persist: checked `host.rs`,
  `state.rs`, `ui_step.odin`, `frames.odin`, `relayout.rs`; none freezes glyph
  keys after a rebuild.
- A shim ABI exposing atlas counters (`rasterized`, `page_count`, `dirty`):
  `text/atlas.rs:216-237` has them; no binding exists.

## Resolution (HARB-374)

The missing path is the pre-assigned `runtime.env.scale` in `Host::attach`. A
1080p → 1440p resize keeps the viewport in points at 1280x720, so
`change_viewport` saw an equal viewport and an already-equal scale: it returned
false, and neither `scene.set_pixel_scale` nor `relayout` ran. Every glyph key
survived, the new atlas received no rasterization, and the loss was permanent
rather than one frame.

Both causes are fixed together: `attach` reuses the renderer and calls
`set_format` when the format changed, so the GPU atlas outlives the resize, and
the viewport scale lives only in `Runtime::env.scale`, which the draw reads.

Live check sequence: the window starts borderless at 2560x1440 (scale 2.0), then
resizes to 1280x720 (scale 1.0, the same 1280x720 viewport in points), then to
1024x600 (scale 1.0, same-scale). Before the fix the panel text is already gone
at 1280x720 and stays gone through the same-scale step. After the fix it
survives both steps.

## References

- `ui/shim/src/host.rs`, `paint.rs`; `src/renderer/ui_step.odin`, `ui_bridge.odin`,
  `swapchain.odin`, `frames.odin`.
- Rune: `text/atlas.rs`, `render/upload.rs`, `runtime/frame.rs`.
