# Mixed lighting: static fixtures and dynamic lamps

Status: research for #371. No renderer code changes. This note resolves the
production architecture, the bake boundary, the invalidation rule, the fit for
the one-mesh box renderer, and the terms the project needs.

## Bottom line

Copy the **energy split** of Unreal's Stationary light and Unity's **Mixed /
Baked Indirect** mode, not the fully baked modes:

- A **static fixture** keeps real-time direct light and real-time hard shadows.
  Only its diffuse bounce is baked.
- A **dynamic lamp** keeps real-time direct light and real-time hard shadows.
  It contributes no bounce.
- Static surfaces read a **baked indirect lightmap**. Dynamic objects read a
  **baked probe field**. Both contain only the static-source bounce: static
  fixtures and static emissive boxes, never dynamic lamps.
- A **static-only bake** builds a separate acceleration structure from static
  geometry and shades hits with static fixtures plus static emissive boxes. The
  frame's direct path, shadow path, light buffer, and TLAS stay as they are.
- A **bake key** hashes static geometry, static fixture settings, and bake
  quality. Any change to that key invalidates the whole bake. Dynamic objects
  and dynamic lamps never enter the key.

This preserves ADR 0041 (no ambient fill; unlit stays black) and ADR 0040 (hard
ray-query shadows). It supersedes ADR 0039 (dynamic-only lamps) and ADR 0042
(per-frame single-volume DDGI). It also contradicts the current design guide's
"no baked light" and "no texture" sentences; those docs need an explicit
revision, not a silent exception (see "Design-guide conflict").

## What the engines actually do

The split matters because "baked lighting" is not one mode. These are the
production modes that map to this decision.

| Engine mode | Direct | Shadows | Indirect | Dynamic objects |
| --- | --- | --- | --- | --- |
| Unreal **Static** | Baked | Baked | Baked | No dynamic direct from the static light; Volumetric Lightmap / Indirect Lighting Cache supplies indirect ([Static Light Mobility](https://dev.epicgames.com/documentation/unreal-engine/static-light-mobility-in-unreal-engine?lang=en-US)) |
| Unreal **Stationary** | Real-time | Real-time dynamic shadows plus baked indirect shadowing | Baked | Real-time direct and per-object shadows; baked indirect via Volumetric Lightmap ([Stationary Light Mobility](https://dev.epicgames.com/documentation/unreal-engine/stationary-light-mobility-in-unreal-engine?lang=en-US)) |
| Unreal **Movable** | Real-time | Real-time | Only with Lumen; no baked bounce | Real-time direct and shadows; dynamic GI only if Lumen is on ([Movable Light Mobility](https://dev.epicgames.com/documentation/unreal-engine/movable-light-mobility-in-unreal-engine?lang=en-US)) |
| Unity **Baked** | Baked | Baked | Baked | "Dynamic GameObjects do not receive light or shadow from Baked Lights"; Light Probes carry indirect ([Light Modes](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting-light-sources/components/configuring/light-modes/introduction)) |
| Unity **Mixed / Baked Indirect** | Real-time | Real-time | Baked | Real-time direct plus Light Probe indirect ([Lighting Mode](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting-light-sources/components/configuring/lighting-mode/lighting-mode)) |
| Unity **Mixed / Shadowmask** | Real-time | Static shadows baked into a shadow mask, up to four lights; dynamic shadows real-time | Baked | Real-time direct; baked shadows and indirect ([Lighting Mode](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting-light-sources/components/configuring/lighting-mode/lighting-mode)) |
| Unity **Mixed / Subtractive** | Real-time for dynamic objects, baked for static | Baked | Baked | Real-time direct; real-time shadows from the single main directional light only ([Lighting Mode](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting-light-sources/components/configuring/lighting-mode/lighting-mode)) |
| Unity **Realtime** | Real-time | Real-time | Only with Enlighten Realtime GI | Real-time direct; no baked bounce ([Light Modes](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting-light-sources/components/configuring/light-modes/introduction)) |

The harbagsa target is the **Unreal Stationary / Unity Mixed Baked Indirect**
row, with one simplification: hard ray-query shadows replace shadow maps, and
there is no shadow-channel overlap limit. Unreal's four-stationary-light limit
exists because stationary shadows consume shadow-map channels; the ray-query
path has no such channel constraint ([Stationary Light Mobility](https://dev.epicgames.com/documentation/unreal-engine/stationary-light-mobility-in-unreal-engine?lang=en-US)).

The fully baked rows are rejected because they bake direct light. A dynamic
object then loses direct light from that fixture, and a static surface's direct
shadow becomes a lightmap-resolution shadow. Both contradict the requested look
and the existing hard-shadow model.

## Recommended architecture

```text
Frame build
  arena_static_boxes() ───────────────┐
  placed static objects ──────────────┤ static boxes + stable keys
  placed dynamic objects ─────────────┼─ dynamic boxes
  spider boxes ───────────────────────┘
  static fixtures ──> direct light list ──> bake light list
  dynamic lamps ────> direct light list ──> (not in bake)

Bake (only when bake_key changes; not a frame pass)
  static boxes + bake lights + static emissive boxes
    -> static TLAS
    -> one-bounce indirect into
         lightmap atlas (static surfaces)
         probe volume (dynamic objects)
    -> publish atlas + probes, bump bake_version

Frame
  TLAS from all boxes
  cluster all direct lights (static + dynamic)
  depth prepass
  lit pass
    static box:  albedo * (direct + lightmap_indirect) + albedo * emissive
    dynamic box: albedo * (direct + probe_indirect)   + albedo * emissive
  TAA
  overlay
```

The direct formula and the hard-shadow visibility check are unchanged from
`src/renderer/shaders/box.frag`. The only new term is the source of
`indirect`: a lightmap fetch for static boxes, the existing probe gather for
dynamic boxes. The current formula already adds the emissive self term after the
direct plus indirect sum.

### Data flow

1. **Frame build** classifies every box as static or dynamic and every light as
   static fixture or dynamic lamp. The arena and placed static objects are
   static; placed dynamic objects and spider boxes are dynamic. Today
   `src/frame/frame.odin:99-107` appends arena boxes, then every placed object,
   then spider boxes, without a static tag or object identity; the split needs a
   parallel key array, not a new field on `geometry.Box`.
2. **Bake input** is exactly the static boxes, the static fixture list, the
   static emissive boxes, and the bake quality. It excludes dynamic crates,
   dynamic lamps, the spider, the camera, TAA, and UI. The bake uses a
   static-only TLAS so a moved crate cannot change the baked result.
3. **Bake shading** is the same one-bounce hit shade the current probe pass uses:
   a hit surface gets `albedo * (direct_from_static_fixtures + emissive)`;
   a miss returns zero. The lightmap itself stores only the indirect term at the
   receiver, never the receiver's direct light.
4. **Frame direct** uses every active light, static and dynamic, exactly as
   today: clustered forward+, one hard ray query per light, lamp instances
   excluded from shadow rays.
5. **Static surfaces** add the lightmap indirect term. **Dynamic objects** add
   the probe indirect term. Dynamic lamps add no indirect term anywhere.
6. **Dynamic lamp changes** move direct light and shadows immediately and never
   touch the bake. **Static fixture changes** move direct light and shadows
   immediately but leave the old indirect until a new bake is published; that
   stale window is a reported state, not a silent success.

## What is baked versus real-time

| Quantity | Static surfaces | Dynamic objects |
| --- | --- | --- |
| Direct from static fixtures | Real-time | Real-time |
| Direct from dynamic lamps | Real-time | Real-time |
| Shadows from any light | Real-time hard ray query | Real-time hard ray query |
| Indirect from static fixtures | Baked lightmap | Baked probe field |
| Indirect from dynamic lamps | None | None |
| Static emissive bounce | Baked | Baked (via probes) |
| Dynamic emissive bounce | None | None |
| Static geometry in the indirect solve | Yes | Yes |
| Dynamic geometry in the indirect solve | No | No |
| Emissive self term | Real-time | Real-time |

The important consequence is that a dynamic object still receives **real-time
direct** from a static fixture. That is why this is Stationary/Mixed Baked
Indirect and not Unreal Static/Unity Baked: in those modes a static light's
direct contribution is baked, so a dynamic object only gets indirect from the
cache. The current owner direction keeps direct real-time for both light kinds.

The baked probe field is the same idea as Unreal's Volumetric Lightmap and
Unity's Light Probes: precomputed incident light sampled by moving objects.
Unreal stores third-order spherical harmonics per cell and interpolates per
pixel ([Volumetric Lightmaps](https://dev.epicgames.com/documentation/unreal-engine/volumetric-lightmaps-in-unreal-engine?lang=en-US));
Unity stores 27 floats of L2 SH per probe and interpolates tetrahedrally
([Light Probe data format](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/direct-and-indirect-lighting/lightmap-data/light-probes-technical-information),
[Light Probes and moving GameObjects](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/direct-and-indirect-lighting/light-probes/moving-objects)).
The existing harbagsa probe atlas is already an octahedral incident-radiance
field with depth moments; it can be baked instead of updated. Keeping it avoids
the L2 SH ringing problem and keeps the existing gather shader.

## Static versus dynamic objects

The static/dynamic split is a property of the **object and body**, not of the
shader material:

- **Arena boxes and static placed objects** are static geometry. They receive a
  lightmap tile and cast into the static TLAS for the bake. The arena is 52
  static boxes today: six shell boxes plus 46 props (`src/game/arena.odin:16`,
  `src/game/arena_props.odin:87`).
- **Dynamic placed objects (crates) and spider boxes** are dynamic geometry.
  They receive probes and do not cast into the static bake TLAS. They still cast
  real-time shadows through the frame TLAS.
- **A static fixture's body** is a static box. It receives a lightmap tile like
  any static surface. Its point light is a bake source; its emissive body is a
  separate question (see open decisions).
- **A dynamic lamp's body** is a dynamic box. It receives probes, casts
  real-time shadows, and never casts into the bake. Its point light is excluded
  from the bake light list.

`Placed_Object` already carries a stable id, a body mode, and light settings
(`src/game/objects.odin:18-31`), so the frame can emit a stable key without a
new scene type. `geometry.Box` has no id and should not gain one; it is shared
by arena, props, spider, and physics (`src/geometry/box.odin:9-18`).

The three starting lamps (`INITIAL_LAMPS`, `src/game/prefabs.odin:61-65`) become
static fixtures. A newly placed lamp can be either kind; the kind is a separate
flag from body mode, and the body mode follows the kind.

## Bake invalidation

### What invalidates

A full rebake is required when any of these changes:

- a static fixture is added, removed, moved, rotated, or scaled;
- a static fixture's active flag, colour, intensity, range, or emissive changes;
- a static non-lamp box is added, removed, moved, rotated, scaled, recoloured, or
  changes emissive;
- a box flips between static and dynamic;
- a lamp flips between static fixture and dynamic lamp;
- bake quality or atlas layout changes.

These are exactly the inputs of the bake. A **single `bake_key` hash** over the
static boxes, static fixture settings, and bake quality is safer than a dirty
flag on every edit path. The editor has placement, drag, duplicate, delete,
undo/redo, scene load, and harness edits; a hash over the actual input catches
all of them and cannot forget a path. The game layer does not need to know about
the renderer; the frame builds the static input and the renderer hashes it.

### What does not invalidate

- moving, pushing, or rotating a dynamic crate;
- moving a dynamic lamp or changing its colour, intensity, or range;
- moving the spider, camera, or UI;
- changing TAA or view flags.

This is the main cost win: a moving lamp and a pushed crate are the common case,
and neither touches the bake.

### Rebuild scope and publish

A moved fixture changes its bounce across the whole room, not just nearby
tiles. Incremental per-tile invalidation would need a light-to-tile visibility
map and would still miss the fixture body's occlusion change. Rebuild the whole
atlas and the whole probe field; the scene is small.

Publish is a visibility event:

1. build the new atlas/probe buffers while the old ones remain bound;
2. wait for the old frame in flight or retire the old images after
   `MAX_FRAMES_IN_FLIGHT`;
3. swap the descriptors, bump `bake_version`, clear `bake_dirty`;
4. reset TAA history, because the shading changed without motion.

A failed bake must log and keep the old bake with a visible error/dirty state.
It must not silently fall back to black, probe-only, or an old bake that claims
to be current. That is the "do not hide a failed call behind a default" rule in
`AGENTS.md`.

## Fit for the current renderer

| Current fact | Consequence |
| --- | --- |
| One mesh: 24 vertices, position + normal, four vertices per face (`src/renderer/mesh.odin:6-14`) | Every face already has a unique normal; the lightmap can be per face without a vertex layout change. |
| Vertex shader passes world position and local position (`src/renderer/shaders/box.vert:29-36`) | A face UV can be derived in the fragment shader from local position and the local face normal. No UV attribute is needed. |
| Per-object draw with a push-constant object index (`src/renderer/draw_pass.odin:103-126`) | A per-object lightmap slot or per-face rects fit the existing draw pattern. |
| `Object_Data` is 144 bytes: model, previous model, colour (`src/renderer/uniforms.odin:31-51`) | Add a slot/weight, or a side buffer keyed by slot. The model matrix already supplies the world scale for the bake. |
| `geometry.Box` has centre, half extents, colour, rotation, emissive, visual-only; no id or static flag (`src/geometry/box.odin:9-18`) | The frame must emit a parallel static key/flag. Do not put renderer identity into shared geometry. |
| Frame order is arena, placed objects, spider (`src/frame/frame.odin:99-107`) | Arena is stably ordered; placed objects need their stable `Placed_Object.id` as the key. |
| Every active lamp is collected into one light list (`src/game/lights.odin:127-143`) | The frame needs a second filtered list for the bake, or a kind field on the CPU light. The GPU `Light` struct should not grow a bake-only field. |
| Lamps are forced to dynamic bodies (`src/game/prefabs.odin:215-225`) | Replace this with a lamp kind: static fixture or dynamic lamp. The body mode follows the kind. |
| One TLAS is built from all boxes each frame (`src/renderer/acceleration.odin:120-160`) | Add a static-only bake TLAS; keep the frame TLAS unchanged. |
| The probe field is traced and blended every frame (`src/renderer/probe.odin:240-330`) | Move the same work into the bake; remove the per-frame probe pass from `perf.PASS_ORDER`. |
| The probe field resets on a light hash (`src/renderer/probe.odin:329-350`) | Replace the per-frame light hash with the bake key; the baked field changes only on publish. |
| The render digest hashes boxes and lights but no bake state (`src/renderer/render_digest.odin:18-37`) | Add `bake_version`/`bake_key`; otherwise a rebake can compare as an identical image. |
| TAA has explicit reset reasons (`src/renderer/taa.odin:154-200`) | Add a bake-publish reset reason. |
| Scene colour is `R16G16B16A16_SFLOAT` (`src/renderer/frame_targets.odin:8`) | An HDR indirect lightmap fits the existing scene target; no tone-map change. |
| No sampler in the scene shader; the text atlas already shows the combined-image-sampler pattern (`src/renderer/text_atlas_resources.odin:23-97`) | One new sampled atlas and one descriptor binding; no general material texture system. |

The direct path is a good fit and should not be rewritten. The hard part is the
bake lifecycle: input hashing, static TLAS, publish, and the editor's static
edit paths.

## Cost and performance shape

The current single-volume DDGI costs about 0.76 ms for the probe pass and about
0.58 ms for the gather at 96 lights and 1080p on the baseline machine
(`docs/adr/0042-single-volume-ddgi.md`). Removing the per-frame probe pass and
the gather removes that cost, and adds one lightmap texture fetch per static
fragment. The hard direct shadow term remains the dominant cost: 4.29 ms at 96
lights, 5.94 ms full frame versus 1.65 ms with shadows off
(`docs/adr/0040-hard-point-light-shadows.md`). Mixed lighting does not make the
direct lights cheaper; it removes DDGI and moves the bounce off the frame.

The bake is a new off-frame cost. A rough scaling from the existing probe pass:
1,200 probes x 64 rays is 76.8k rays; a 100k-texel lightmap at 64 rays is 6.4M
rays, about 83x, or tens of milliseconds if the hit shade scales linearly. At
8 texels/m a 400k-texel atlas is about 330x, or hundreds of milliseconds. This
is an order-of-magnitude estimate, not a measurement. The bake light count also
matters: every hit evaluates the bake light list, and the 96-light frame budget is
not automatically a 96-light bake budget. Range-cull bake lights per texel/probe
or measure before promising an edit-time budget.

The bake should report its own `bake_ms` and `bake_lights` separately from the
frame GPU total. Hiding an edit-time stall inside the frame interval would make
the perf evidence lie.

## Known artifacts and controls

| Artifact | Cause | Normal control |
| --- | --- | --- |
| Stale indirect after a static fixture moves | Direct follows the new transform; baked indirect stays at the old one. Unity documents exactly this for Mixed lights: direct follows, indirect stays baked ([Adjust Mixed lights at runtime](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting-light-sources/components/configuring/lighting-mode/runtime)) | Invalidate the bake key; rebake before capture. Keep `bake_dirty` visible while stale. |
| Direct/indirect colour mismatch after a fixture tint change | Same as above: direct turns green, baked bounce stays red | Static fixture settings are bake inputs; lock them or rebake on commit. Do not allow a live tint on a static fixture with no rebake. |
| Double-counted fixture glow | The fixture's point light and its emissive body both feed the bake | Choose one source, or scale the body emission; expose a fixture-emissive policy. |
| Probe leak through thin walls | Probes on both sides of a 0.5 m wall interpolate through it | Keep the depth/facing rejection; keep wall thickness; do not reduce probe spacing without a leak check. |
| Probe ringing | L2 SH overshoot near a sharp light/dark boundary; Unity and Unreal both document de-ringing controls ([Unity light probe troubleshooting](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/direct-and-indirect-lighting/light-probes/troubleshooting), [Unreal Volumetric Lightmaps](https://dev.epicgames.com/documentation/unreal-engine/volumetric-lightmaps-in-unreal-engine?lang=en-US)) | Keep the octahedral probe atlas (no SH ringing) or add de-ringing if the representation changes. |
| Black dynamic object outside the probe volume | Unreal's ILC has no samples outside the importance volume ([Indirect Lighting Cache](https://dev.epicgames.com/documentation/unreal-engine/indirect-lighting-cache-in-unreal-engine?lang=en-US)); Unreal VLM clamps border texels | One volume covers the closed arena; if a future room is added, add a volume or clamp the border. |
| Dynamic crate leaves no indirect shadow | The bake cannot contain a movable occluder | Accepted. The crate still casts a real-time direct shadow; indirect is intentionally low-frequency. |
| Dynamic lamp leaves no bounce | The bake excludes dynamic lamps | Intended. The corner near a moving lamp stays darker than a static fixture's corner. Do not add a fill to compensate. |
| Bake hitch on edit commit | Full rebake blocks the queue | First version: bake at a controlled commit point and report `bake_ms`; chunk later if the hitch is unacceptable. |
| TAA smear after a publish | History sees new shading at old motion | Reset TAA history on publish. |
| Captures compare equal after a rebake | The digest has no bake state | Add `bake_version`/`bake_key` to the render digest and harness state. |
| Lightmap seams or compression blocks | See #372 | Padding, dilation, float format, bilinear; no baked direct. |
| Design-guide contradiction | `docs/design/README.md` and `world.md` ban textured/baked light; `GLOSSARY.md` says lamps are always dynamic and probes update per frame | Revise those documents in the same change as the implementation. The signature becomes "real-time direct and hard shadows with baked indirect bounce", not "no baked light". |

## Rejected alternatives

| Alternative | Why rejected |
| --- | --- |
| Keep per-frame DDGI and add baked lightmaps | Two indirect systems, two invalidation models, and the owner asked to replace DDGI. |
| Fully baked direct + indirect (Unreal Static / Unity Baked) | Direct shadows become lightmap-resolution; dynamic objects lose real-time direct from those lights. Contradicts the requested look. |
| Fully dynamic GI (Lumen, Enlighten Realtime, SSGI, path tracing) | The target is clean stylised flat boxes, not dynamic GI. Cost and maintenance are far above the requirement. |
| Ambient fill or a constant bounce floor | Already rejected by ADR 0041. It hides missing lamp coverage and is not transport. |
| Baked probes only, no lightmap | Static surfaces lose crisp per-face indirect and inherit probe interpolation and leak. The lightmap is the right static-surface representation. |
| Lightmap only, no probes | Dynamic crates and the spider get no indirect at all. |
| Bake every light, including dynamic lamps | That is dynamic GI with a cache; a moving lamp would invalidate every frame. |
| Per-frame rebake of the whole scene | A guaranteed hitch; the static set is the only part that needs baking. |
| Per-tile incremental invalidation | A fixture change reaches the whole room and changes its body's occlusion; a visibility map would be more machinery than a full small-scene rebake. |
| Static fixture settings changed live with stale indirect | The Unity runtime warning is a real artifact; either rebake or lock the settings. |
| Copy Unreal's four-stationary-light overlap limit | It exists for shadow-map channels; ray-query shadows do not have that limit. Do not add a limit we do not need. |
| Soft/area shadows or a lamp radius | A separate lighting decision. Hard shadows are the current look. |

## Terms for GLOSSARY.md

Add these, and revise the existing entries in the same edit:

| Term | Definition | Avoid |
| --- | --- | --- |
| **Mixed lighting** | Static fixtures keep real-time direct light and hard shadows while their indirect bounce is baked; dynamic lamps keep real-time direct light and hard shadows and have no bounce. | Hybrid rendering, half-baked lighting |
| **Static fixture** | A lamp fixed in the world. Its body is static. Direct and hard shadows are real-time; its diffuse bounce is baked. | Static lamp, baked lamp |
| **Dynamic lamp** | A lamp that can move. Its body is dynamic. Direct and hard shadows are real-time; it contributes no bounce. | Movable light, realtime lamp |
| **Lamp kind** | Static fixture or dynamic lamp. Separate from body mode; the kind decides the body mode. A non-lamp object keeps the ordinary static/dynamic body mode. | Lamp type, light mode |
| **Baked indirect** | The one-bounce indirect light from static fixtures and static emissive boxes stored in the lightmap and probe field. It excludes dynamic lamps and dynamic geometry. | Baked lighting, GI cache |
| **Bake** | The off-frame pass that fills the lightmap atlas and the probe field. It is not a frame pass and has its own timing. | Probe pass, lighting build |
| **Bake key** | The hash of static geometry, static fixture settings, and bake quality that identifies a bake. A change makes the current bake stale. | Dirty flag, light hash |
| **Bake invalidation** | Marking the bake stale when its key changes. The old bake may render until the new one is published, but the stale state is visible. | Refresh, rebuild |
| **Static geometry** | Arena boxes and static placed objects. It receives lightmap indirect and casts into the bake TLAS. | Static mesh, level mesh |
| **Dynamic geometry** | Dynamic placed objects and spider boxes. It receives probe indirect and does not cast into the bake TLAS. | Movable mesh |
| **Static TLAS** | The bake-time acceleration structure built from static geometry only. The frame TLAS still contains every box. | Bake BVH |
| **Unbaked static box** | A static box with no current lightmap tile. It must use a visible fallback (probe indirect or a marked error), never a silent black. | Missing lightmap |
| **Indirect term** | The value added under albedo for bounce light. In this renderer it is a cosine-weighted average incident radiance on the same scale as the direct term, not physical irradiance. | Irradiance (unless the units are fixed) |

Revise the existing entries:

- **Indirect light (GI)**: now "one diffuse bounce from a static fixture; dynamic
  lamps do not bounce; static surfaces read a lightmap and dynamic objects read a
  baked probe field."
- **Probe**, **Probe volume**, **Probe atlas**: now baked data, not per-frame
  state. The probe volume can keep the 20 x 3 x 20 grid at 2 m.
- **Probe pass**: remove or rename to **Bake pass**, outside `PASS_ORDER`.
- **Lamp prefab**: no longer "always dynamic"; the prefab has a lamp kind.
- **Body mode**: no longer "a lamp always uses a dynamic body"; the lamp kind
  decides the body mode.
- **Static box**: clarify arena static box versus static placed object. Both are
  static geometry for the bake.

## Open decisions for the owner

1. **Bake trigger.** Commit-time off-frame bake, explicit command, or next-frame
   automatic? Recommendation: commit + off-frame, old bake visible with
   `bake_dirty`; block only at startup.
2. **Bake budget.** 4 texels/m, 64 rays, one bounce is the starting point. 8
   texels/m and more rays are measured options; #372 owns the atlas size.
3. **Probe representation.** Keep the existing octahedral atlas with depth
   moments (recommended: no SH ringing) or move to L2 SH. One volume is enough
   for the closed arena; a second room is a later decision.
4. **Fixture emissive policy.** Does a static fixture's emissive body also feed
   the bake? Current probe behavior counts both the point light and the body.
   Recommendation: keep parity, expose a scale, measure the corner.
5. **New lamp default.** Static fixture (matching the starting lamps) or dynamic
   lamp? Recommendation: static fixture by default, with an explicit
   dynamic-lamp toggle in the palette and inspector.
6. **Static fixture live edits.** Recommendation: no live colour/intensity/range
   without a rebake; static fixture settings are bake inputs. Dynamic lamps stay
   live.
7. **Unbaked static fallback.** Probe indirect or a visible error/black?
   Recommendation: probe indirect plus `bake_missing`, never silent black.
8. **Debug override.** Recommendation: rename `gi` to `baked_indirect`; the
   toggle now means baked indirect, not a live field.
9. **Harness contract.** Add `bake` state (`dirty`, `version`, `key`, `bake_ms`,
   `texels`, `atlas_size`) and a way to wait for or force a bake before a
   capture. This is operational evidence, not a gate.
10. **Static fixture lifecycle.** Recommendation: edits are debug-mode only; a
    removal triggers a rebake like any other static edit.
11. **Atlas growth.** Recommendation: one 2048 x 2048 atlas first, with an
    `atlas` field in the slot data so a texture array is additive later.
12. **Baked AO.** Recommendation: no for the first version. AO is not transport,
    it darkens static geometry independently of the lamps, and it reads as a
    surface texture.
13. **Design-guide revision.** Approve "no surface texture; one lighting-data
    texture; no dynamic GI" in place of "no texture / no baked light". Without
    it, the implementation and the guide will contradict each other.
14. **Bake light budget.** Static fixtures stay in the clustered direct loop. If
    many are placed, the bake light list grows even though the frame budget is
    capped. Decide whether bake lights are range-culled per texel/probe or
    static fixture count is capped.

## Primary sources

- Unreal light mobility: [Static](https://dev.epicgames.com/documentation/unreal-engine/static-light-mobility-in-unreal-engine?lang=en-US), [Stationary](https://dev.epicgames.com/documentation/unreal-engine/stationary-light-mobility-in-unreal-engine?lang=en-US), [Movable](https://dev.epicgames.com/documentation/unreal-engine/movable-light-mobility-in-unreal-engine?lang=en-US).
- Unreal indirect for movable objects: [Indirect Lighting Cache](https://dev.epicgames.com/documentation/unreal-engine/indirect-lighting-cache-in-unreal-engine?lang=en-US), [Volumetric Lightmaps](https://dev.epicgames.com/documentation/unreal-engine/volumetric-lightmaps-in-unreal-engine?lang=en-US), [CPU Lightmass](https://dev.epicgames.com/documentation/unreal-engine/cpu-lightmass-global-illumination-in-unreal-engine?lang=en-US).
- Unreal lightmap UVs and padding: [Understanding Lightmapping](https://dev.epicgames.com/documentation/unreal-engine/understanding-lightmapping-in-unreal-engine?lang=en-US).
- Unreal multiple baked states: [Precomputed Lighting Scenarios](https://dev.epicgames.com/documentation/unreal-engine/using-precomputed-lighting-scenarios-in-unreal-engine?lang=en-US).
- Unity light modes: [Light Modes](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting-light-sources/components/configuring/light-modes/introduction), [Lighting Mode](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting-light-sources/components/configuring/lighting-mode/lighting-mode), [Adjust Mixed lights at runtime](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting-light-sources/components/configuring/lighting-mode/runtime).
- Unity probes: [Light Probe data format](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/direct-and-indirect-lighting/lightmap-data/light-probes-technical-information), [Light Probes and moving GameObjects](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/direct-and-indirect-lighting/light-probes/moving-objects), [Troubleshooting Light Probes](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/direct-and-indirect-lighting/light-probes/troubleshooting).
- Papers: [Ramamoorthi and Hanrahan, An Efficient Representation for Irradiance Environment Maps](https://cseweb.ucsd.edu/~ravir/papers/envmap/envmap.pdf); [Greger et al., The Irradiance Volume](https://www.sci.utah.edu/~bigler/images/msthesis/The%20irradiance%20volume.pdf).
- Repository decisions and code: `docs/adr/0040-hard-point-light-shadows.md`, `docs/adr/0041-absolute-darkness.md`, `docs/adr/0042-single-volume-ddgi.md`, `docs/adr/0039-dynamic-only-lamps.md`, `src/renderer/`, `src/frame/frame.odin`, `src/game/`.
