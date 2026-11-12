# Rune as the UI layer: integration plan

Date: 2026-11-10
Status: proposed. One delivery, gated by a device-adoption spike.

Sources: Rune checkout at `~/Projects/other/rune`, commit `f18ead8`
(2026-11-10), crate `rune 0.0.1`; wgpu 30.0.1 from the local registry; the
three companion notes in this directory.

## Decision

Run Rune in the game process, on the game's Vulkan device, and let Rune draw the
UI directly into the game's final image, on top of the 3D. Odin keeps the
window, the device, the swapchain, the 3D renderer, and the game state. Rune
keeps everything it already does: the element tree, memo, Taffy layout, input
routing, springs, text shaping, the paint pipeline, `rune-kit`, layers, shadows,
gradients, and backdrop blur.

Nothing is ported. The UI is authored in Rust with Rune's normal API.

This is route A in the earlier discussion, with one improvement: no separate UI
texture and no composite pass. Rune draws over the 3D in the swapchain image.

## Why this route

Route B (Rune computes, Odin draws) needs Odin to reimplement Rune's renderer:
the uber shader at about 2,000 GLSL lines for rects, borders, shadows,
gradients, glyphs and images (`shader.wgsl:359-545`), the layer planner and
compositor (`render/layers.rs:226-760`), and, for the materials and glass in
the demos, `rune-fx` (2,228 WGSL lines) and `rune-light` (1,231 WGSL lines).
That is a permanent parity gap against a moving target.

Route A needs one startup handshake and a shim. Rune's renderer already accepts
any target:

- `Renderer::new(&wgpu::Device, TextureFormat)` is public (`render.rs:762-764`).
- `Renderer::prepare(device, queue, atlas, instances, viewport)` uploads the
  frame (`render/upload.rs:187-215`).
- `Renderer::encode_layers(&encoder)` is public (`render/layers.rs:661-667`).
- `Renderer::draw_target_range_with(encoder, view, format, load, range, hook)`
  is public and takes a `LoadOp`, so it can draw over existing pixels
  (`render.rs:847`).
- `Renderer::submit(&queue, encoder)` is public (`render.rs:947-950`).
- `Runtime::frame(dt)` is public (`runtime/frame.rs:305-307`).

The only thing Rune cannot do today is adopt a device and a swapchain image it
did not create. wgpu 30.0.1 exposes that as public `unsafe`:

- `wgpu_hal::vulkan::Instance::from_raw` (`wgpu-hal/src/vulkan/instance.rs:317`).
- `wgpu_hal::vulkan::Adapter::device_from_raw`
  (`wgpu-hal/src/vulkan/adapter.rs:2570`).
- `wgpu::Adapter::create_device_from_hal` (`wgpu/src/api/adapter.rs:77`).
- `wgpu_hal::vulkan::Device::texture_from_raw`
  (`wgpu-hal/src/vulkan/device.rs:296`).
- `wgpu::Device::create_texture_from_hal` (`wgpu/src/api/device.rs:341`).

No fork is required. The shim depends on `rune` at a pinned git rev, and on the
same `wgpu` 30.0.1, so `wgpu::Device` is the same type on both sides.

## Architecture

| Piece | Owner | Notes |
| --- | --- | --- |
| Window, `VkInstance`, physical device | Odin | Created as today, plus the instance extensions the shim asks for. |
| `VkDevice`, one graphics queue | Shim | Created with the union of the game's features and wgpu's required set. Returned to Odin. |
| Swapchain, 3D passes, TAA, captures | Odin | Unchanged, except it now uses the shim's device and queue. |
| `Runtime<UiState>`, view, handlers, springs, text | Shim | Rust, one thread, the game's main thread. |
| `Renderer`, pipelines, layers, atlas | Shim | Built on the adopted device with the swapchain format. |
| Input capture, game state | Odin | SDL events and a flat snapshot cross to the shim each frame. |
| Actions | Shim to Odin | A queue of app-defined enums, drained after the step. |

The shim is one Rust static library, linked like Box3D. The UI view is Rust code
in the same crate or a sibling crate, written with Rune's normal `El` API.

## Startup

1. Odin asks the shim for the Vulkan instance extensions wgpu needs
   (`ui_vk_instance_extensions()`), and creates the instance with its own set
   plus those names.
2. Odin selects the physical device as today.
3. Odin calls `ui_vk_init(instance, physical_device, &wants)`. The shim:
   - wraps the instance with `Instance::from_raw` and `wgpu::Instance::from_hal`;
   - enumerates adapters and matches `raw_physical_device` to the game's device;
   - reads `required_device_extensions` and `physical_device_features`;
   - merges them with the game's required extensions and features from `wants`;
   - calls `vkCreateDevice` on the same queue family, creates the queue with
     `flags = 0`;
   - adopts it with `device_from_raw` and `create_device_from_hal`;
   - returns the `VkDevice`, queue handle, family index, and wgpu device/queue.
4. Odin loads device entry points as today, creates the swapchain, and passes
   the swapchain image views to the shim once with `ui_vk_images(...)`.
5. The shim wraps each image with `texture_from_raw` and
   `create_texture_from_hal`, creates a `wgpu::TextureView` per image, and
   builds `Renderer::new(&device, format)`.

The flag ordering matters: the instance extensions are needed before
`vkCreateInstance`, and the device extensions/features are needed before
`vkCreateDevice`. The shim owns both because wgpu's feature chain is a Rust
type.

## Frame

Odin:

1. Poll SDL, map events into `UiEvent`, and build `UiSnapshot` from the game
   state.
2. Acquire the swapchain image and record the 3D frame into it as today.
3. Call `ui_frame(host, dt, &snapshot, events, count)`. The shim writes the
   snapshot into `UiState`, pushes the events, and calls `rt.frame(dt)`.
4. Call `ui_draw(host, image_index)`. The shim:
   - `renderer.prepare(device, queue, &mut rt.text.atlas, &rt.instances, size)`;
   - opens an encoder, `renderer.encode_layers(&mut encoder)`;
   - `renderer.draw_target_range_with(&mut encoder, &view, format,
     LoadOp::Load, 0..instances.len(), &mut noop_hook)`;
   - `renderer.submit(&queue, encoder)`.
5. Submit the game's 3D command buffer. Order: 3D first, Rune second, present
   third, all on the same queue.
6. Present.
7. Drain `ui_actions(host)`, apply the game actions, and clear the queue.

The UI pass is one extra queue submission per frame. A static UI still draws,
because the swapchain image rotates. A few hundred instances is cheap.

### Image layout contract

| Point | Layout | Who sets it |
| --- | --- | --- |
| After the 3D pass | `COLOR_ATTACHMENT_OPTIMAL` | Odin |
| wgpu `initial_state` | `TextureUses::COLOR_TARGET` | Shim, once per image |
| Rune draws | `LoadOp::Load` | Shim |
| End of Rune's encoder | `PRESENT_SRC_KHR` via `transition_resources` | Shim |
| Present | `PRESENT_SRC_KHR` | Odin |

The swapchain image needs `COLOR_ATTACHMENT` and `TRANSFER_SRC` (backdrop blur
copies it) and `SAMPLED` if a UI effect samples it. Check against
`supportedUsageFlags`; fall back to skipping backdrop blur if `TRANSFER_SRC` is
not available.

## Boundary

The shim owns the UI state. Odin owns the game state. Nothing else crosses.

```c
typedef struct UiHost UiHost;

typedef struct {
    double dt;                /* seconds, fixed for a capture */
    float width, height, scale; /* points; scale is device pixels per point */
} UiFrame;

typedef struct {
    uint32_t open_menu, selected, sprint_mode, grounded;
    float speed, position[3], camera_yaw;
    /* app-defined, extending as the UI grows */
} UiSnapshot;

typedef struct {
    uint32_t kind;            /* pointer, wheel, key, text, focus, resize */
    uint32_t flags;           /* modifier bits, button, pressed */
    float x, y, dx, dy;       /* points */
    int32_t key;              /* shim key code */
    const uint8_t *text;      /* UTF-8, copied by ui_frame */
    uint32_t text_len;
} UiEvent;

typedef struct {
    uint32_t kind;            /* app-defined GameAction */
    int32_t i;
    float f;
} UiAction;
```

Functions: `ui_vk_instance_extensions`, `ui_vk_init`, `ui_vk_images`, `ui_new`,
`ui_free`, `ui_frame`, `ui_draw`, `ui_actions`, `ui_actions_clear`,
`ui_set_scale`, `ui_stats`.

Rules:

- UI state stays in Rust, so a toggle, a selection, or a drag responds in the
  same commit. Odin never writes UI state.
- Game state crosses as a snapshot every frame. No events to miss, no mirror to
  keep coherent beyond the one struct.
- Handlers push `GameAction` into `UiState.actions`; the shim drains it after
  `frame`. No C callback runs inside a Rune handler, so no reentrancy and no
  aliasing of the borrowed runtime.
- Game to UI commands are `ui_*` setters that mutate `UiState` and call
  `rt.invalidate()`. They run between frames.
- Coordinates: SDL gives device pixels; divide by `scale` to points before
  pushing events. Instances are already device pixels; never scale them again.
- `Runtime` is not `Send`: handlers are `Rc`, scratch is `RefCell`, and several
  clocks are thread-local. The shim and the game must run on the same thread.

## Determinism and the harness

- `Runtime::new` with `wall_start = None`, a fixed `dt`, and an explicit
  `time_scale` and `reduced_motion` gives a deterministic UI clock.
- Call `rt.frame(0.0)` once before the first input, so hit rects exist, exactly
  as Rune's headless harness does.
- One `frame(dt)` can run more than one commit when a timer fires. Count
  `rt.stats.commits`, not calls.
- Pass explicit font bytes with `Runtime::with_text`. `TextSystem::new` can
  discover system fonts, which differ by machine.
- The game's harness renders to an offscreen target. That target is just
  another image: wrap it the same way and the UI is captured with the scene.
  `--no-render` runs cannot draw the UI; they can still step the runtime if the
  shim is built without the renderer, but the simplest rule is that UI capture
  requires a device.

## Build

- Add `ui/` as a Cargo workspace with one `staticlib` crate. `cargo build
  --release` produces `libharbagsa_ui.a`.
- `Makefile`: build the Rust library before linking, and link it next to
  `libbox3d.a` with `-lpthread -ldl -lm`.
- Add the pinned `rune` git rev and `wgpu 30.0.1` to the lockfile. The lockfile
  is committed.
- `make check` compiles the Rust crate too. The 400-line limit does not apply
  to Rust files, but keep the shim small and split it by boundary.
- The shim must set `panic = "abort"` in its release profile. No Rust panic may
  unwind into Odin.

## Work breakdown

One delivery, in this order. The first item is a hard gate.

1. **Device-adoption spike.** A Rust binary that adopts a Vulkan instance and
   device created by a small Odin or C program, wraps one `VkImage`, draws a
   solid Rune rect into it with `LoadOp::Load`, and shows the result. Kill
   criteria: `device_from_raw` rejects the device, the image layout is
   unmanageable, or the swapchain usage flags exclude `TRANSFER_SRC`. If the
   spike fails, stop and fall back to route C or the offscreen copy.
2. **Shim core.** `Runtime<UiState>`, `Renderer`, image wrapping, one static
   view. Prove a menu draws over a test pattern.
3. **Boundary.** Snapshot, events, actions, scale, and the frame loop. Prove a
   click changes a toggle and a game action comes back.
4. **View.** Port the existing surfaces to Rust views in one pass: status panel,
   capture hint, notice, settings menu, palette, debug inspector. Keep the same
   content and hierarchy. Rune's own components are allowed where they fit.
5. **Visual pass.** Adopt Rune's kit and materials where the game wants them.
   This is the point where the old theme tokens stop being the source of truth.
6. **Harness.** Add UI events to the scenario format and capture the UI with the
   scene. Update `docs/agents/harness.md`.
7. **Delete the old path.** Remove `src/ui`, `src/renderer/hud_*`,
   `src/renderer/ui_theme.odin`, the overlay pipelines, and the atlas. Keep the
   debug line pass if it is still used.

## Risks

| Risk | Effect | Mitigation |
| --- | --- | --- |
| The game cannot create a device satisfying wgpu's contract | Route dies | The spike is the first item. Nothing else starts until it passes. |
| Swapchain images do not support `TRANSFER_SRC` | Backdrop blur cannot copy the scene | Check `supportedUsageFlags`; skip blur or render to an intermediate with the extra usage. |
| Layout ownership across wgpu and raw Vulkan | Validation errors or corruption | One table, one owner per transition, all on one queue, one mutex. |
| `Runtime` is thread-bound | Cannot move the UI to a worker | Keep the UI on the main thread. Layout for a HUD is microseconds. |
| Rune is pre-release | A rev bump breaks the shim | Pin the rev. The shim touches a small public API, so the diff is small. |
| Rust panics across FFI | Undefined behavior | `panic = "abort"`, no unwinding, `#[repr(C)]` only at the boundary. |
| Fonts differ by machine | Captures drift | Ship font bytes and pass them with `Runtime::with_text`. |

## Parity matrix

| Feature | Route A |
| --- | --- |
| Element tree, keys, memo | Yes, Rune's. |
| Taffy layout, CSS semantics | Yes. |
| Springs, transitions, presence | Yes. |
| Input routing, focus, hit list | Yes, inside Rune. |
| Text shaping, atlas, fallback | Yes. |
| Layers, group opacity, cutouts, turns | Yes. |
| Rects, borders, shadows, gradients | Yes. |
| Backdrop blur over the 3D | Yes, when the swapchain allows `TRANSFER_SRC`. |
| `rune-kit` components | Yes. |
| `rune-fx` effects | Needs the effect hook wired to `FxRenderer`. Optional. |
| `rune-light` glass | Separate renderer and passes. Optional. |
| Native windows, overlays, menus | No. The game owns the window. |
| Video and native surfaces | No. |
| Accessibility (AccessKit) | No platform adapter. |
| IME and clipboard | Possible; forward SDL text input if a text field is added. |

## Out of scope

- OS windows, overlays, and native menus. The game has one window.
- Video playback and native surfaces.
- Accessibility.
- Multi-window Rune apps.

## Open questions

- Whether the game's TAA and capture passes leave the final image in a state
  the UI pass can load. The spike must test the real frame graph, not a toy.
- Whether the game wants `rune-fx` materials. The kit does not need them; the
  demos do.
- The exact action vocabulary. It grows with the UI and belongs in `UiState`.

## References

- `docs/research/rune-paint-contract.md`: the instance and shader contract, if
  the paint route is ever revisited.
- `docs/research/rune-gpu-interop.md`: the wgpu adoption APIs, the dma-buf
  alternatives, and the readback cost.
- `docs/research/rune-host-boundary.md`: the public runtime API, the event
  model, and the optional patches.
- `docs/research/rune-ui-port.md`: what is worth porting if the integration
  route is rejected.
