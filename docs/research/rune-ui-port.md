# Porting Rune's UI ideas into the Odin overlay

Date: 2026-11-10
Status: superseded. Rune is the UI layer; this note records the rejected porting
route.

**Superseded:** HARB-342 chose to run Rune in-process as the UI layer, and the
shim in `ui/shim` implements it. This note predates that decision. It is kept as
a record of the porting analysis, not as guidance; use
`docs/research/rune-integration-plan.md` and `docs/ui/README.md` instead.

Source read: Rune checkout at `~/Projects/other/rune`, commit `f18ead8`
(2026-11-10), crate `rune 0.0.1`. Rune is pre-release; a later commit may move
these files. Claims about behaviour below come from the code. `docs/` is cited
as intent, never as authority.

## Answer

Rune is a general-purpose UI framework: 293k lines of Rust, of which 193k are
the `rune` crate. The overlay here is 598 lines of pure layout in `src/ui` and
about 2,700 lines of theme, text, and drawing in `src/renderer`. Almost all of
Rune's value sits in machinery this engine does not need: a retained node list,
Taffy, wgpu, Parley, AccessKit.

Three ideas survive the size difference. Only the first is worth doing for its
own sake today.

| Idea | Payoff here | Cost | Lands in |
| --- | --- | --- | --- |
| Cache shaped runs, and shape once per string per frame | Real: removes 2–3 HarfBuzz passes per label | ~120 lines | `src/renderer/text.odin` |
| One labeled rect list per frame, used for picking and for the harness dump | Grows into the missing pointer and review story | ~150–250 lines | `src/renderer/overlay.odin`, `cmd/harbagsa-agent` |
| Closed-form spring for UI motion | Only when the overlay gains motion | ~100 lines | `src/ui`, not `src/game` |

Everything else in Rune is a net loss at this size. The section **Rejected**
says why for each subsystem.

The three are ideas. The rejected items are subsystems, and a subsystem costs
more than its own lines: it brings preconditions this engine does not have. A
retained tree needs a path-keyed id map, per-node state, and a mount/update
teardown pass. Taffy needs CSS sizing semantics. A widget text stack needs its
own rasterizer. Each one turns a value (`ui.Row`, a `Rect`, a shaped run) into a
node that has to be mounted and diffed. The loss lands at every call site in
`src/game` and `src/renderer`, not in the port.

The trade reverses when the overlay becomes a general UI: scrolling lists, text
input, windows, or enough interactive components that every surface needs a
stable id and per-surface state. Then the preconditions are worth building and
the subsystem ports start to pay.

## What Rune actually is

The README reads like SwiftUI. The runtime is not.

- A view is ordinary code that returns a fresh `El` tree
  (`crates/rune/src/el.rs:553-577`, constructors at `el.rs:604-632`).
- The runtime flattens that tree into a retained `Vec<Node>`. Identity is a key
  path (`parent/key`), interned to a `NodeId` that survives across frames:
  `runtime/commit/flatten.rs:53-88`, `flatten.rs:116-150`.
- Old and new node lists are compared field by field, and visual changes are
  retargeted as property tracks: `runtime/commit/apply.rs:7-120`.
- There is no element-type diff and no hooks. Handlers downcast to `&mut S`:
  `el/handlers.rs:4-17`. Element-local history has to live in the app state.
- Hover and press do not rerun the view. They retarget `P_HOVER` / `P_PRESS` on
  the retained node: `runtime/input/hover.rs:286-383`.
- Layout runs at the target state; animation moves the box afterward, so text
  never reflows while a box springs: `runtime/commit/apply.rs:500-520`.

That last point is the one that matches this engine. `src/ui/*_layout.odin`
takes a `ui.Text_Metrics` adapter and returns rects; the renderer draws those
rects. Rune gets the same separation from `compute_layout` plus a text-measure
closure (`runtime/commit/text_layout.rs:331-377`), with a CSS solver and a
retained store behind it. Nothing about the overlay's architecture needs to
change.

## 1. Shape once, not three times

**Idea.** Shape a string once and keep the result keyed by content and style.
Re-break only when the break width changes; replays skip the shaper entirely.

**Rune.** `text.rs:540-626` keys a layout by
`(text, spans, style, scale, wrap, pills, base direction)` for shaping and
`(shape key, width, align, blocks)` for line breaking. A width change re-breaks
the newest shaped layout instead of reshaping. Two budgets bound it: 3 MiB of
stale layouts (`text/layout_cache.rs:21-46`) and 8 MiB / 4096 entries of
flattened glyph placements (`text/glyph_cache.rs:1-40`).

**This engine.** A row is shaped more than once every frame:

- `ui.rows_layout` measures every label and every value:
  `src/ui/layout.odin:136-167`.
- `rows_emit` then calls `text_emit`, which shapes the same string again:
  `src/renderer/hud_rows.odin:106`, `src/renderer/text.odin:142`.
- A right-aligned value is shaped three times, because
  `text_emit_aligned` measures and then emits: `src/renderer/text.odin:188-192`.

`text_shape` allocates nothing, but it clears and refills a HarfBuzz buffer and
writes a 1.5 KiB `Text_Run` on the stack for every call
(`src/renderer/text_shaper.odin:120-193`). Labels are static, so the hit rate
would be near total after the first frame.

**Cost.** Key on the string bytes plus `face`, weight key, pixel size,
`tracking`, and `caps`, which is every input `text_shape` reads
(`text_shaper.odin:116-193`). Store the run (glyphs, pen x, width) beside
`Text_Shaper` in `Text_Atlas`, where shaping already lives. Roughly 1.5 KiB per
distinct string; a hundred strings is 150 KiB. Add a miss counter so a cache
that stops paying is visible instead of guessed at.

The win is not a frame-time number this survey measured. It is that one
function would own shaping: `text_measure` and `text_emit` both become cache
reads, and a label cannot be measured at one width and drawn at another.

**Verdict.** Port. It is the only place Rune is clearly better than this
engine at something the engine already does.

## 2. A labeled rect list, built while drawing

**Idea.** During paint, push `(id, rect)` for everything interactive, clipped by
its ancestors. Picking walks that list in reverse paint order and takes the
topmost hit. The list is also the natural thing to dump for inspection.

**Rune.** `runtime/paint/build.rs:1249` registers a hit while painting, implemented
at `runtime/input/hit.rs:209`; `runtime/input/hit.rs:139-160` walks the list in
reverse. Press captures the target path and fires only if the pointer stays
inside (`runtime/input/pointer.rs:177-300`). The retained tree that produces
those hits also feeds the headless `--tree` dump (`tooling/trace.rs:293-360`).

**This engine.** There is no list. Two controls recompute layout and hit test
by hand: `ui.slider_hit` from `menu_input.odin:18` and the palette card test at
`hud_palette.odin:284`. Both read the same layout the draw read, which is the
important half of Rune's rule, but each new control repeats the lookup.

More importantly, the harness cannot see the overlay at all. `Scene` serializes
camera, objects, settings, and view flags (`src/frame/scene.odin:74`), and a UI
change is reviewed as a PNG diff. A row rename or a value that overflows its
fixed field is a few pixels in an image. Rune's `--tree` dump carries `path`,
`role`, `rect`, `text`, `label`, and `selected` per element
(`tooling/trace.rs:296-330`), which is what makes its harness able to review a
layout without looking at one.

**Cost.** Add `Rect_Entry { kind, index, rect }` to `Overlay`, cleared in
`prepare_overlay`, pushed by `build_hud` for rows, slider, palette cells, and
the selected band. A reverse scan is the pick. Serialize the list after a
capture so `report.json` carries the overlay's geometry without a renderer
round trip. That is one list serving pick, dump, a future hover, and a scenario
that clicks `menu.row:Type weight` instead of a pixel.

**Verdict.** Port the pattern when a third pointer target appears, not as a
framework. It pays twice: picking stops duplicating geometry, and the harness
gains a semantic view of the overlay, which is worth more than the pixels.

## 3. A closed-form spring

**Idea.** Springs are parametric, not integrated. `Spring(duration, bounce)`
maps to `ω = 2π / duration`, `ζ = 1 - bounce`. `sample(t)` evaluates the closed
form for under-, critical-, and over-damping, so a retarget can keep exact
position and velocity. `rune-motion` has no required dependencies
(`crates/rune-motion/Cargo.toml`).

**Rune.** `rune-motion/src/spring.rs:20-110` (`new`, `sample`, `settling_duration`),
`layer.rs:79-200` (`spring_unbounded`, `sample`), `gesture.rs:14-120`
(least-squares velocity over the last 100 ms, rubber band, projection).

**This engine.** UI motion and world motion are separate systems here. The
overlay draws no transition today: `src/ui` and the `hud*` files contain no
easing, spring, or interpolation. The world smooths body yaw at
`src/game/player.odin:182` and step offset at `src/game/step.odin:208` with an
exponential filter. That filter is frame-rate independent and never overshoots,
but it drops velocity at a retarget. A critically damped spring has both
properties and keeps the velocity, which matters when a value is caught
mid-move.

**Verdict.** Port it when the overlay gains motion. Nothing in the overlay moves
today, so the port has no consumer. The spring is not competing with the world
filter, and adding it would not touch `src/game`.

## Rejected

| Subsystem | Why not | Size |
| --- | --- | --- |
| `El` tree, `memo`, flatten reuse | Needs `Rc<dyn Fn>`, path ids, and a retained node list. Replacing the 1,158 lines that build the menu, HUD, and palette with a diffing runtime is the wrong direction. | 8,994 lines `el.rs` + `el/`, ~8k `runtime/commit`, 1.2k `memo` |
| `rune-taffy` | Flex/grid/block semantics for a fixed row panel. The pure layout here is smaller and directly testable without a renderer. | 4,455 lines + `taffy 0.15` (`rune-taffy/src/store.rs`) |
| Parley + swash + font fallback | FreeType and HarfBuzz already shape every string at the device pixel size, and ADR 0007 chose coverage over a distance field for a measured reason. Port the caches, not the stack. | 12,874 lines (`text.rs`, `text/`); `parley 0.12`, `swash 0.2` (`crates/rune/Cargo.toml:77-78`) |
| AccessKit tree | No assistive client for a game overlay, and the platform adapters are the bulk. | 2,244 lines (`a11y/`) |
| Layers, blur, shadows, effect slots | The overlay emits flat axis-aligned rects and one atlas-sampled text quad (`src/renderer/shaders/hud.frag`). No current component asks for a rounded edge, a shadow, or an offscreen layer. | 782 (`render/layers.rs`) + 447 (`render/backdrop_blur.rs`) |
| Virtual lists, growth rows, scroll physics, text selection | No long lists, no scrolling, no selectable text in the overlay. | several thousand lines |
| Native shell, titlebar menus, IME, file dialogs, clipboard, drag-out | The engine owns the window and input. | OS-specific, large |
| `tok.rs` theme | `src/renderer/ui_theme.odin` already does this, with density folded in. | 222 lines |
| Renderer: one instanced quad pipeline, exact box coverage | `src/renderer/shaders/hud.frag` samples atlas coverage and draws hard-edged rectangles. `box_cov` (`shader.wgsl:335-347`) matters for rounded or rotated edges, which no current component draws. | n/a |

## Scope

UI motion and world motion are separate subjects. `docs/design/motion.md` covers
the player, the legs, the camera, and the smoothing filter; it is not a UI
motion spec. Nothing in the overlay moves today, which is a fact about the code,
not a rule about what the overlay may do. If the overlay gains motion, the spring
in Rune is the piece to port; `Scene`, presence, and matched geometry
(`crates/rune-motion/src/scene.rs:480-520`) still assume a retained tree and stay
out.

## Conflicts

- **Text.** Rune rasterizes with swash and lays out with Parley; this engine
  rasterizes with FreeType and shapes with HarfBuzz. ADR 0007 measured why
  coverage beats a distance field at a one-pixel stem. Rune's text *caches* are
  portable; its text *rasterizer* is not, and swapping it would reopen a solved
  measurement.
- **Rendering.** The overlay emits flat axis-aligned rects and one
  atlas-sampled text quad (`src/renderer/shaders/hud.frag`). Nothing draws a
  rounded edge, a shadow, or an offscreen layer, so Rune's layer and blur stack
  has no input. Rune's shadow and blur paths are out of scope until a component
  needs them.

## Not found

- Frame time spent in `text_shape` in this engine. No counter exists, and no
  run was taken. The recommendation rests on the call graph, not a measurement.
  A miss/hit counter in the cache would make the real number visible.
- A Rune equivalent of this engine's render digest or scenario sweeps. Rune's
  harness covers snapshots, scripts, traces, and a tree dump
  (`tooling/args.rs:134-180`); it was not compared feature by feature.

## References

- Rune source: `~/Projects/other/rune`, commit `f18ead8`. Entry points that
  matter: `crates/rune/src/el.rs`, `runtime/commit/flatten.rs`,
  `runtime/input/hit.rs`, `text.rs`, `text/layout_cache.rs`,
  `text/glyph_cache.rs`, `render.rs`, `tooling/`.
- `~/Projects/other/rune/crates/rune/README.md`: states intent; the runtime
  sections above are what the code does.
- `docs/ui/README.md`: the eight components and the layer rule.
- `docs/design/motion.md`: world-motion rules for the player, legs, and camera.
  It is not a UI motion spec.
- `docs/adr/0007-coverage-atlas-for-ui-text.md`: why the text rasterizer is not
  replaceable.
- `docs/agents/harness.md`: what the harness already does, and the gap this
  document proposes to fill.
