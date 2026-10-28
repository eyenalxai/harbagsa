# Lighting quality, capture matrix, and budgets

Status: research for #375. No renderer code changes. This note assumes the mixed
model in [mixed-lighting.md](mixed-lighting.md) and the atlas rules in
[lightmap-boxes.md](lightmap-boxes.md). It informs #378 (decisions) and #379
(spec).

## Bottom line

- The mixed system can meet the clean look, but the quality bar must separate
  **static surfaces** from **dynamic objects**. Static surfaces read per-face
  lightmaps and cannot leak across a closed wall. Dynamic objects read a coarse
  probe field and can. Treat the two as different products with different
  tolerances.
- **Do not bake direct light or shadows.** A "baked static shadow" is a failure,
  not a feature. A moving crate under a static fixture must still cast a hard
  real-time shadow, and the old shadow must disappear when the crate moves.
- The meaningful evidence is **region statistics, profiles, and tight paired
  captures**, not full-frame means. A full-frame mean hides a wall leak and a
  one-pixel seam.
- The performance win is smaller than "remove DDGI" suggests. The probe
  **update** (about 0.76 ms at 96 lights and 1080p) disappears; the probe
  **gather** (about 0.58 ms) remains for dynamic objects, so only its static share
  is saved. Budget the win relative to a fresh baseline. The current design guide
  also bans baked light and texture; revise it before a visual review can pass.

## What "clean" means

In plain terms, a person standing still in normal play sees:

1. Flat coloured boxes with hard shadow edges that move when a dynamic lamp or a
   crate moves. No soft, blurry, or double shadow.
2. A low-frequency bounce in corners and on nearby walls; a corner near a lamp
   is not a black hole. It is visible, stable, and does not crawl, shimmer, band,
   or pop as the camera or a crate moves.
3. No bright patch on the dark side of a wall. No thin line, block, or
   texture-like pattern on a continuous face.
4. With every lamp removed, an interior view with no emissive prop is black
   (the spider's eyes and markings are the exception). A moving dynamic lamp
   changes direct light and shadow only; a far corner it cannot see does not change, and a stale bake is announced.

**Ship bar.** Every row in the capture matrix has a run directory. A reviewer can
open the compare panel, the profile, and the report, and the numbers are inside
the thresholds below. No failure class from **Failure versus accepted
limitation** is present. The accepted limitations are written into
`docs/design/`, `GLOSSARY.md`, and `README.md`. The 1080p/96-light perf run and
the bake run are inside budget on the baseline machine.

These are review thresholds, not a test gate. Do not wire them into `make check`, CI, or `diff --max-pixels`; a number outside a threshold starts a conversation, not a failed build.

## The artifact classes

"Dilation" here means copying valid chart-edge texels outward into the gutter and
into invalid texels so a bilinear tap never reads black or a neighboring chart.

| Class | What it looks like | Production control | Control in this renderer |
| --- | --- | --- | --- |
| **Seam** | A thin dark or bright line on a continuous face; a visible chart boundary. A hard 90-degree edge between two faces is correct, not a seam. | Four-texel padding between charts; center-to-center UVs; dilation. Unity stitches seams only within one GameObject, not between separate objects, and the GPU cannot blend across separated charts ([Unity seam stitching](https://docs.unity3d.com/2022.3/Documentation/Manual/Lightmapping-SeamStitching.html)); Unreal asks for at least four texels of padding to avoid bleed ([Understanding Lightmapping](https://dev.epicgames.com/documentation/en-us/unreal-engine/understanding-lightmapping-in-unreal-engine)). | Per-face charts; 4-texel gutter; bilinear, no mips; center-to-center rects; profile across every continuous boundary. No stitching across boxes; a 90-degree edge stays hard. |
| **Dilation / invalid texels** | Black or smeared gutter; blocky dark patches where a face is buried in another box. | Mark invalid texels and clone the nearest valid value; Unity's texel validity and dilation do this ([Troubleshooting lightmapping artifacts](https://docs.unity.com/en-us/engine/6000.7/manual/lighting-overview/direct-and-indirect-lighting/lightmapping/baking-before-runtime/troubleshooting/troubleshooting-lightmapping-artifacts)); Lightmass pads around atlas edges ([Understanding Lightmapping](https://dev.epicgames.com/documentation/en-us/unreal-engine/understanding-lightmapping-in-unreal-engine)). | Count invalid and dilated texels; dilate 4 texels; show the atlas in a debug capture. A black gutter is a failure, not a style. |
| **Light leak** | A bright patch on the dark side of a wall, or a dynamic object that is lit by a lamp it cannot see. | Thicker walls, more chart spacing, invalid probes, dilation, rendering layers. Unity's APV guide says thicker walls or denser probes fix a wall leak, and its probe guide says sparse probes leak across dark gaps ([APV light leaks](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting/probevolumes/fixissues/troubleshoot-light-leaks), [Light Probe troubleshooting](https://docs.unity.com/engine/6000.6/manual/lighting-overview/direct-and-indirect-lighting/light-probes/troubleshooting)); Unreal's Volumetric Lightmap says the only fixes for a wall leak are smaller detail cells or a thicker wall ([Volumetric Lightmaps](https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-lightmaps-in-unreal-engine)). | Static surfaces: per-face lightmaps; transport cannot cross the wall. Dynamic objects: invalidate probes inside geometry, dilate, and accept a capped residual leak. The arena's 0.5 m walls are four times thinner than the 2 m probe spacing; do not promise a leak-free dynamic case. |
| **Probe interpolation** | Bands or steps as a crate crosses a 2 m cell; an object that is uniformly too bright or too dark; ringing on the back side of a bright edge. | Per-pixel interpolation, denser probes, an anchor or proxy volume, tetrahedral interpolation. Unity warns that baking direct into probes creates sharp discontinuities and that sparse probes bleed across dark gaps ([Light Probe troubleshooting](https://docs.unity.com/engine/6000.6/manual/lighting-overview/direct-and-indirect-lighting/light-probes/troubleshooting)); Unreal interpolates the Volumetric Lightmap per pixel and calls out fewer leaks than per-object interpolation ([Volumetric Lightmaps](https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-lightmaps-in-unreal-engine)). | Keep the existing per-pixel octahedral gather. It avoids spherical-harmonic ringing. Keep the 2 m grid for the first version; a crate sweep is the evidence for whether it is enough. |
| **Dynamic-object mismatch** | A crate looks pasted into a corner; it gets no indirect shadow; its bounce is flat across its face; it is much brighter or darker than the wall behind it. | Probe lighting per pixel or per object plus an authored rim term. Anomaly 2 shipped with one probe per object, an irradiance gradient for the top face, no shadow transitions on the object's surface, and a darkened bottom face to hide missing occlusion ([Lightmapping in Anomaly 2 mobile](https://knarkowicz.wordpress.com/2014/07/20/lightmapping-in-anomaly-2-mobile/)); TF2 uses an irradiance volume plus a rim term so characters stay readable away from local lights ([Illustrative Rendering in TF2](https://wiki.teamfortress.com/wiki/Illustrative_Rendering_in_Team_Fortress_2)). | Accept the low-frequency mismatch. The real-time direct shadow grounds the crate. Do not add a rim or a fill to hide it; that would be a new look decision. |
| **Stale bake** | Direct light turns green while the corner bounce stays red; a moved fixture's bounce stays at the old position. | Rebuild the bake when its inputs change, and make the stale state visible. Unity documents exactly this for Mixed lights: runtime changes affect direct light but not baked indirect, and moving the light leaves indirect at the baked position ([Adjust Mixed lights at runtime](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting-light-sources/components/configuring/lighting-mode/runtime)). The Witness precomputed multiple lightmaps for switchable states and switched them outright at runtime (interpolation was planned); storage grows with each variant ([Multi-lightmaps](https://www.the-witness.net/news/2010/04/graphics-tech-multi-lightmaps/)). | Bake key + `bake.dirty` + rebake at commit. Keep the old bake visible, but never let a capture call it current. The stale window is evidence, not a hidden success. |
| **Missing dynamic shadows from baked lights** | A moving crate loses its shadow because the lamp was fully baked. | Do not fully bake. Unity's Baked mode explicitly says dynamic GameObjects receive no light or shadow from Baked Lights ([Light Modes](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting-light-sources/components/configuring/light-modes/introduction)); Unreal's Stationary mode keeps direct lighting dynamic and stores only indirect lighting and shadowing in lightmaps, with per-object shadows for movable objects ([Stationary Light Mobility](https://dev.epicgames.com/documentation/en-us/unreal-engine/stationary-light-mobility-in-unreal-engine)). | Keep direct and hard shadows real-time for both static fixtures and dynamic lamps. This class cannot occur unless someone bakes direct. The `static-shadow` capture exists to prove it did not happen. |
| **Compression / banding** | 4x4 blocks on a smooth wall; contour bands in a corner gradient. | Float first; compression later only if invisible; dither the 8-bit output. Unity lists banding and blocky artifacts from low-quality lightmap compression ([Troubleshooting lightmapping artifacts](https://docs.unity.com/en-us/engine/6000.7/manual/lighting-overview/direct-and-indirect-lighting/lightmapping/baking-before-runtime/troubleshooting/troubleshooting-lightmapping-artifacts)); Unreal says compression artifacts are less noticeable in indirectly lit areas but still visible on small charts ([Understanding Lightmapping](https://dev.epicgames.com/documentation/en-us/unreal-engine/understanding-lightmapping-in-unreal-engine)). | `R16G16B16A16_SFLOAT` atlas first. Do not add BC6H until a float capture is clean and a BC6H capture is indistinguishable at 1080p. A 2048-square RGBA16F atlas is 32 MiB; BC6H is 4 MiB ([BC6H format](https://learn.microsoft.com/en-us/windows/win32/direct3d11/bc6h-format)). |

**Production pattern.** The shipped examples do not solve these classes with
dynamic GI. They bake static surfaces, probe dynamic objects, keep direct and
shadows real-time for movers, and art-direct the residual. Anomaly 2 accepted one
probe per object and no shadow transitions; The Witness accepted precomputed
variants; TF2 accepted a coarse irradiance volume and hid it with a rim. The
question is which artifacts are below the visible threshold for this look.

## Fit for this arena

| Fact | Consequence |
| --- | --- |
| Every object is one box; every face is a rectangle with one normal. | Per-face lightmap charts are natural. A 90-degree edge is a real normal change and should stay hard; no UV unwrap or seam stitching across faces. |
| Static surfaces are the arena shell and static placed objects. | A per-face chart on the outside of a 0.5 m wall cannot see a lamp inside. Static transport leaks are controlled by the chart, not by probe density. |
| Dynamic objects are crates, the spider, and dynamic lamps. | They read the baked probe field. The field is 2 m spacing; a 0.5 m wall is thinner than one cell. Dynamic leak is the main accepted risk. |
| Direct light is a clustered forward+ loop with one hard ray query per light. | Do not touch it. The new work is one lightmap fetch for static fragments and the existing probe gather for dynamic fragments. |
| `box.frag` shades `v_color * (direct + probe_indirect) + v_color * object.color.a`. | The mixed formula is the same shape with `indirect` chosen by static/dynamic. No ambient term, no tone-map change. |
| `PASS_ORDER` still includes the probe update pass, and `render_digest` includes `probe_volumes` and `gi`. | After the change, `perf.gpu.probe` must be absent or zero, and `bake_version`/`bake_key` must be in the digest. Otherwise a rebake can compare as an identical image. |
| The harness already has `stats`, `profile`, `steps`, `coverage`, `compare`, and `diff`. | The capture matrix needs no new image tool. It needs a `bake` command, `state.bake`, and `baked_indirect`/`probe_indirect` debug switches. |
| `docs/design/README.md` says no cached or baked lighting competes with the lamps; `world.md` says there is no texture and a baked lamp is not an alternate mode; `GLOSSARY.md` says every lamp is dynamic and the probe pass is per-frame. | The implementation and the current guide contradict each other. Revise the guide in the same change, or a review against `docs/design/review.md` must reject the work. |

The matrix assumes baked probes. If #379 rejects them, dynamic objects get no
indirect; the crate cases and the "no dark gap" bar change to a harder look.

### Design-guide conflict

The intended wording is: **no surface texture; one lighting-data texture; one
baked probe field for dynamic objects; no dynamic GI; no ambient fill.** This
keeps the signature ("flat boxes, hard shadows, coloured lamps, black unlit
surfaces") while allowing the bake. The following sentences must change in the
same change as the implementation:

- `docs/design/README.md:29-33`: "No cached or baked lighting competes with the
  lamps" and "A texture ... or a baked light ... removes it."
- `docs/design/world.md:5`: "There is no texture"; `:99`: "A static or baked lamp
  is not an alternate mode"; `:106-110`: "There is no sampler in the scene
  shader."
- `GLOSSARY.md:198-224`: `Indirect light`, `Probe`, `Probe volume`, `Probe atlas`,
  `Probe pass`, `Lamp prefab`, and `Body mode` all describe the dynamic DDGI model.
- `README.md:9-13`: "one-bounce probe GI" and "no baked global illumination."

## Metrics that mean something

Region statistics are in code values 0..255 for a colour capture and in linear
radiance for a `scene_color` capture. Use a normalized region for cross-extent
comparisons, and record the exact rect in the scenario.

| Metric | Where | What it answers | Do not use it for |
| --- | --- | --- | --- |
| `stats.mean.x/y/z` | `report.json` capture | Average level and hue in a corner, crate face, or wall patch. | Full-frame "brightness"; camera coverage dominates. |
| `stats.max` | capture | Leak ceiling and black floor. | A region that contains a lamp or an emissive face. |
| `stats.gradient` | capture | Noise and banding; compare the same region before/after. | A region with a real geometry edge; the edge raises it legitimately. |
| `coverage.zero_fraction` | capture | Exact-black fraction. | A view with the clear colour or the spider in frame. |
| `coverage.black_fraction` | capture | Fraction below a luma threshold; the leak metric. | Proving "no light at all"; it is threshold-dependent. |
| `coverage.lit_fraction` | capture | Fraction above a luma threshold; the "bounce is present" metric. | A region with direct light; it cannot separate direct from indirect. |
| `histogram` (64 bins) | capture | Comb or gap pattern from quantization. | Smoothness alone; a legitimately flat face is one spike. |
| `steps` | capture | Contour bands after a 9x9 blur; `top` names the worst jumps. | A true shadow or geometry edge; the 8-level cap is designed to exclude those. |
| `profile` | capture | A seam step or a shadow-edge width along one line. `values` is the line; `width` is the 10-90 crossing. | A whole-frame claim; one line is a local probe. |
| `compare.mean_delta` / `max_delta` / `over_16` | `compare.json`, `diff --json` | How much changed and whether it is localized. `over_16` counts pixels with any channel delta above 16. | Absolute quality. A large delta can be the correct direct-light move. |
| `capture.delta_mean` / `delta_max` / `delta_over_16` | `report.json` | Change from the previous colour capture in the same run. | Cross-run comparisons; use `compare`/`diff` for that. |
| `render_digest` | capture | Whether two frames had the same inputs. | Visual quality; a different digest can be the intended change. |
| `perf.gpu.*.p50/p95/mean` | `report.json` | Which pass owns the time and whether it fits the budget. | A single run; collect three and compare medians. Never mix `--present` with offscreen. |
| `state.bake.*` | `report.json` / `state.json` | Bake time, texels, rays, lights, bytes, invalid/dilated texels. | A frame budget; the bake is off-frame. |
| `diff.identical` | `diff --json` | Exact negative control, such as a corner that must not react to a dynamic lamp. | Any intended change; a moved lamp is not identical. |

**Capture hygiene.** Use `renderer_debug.taa=false` for measurement captures and
profiles; TAA changes exact pixels. Use TAA on and `settle until converged` for
the final look capture. Run the same command sequence and the same history for
A/B. A `png` sidecar on a `stats` capture is the full frame, not the region.

## The capture matrix

All scenarios are text files under `scenarios/`; they are part of the feature, not
a test suite. Remove the three initial lamps unless a case says otherwise; coordinates are metres and degrees. `look` is the human image;
`stats` and `profile` are the numbers. The default extent is 1280x720; repeat the
look captures at 1920x1080 for the ship review.

| # | Case | Scene and camera | Capture | Read | Reject when |
| --- | --- | --- | --- | --- | --- |
| 1 | **Static shadow** (the "baked static shadow" trap) | Wall `(0,1.5,-4)`; static fixture `(0,2.2,-1.2)` warm 4/6; crate `(0,0.5,-2.6)`; camera `(3.8,1.7,1.8)` look at `(0,1.0,-3.4)`. Move crate x 0 -> 0.6. | `look` PNG; `edge` profile across the wall shadow. | Profile `width` <= 3 px at 720p; the compare panel shows one edge, and the old edge is absent. | The old shadow remains, the edge is soft or doubled, the shadow does not move, or the crate loses its shadow. |
| 2 | **Static bounce** | Same scene. Paired run with `--renderer-debug baked_indirect=false` and default true. | `corner` stats region (normalized 0.10, 0.30, 0.30, 0.35); `lit-wall` stats; `steps`. | Corner mean delta 4..60/255; corner mean <= 0.6 x lit-wall mean; warm hue (r > g > b); no `steps.top` above 1.0 level. | Delta is 0 (no bounce), corner is as bright as the lit wall (fill), or the corner bands. |
| 3 | **Moving crate** (probe interpolation) | Same scene; crate x sweep -1.0, -0.5, 0.0, 0.5, 1.0; camera closer to the crate. | `crate` stats; `steps`; `look` per step. | Adjacent mean jump <= max(2/255, 8% of local mean); no band above 1.0 level; direct shadow moves. | A pop or a band at a 2 m cell boundary, or a visible step in the crate's indirect as it crosses a cell. |
| 4 | **Dynamic lamp, no bounce** | Sealed closet from case 7; static fixture inside `(-19.2,1.2,-1.2)` warm 4/5; camera inside `(-17.2,1.6,1.2)` look at `(-19.5,0.8,-1.5)`; dynamic lamp outside `(-14.5,1.5,0)` then `(-14.5,1.5,-1.5)`, blue 4/5. Second camera outside for the `near` pool. | `corner` stats in both lamp positions; `near` stats. | Corner `mean_delta` <= 2/255; near `mean_delta` >= 16/255. | The corner changes when only the dynamic lamp moves. That means the lamp still feeds a bake or a probe. |
| 5 | **Lamp removed** | One static fixture in the sealed closet from case 7; capture before; `remove` it; `bake wait:false`; capture `stale`; `bake wait:true`; capture `after`. | `corner` (shadowed inside corner) and `near` (directly lit inside wall) stats; `state.bake`. | `dirty` true at stale, false at after; `version` increments; corner before and stale within 2/255, after <= 2/255; direct near drops at stale. | After rebake the corner still glows; or the stale state is not visible (`dirty=false` while the hue mismatch is visible). |
| 6 | **All lights removed** | Remove `initial-lamp`, `initial-panel`, `initial-beacon`; no placed lights; bake; camera inside the wall-leak closet, away from the spider. | `black` stats region fully covered by static boxes; `look`. | `zero_fraction` = 1.0; `max` <= 1 code value for dither; HUD off. | Any pixel above the dither floor. That is an ambient fill or a stale bake. |
| 7 | **Wall / corner leak** | Closet against the west wall: front wall `(-16,1.5,0)` yaw 90; side walls `(-18,1.5,-2)` and `(-18,1.5,2)` yaw 0; ceiling Platform `(-18,3.0,0)`; static fixture inside `(-18,1.2,0)` warm 4/5; camera outside `(-14.5,1.6,0)` look at `(-16,1.5,0)`; crate outside `(-15.2,0.5,0)`. | `wall` stats on the outer face above the crate; `crate` stats; `steps`. | Wall `black_fraction` >= 0.99 at luma <= 3/255 and `max` <= 8/255; crate mean <= 6/255; no bright edge. | Static wall leak above 8/255, or dynamic crate leak above 6/255. The latter is the accepted-limit boundary, not a hidden success. |
| 8 | **Seam** | Two Blocks `(-2,0.5,0)` and `(0,0.5,0)` abutting, or the arena stairs; fixture above; close camera; paired `baked_indirect` on/off. | `seam` profile perpendicular to the joint; 4x PNG crop; atlas debug capture. | Max adjacent `profile.values` step <= 0.008 linear (about 2 code values at mid-grey) on the continuous face; a step that appears only with indirect on is the seam. No black gutter texel or 1 px line. | A line or a dark gutter at the chart edge. A hard 90-degree face edge is not a seam. |
| 9 | **Stale bake** | One warm static fixture; capture `baked`; tint it green; `bake wait:false`; capture `stale`; `bake wait:true`; capture `rebaked`. | `corner` stats; `look`; `state.bake`. | `dirty` true at stale; direct is green while the corner stays warm; after rebake the corner r/g ratio moves by at least 10% and the corner mean changes by at least 3/255. | A final capture is taken while dirty; or the dirty state is false while the mismatch is visible. |
| 10 | **96 lights** | `renderer_debug.synthetic_lights=96`; shadows on; bake empty (no static fixtures); default and arena cameras; 1920x1080. | `lit` look; `frame` stats; `perf` 120 frames, 60 warmup. | `light_count` 96; `cluster_overflow` 0; `perf.gpu.probe` absent or zero; total within budget; no `steps.top` band. | Cluster overflow, a probe pass, banding, or a frame over budget. |
| 11 | **Bake cost** | A scene with the three starting fixtures plus the arena geometry; `bake wait:true`; capture. | `state.bake`; `look`. | `ms` inside budget; `texels`, `rays`, `lights`, `atlas_bytes`, `probe_bytes` reported; `invalid_texels` and `dilated_texels` plausible; no `error`. | A missing field, an error, or a bake over budget. |

### Scenario contract

`body: "static"` on a lamp is the planned authoring form; #379 owns the final
field name. The implementation adds the `bake` command and `state.bake`; without
them the matrix cannot separate "stale" from "current." A stale capture needs a
way to observe the old bake: the simplest contract is `bake wait:false` marks
dirty without publishing, `bake wait:true` publishes, and edits never auto-bake.
The exact `stats` rects and `profile` ranges are tuned once and committed in the
scenario.

```json
{
  "requires": {"renderer_debug": true},
  "view": {"hud": false, "debug": false, "hint": false, "perf": false},
  "commands": [
    {"cmd": "remove", "name": "initial-lamp"},
    {"cmd": "remove", "name": "initial-panel"},
    {"cmd": "remove", "name": "initial-beacon"},
    {"cmd": "place", "prefab": "Wall", "position": [0, 1.5, -4], "name": "back-wall"},
    {"cmd": "place", "prefab": "Lamp", "position": [0, 2.2, -1.2], "body": "static",
     "name": "key", "light": {"color": "warm", "intensity": 4.0, "range": 6.0}},
    {"cmd": "place", "prefab": "Crate", "position": [0, 0.5, -2.6], "name": "crate"},
    {"cmd": "camera", "position": [3.8, 1.7, 1.8], "look_at": [0, 1.0, -3.4]},
    {"cmd": "renderer_debug", "taa": false},
    {"cmd": "bake", "wait": true},
    {"cmd": "captures", "outputs": [
      {"name": "corner", "format": "stats", "region": {"unit": "normalized", "x": 0.10, "y": 0.30, "w": 0.30, "h": 0.35},
       "coverage": {"black": 3, "lit": 8}, "steps": {"blur": 9, "min": 0.5, "max": 8}},
      {"name": "look", "format": "png"}
    ]}
  ]
}
```

### Exact commands

`bake`, `state.bake`, `baked_indirect`, and `probe_indirect` land with the implementation; the rest runs on the current harness.

```sh
tools/make.sh agent
for s in static-shadow static-bounce crate-move dynamic-lamp lamp-removed all-off wall-leak seam stale; do
  ./bin/harbagsa-agent run "future-scenario/lighting-$s.json" --out "runs/lighting/$s"
done
./bin/harbagsa-agent run future-scenario/lighting-static-bounce.json --renderer-debug baked_indirect=false --out runs/lighting/static-bounce/off
./bin/harbagsa-agent run future-scenario/lighting-static-bounce.json --out runs/lighting/static-bounce/on
./bin/harbagsa-agent compare runs/lighting/static-bounce/off runs/lighting/static-bounce/on --delta --out runs/lighting/static-bounce/compare
./bin/harbagsa-agent run future-scenario/lighting-dynamic-lamp.json --param lamp_z=0,-1.5 --out runs/lighting/dynamic-lamp
./bin/harbagsa-agent compare runs/lighting/dynamic-lamp/lamp_z_0 runs/lighting/dynamic-lamp/lamp_z_-1.5 --delta --out runs/lighting/dynamic-lamp/compare
./bin/harbagsa-agent run future-scenario/lighting-crate-move.json --param crate_x=-1.0,-0.5,0.0,0.5,1.0 --out runs/lighting/crate-move
./bin/harbagsa-agent run future-scenario/lighting-perf-96.json --size 1920x1080 --out runs/lighting/perf-96
for i in 1 2 3; do ./bin/harbagsa-agent run future-scenario/lighting-bake.json --out "runs/lighting/bake-$i"; done
```

Read the evidence with `jq` (text only; no images leave `runs/`):

```sh
jq '.state.bake' runs/lighting/bake-1/report.json
jq '.perf[] | {name, p50: .interval.p50, p95: .interval.p95, gpu: .gpu}' runs/lighting/perf-96/report.json
jq -r '.captures[] | select(.name=="wall") | [.stats.mean.x, .stats.mean.y, .stats.mean.z, .stats.coverage.black_fraction] | @tsv' runs/lighting/wall-leak/report.json
```

Do not use `diff --max-pixels`. It turns the review into an assertion gate.

## Performance matrix and commands

| Run | Scenario | Extent | What it answers |
| --- | --- | --- | --- |
| Baseline, pre-change | `scenarios/perf.json` | 1920x1080 | The actual before number on this machine, with DDGI. |
| Baseline, arena view | `scenarios/perf-arena.json` | 1920x1080 | A second view; checks that the win is not camera-specific. |
| Mixed, default view | `scenarios/perf.json` | 1920x1080 | The after number; compare medians with the pre-change baseline. |
| Mixed, 96 lights | `future-scenario/lighting-perf-96.json` | 1920x1080 | Cluster overflow, direct-shadow cost, lightmap fetch under load. |
| Mixed, indirect off | same 96-light scenario with `baked_indirect=false` | 1920x1080 | The lightmap sample cost: scene pass delta between the pair. |
| Mixed, gather off | same view with `probe_indirect=false` | 1920x1080 | The remaining dynamic-probe gather cost. |
| Bake | `future-scenario/lighting-bake.json` | n/a | Bake milliseconds, texels, rays, lights, bytes. |
| Paired A/B | `tools/ab.sh --ref origin/main` | 1920x1080 | Interleaved medians and ratios; the strongest perf evidence. |

```sh
tools/ab.sh --ref origin/main --scenario scenarios/perf.json --scenario scenarios/perf-arena.json --size 1920x1080 --runs 3 --out runs/lighting/ab-perf
./bin/harbagsa-agent run future-scenario/lighting-perf-96.json --size 1920x1080 --out runs/lighting/perf-96
./bin/harbagsa-agent run future-scenario/lighting-perf-96.json --size 1920x1080 --renderer-debug baked_indirect=false --out runs/lighting/perf-96-no-indirect
./bin/harbagsa-agent run future-scenario/lighting-perf-96.json --size 1920x1080 --renderer-debug probe_indirect=false --out runs/lighting/perf-96-no-gather
```

Inspect `runs/lighting/ab-perf/summary.md` and `summary.json`; in the
`perf-96` reports inspect `perf[].gpu.probe`, `perf[].gpu.scene`,
`perf[].gpu.total`, and `state.renderer.cluster_overflow`.

## Budgets

### Runtime, 1080p, 96 lights

The honest split:

- The **probe update** pass disappears. That is about 0.76 ms at 96 lights and
  1080p ([ADR 0042](../adr/0042-single-volume-ddgi.md)).
- The **probe gather** remains for dynamic objects. It was about 0.58 ms across
  the whole frame; after the change it applies only to dynamic fragments. The
  saving is the update pass plus the static share of the gather.
- The **lightmap fetch** is one sampled image, one face-rect lookup, and a
  static/dynamic branch. It is added to the scene pass.

Measured against a fresh baseline on the RX 9060 XT / RADV GFX1200 at the same extent:

- Static-heavy view: total `p50` at least **1.0 ms lower** than the current DDGI
  build; dynamic-heavy view (spider close-up): at least **0.5 ms lower**. The
  published 5.94 ms direct-shadow figure predates DDGI
  ([ADR 0040](../adr/0040-hard-point-light-shadows.md)).
- Lightmap sampling adds **<= 0.25 ms mean** to the scene pass at 1080p; the
  fetch alone **<= 0.15 ms**. The dynamic probe gather stays **<= 0.25 ms** on a
  normal view and **<= 0.58 ms** on a dynamic-heavy view. Measure both by paired
  `baked_indirect` / `probe_indirect` runs on the same 96-light view.
- `perf.gpu.probe` is absent (or exactly zero). If present and non-zero, DDGI was
  not removed and the run is not mixed-lighting evidence.
- `cluster_overflow` is 0 at 96 lights. `p95` more than 15% above p50 is a
  stability smell, not an automatic rejection. Record 720p and 1440p; set an
  absolute ceiling only after a baseline exists at those extents.

### Memory

| Item | Budget | Note |
| --- | --- | --- |
| Lightmap atlas | 32 MiB | 2048 x 2048 RGBA16F, uncompressed. |
| Baked probe field | <= 4 MiB | 1200 probes x 64 texels x 8 B x 2 maps, one or two copies. The old field was about 6 MB for two in-flight buffers (ADR 0042). |
| Face/slot buffers | < 1 MiB | 512 slots x 6 rects x 16 B plus slot data. |
| Transient bake staging | <= 128 MiB CPU | One float atlas plus ray/sample scratch; stream, do not hold all rays. |
| Persistent new GPU total | <= 40 MiB | Atlas + probes + buffers, excluding driver overhead. |
| Optional BC6H atlas | 4 MiB | Only after a float capture is clean and a BC6H capture is indistinguishable. |

The net memory change is an increase: a 32 MiB atlas is added while the old
roughly 6 MB probe field shrinks to about 2-4 MB. State it in the spec. Unreal's
Volumetric Lightmap went from 5 MB to 30 MB on the Paragon map at default
settings, the same order of increase
([Volumetric Lightmaps](https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-lightmaps-in-unreal-engine)).

### Bake

The default is 4 texels/m, 64 rays, one bounce. The arena has roughly
4,000-4,500 m2 of relevant static face area (40 x 40 floor and ceiling, four
40 x 5.5 walls, props), or about 70k texels at 4/m. At 64 rays that is about
4.5M rays. The current probe pass does 76.8k rays in about 0.76 ms (ADR 0042),
so the raw ray cost is on the order of 45 ms; hit shading, invalidity, dilation,
readback, and upload make the end-to-end bake larger. **This is an
order-of-magnitude estimate, not a measurement.** The first implementation must
replace it with `state.bake.ms`.

| Bake item | Budget | Note |
| --- | --- | --- |
| Default end-to-end bake | <= 500 ms | 4 texels/m, 64 rays, one bounce, all arena static boxes, 3 starting fixtures. |
| High-quality bake | <= 1500 ms | 8 texels/m and/or 128 rays; a measured option, not the default. |
| Bake lights | <= 16 static fixtures | The frame still handles 96 lights; dynamic lamps never enter the bake. The 500 ms budget assumes 3 fixtures; at 16, range-cull per texel and report `bake_lights`. |
| Operations | cold + warm, no frame impact, startup <= 2 s | Report the cold run separately; keep the bake outside the measured 120-frame window. A startup bake failure is a renderer-init failure (exit 3), not a black frame. |
| Failure policy | old bake + visible state | Keep the previous bake, set `bake.dirty`/`bake.error`, show it in the overlay and state. Never silently fall back to black or to an old bake that claims current. |

## Failure versus accepted limitation

| Failure | Why it is not acceptable |
| --- | --- |
| A static surface glows on the dark side of a closed wall. | It breaks the closed-room model and is visible in normal play. Static lightmaps have no transport excuse. |
| A continuous face shows a thin line, a 4x4 block, or a dark gutter. | It reads as a texture and breaks the flat-face signature. |
| A static fixture's shadow stays after the crate moves, or is soft/blurred. | Direct or shadow was baked. This is the exact thing the mixed model forbids. |
| A dynamic lamp changes a corner it cannot see. | The lamp still feeds the bake or the probe field. That is dynamic GI by another name. |
| A final capture is taken while `bake.dirty=true`, or the state claims current while direct and bounce disagree. | The evidence is lying. A stale window is acceptable only when it is visible and marked. |
| Lamp-free interior is not black. | An ambient floor, a stale bake, or a clear-colour leak. [ADR 0041](../adr/0041-absolute-darkness.md)'s absolute darkness is still in force. |
| A crate pops or bands as it crosses a probe cell. | The probe field is the product for dynamic objects; a visible cell boundary is a quality failure, not a stylized choice. |
| The 96-light run overflows clusters, shows a probe pass, or misses the perf budget. | The renderer contract and the performance reason for the change both fail. |
| An unbaked static box renders black with no state. | The failure is hidden. Use probe indirect plus `bake_missing`, or fail loudly. |

| Accepted limitation | How it is documented |
| --- | --- |
| Dynamic lamps give no bounce. | `docs/design/world.md`, `GLOSSARY.md`, README. A moving lamp's corner stays darker; do not add a fill. |
| A moving crate leaves no indirect shadow on the wall. | Design guide. The real-time direct shadow grounds it; the wall's baked bounce ignores the crate. |
| A dynamic object near a 0.5 m wall can pick up up to 6/255 of the other side's bounce. | Design guide + evidence note. This is the probe-spacing limit; fix by thickening or invalidating, not by hiding. |
| The probe field is 2 m; a large dynamic object can have a flat or slightly wrong bounce across its face. | Design guide. Per-pixel gather is already better than per-object; a denser grid is a later decision. |
| A static fixture edit is not visually correct until the rebake publishes. | Design guide + overlay/state. The stale window is visible and timed. |
| One bounce only; no AO, no contact darkening, no colour bleed beyond the first bounce. | Design guide. The look is flat and stylized, not photoreal. |
| The spider's emissive eyes and markings no longer bounce because the spider is dynamic. | Design guide + GLOSSARY. If the owner wants that bounce, the spider would need a static proxy or a different rule; do not sneak it into the bake. |
| No tone map, no specular, no bloom. | Already the design. The lightmap is lighting data, not a material. |
| TAA history resets for one frame after a bake publish. | Technical note. A one-frame reset is better than a smeared stale image. |

## What belongs in the repository without committing images

Commit:

- The scenario JSON files (`future-scenario/lighting-*.json`) and this note.
- A text evidence log, for example `docs/evidence/lighting-2026-10-28.md`, with
  commit, dirty flag, machine, driver, extent, scenario, command, run directory,
  the key numbers, and the reviewer verdict.
- The design-guide, glossary, README, and ADR updates.

Do not commit:

- PNG, float, raw, `compare.png`, atlas dumps, `trace.jsonl`, or `report.json`.
- A run directory. `runs/` is ignored; a reader reproduces it from the scenario
  and command.

The evidence log is the durable text artifact. If a run directory is gone, rerun the scenario; do not paste a screenshot into the repository.

## Open decisions for the owner

1. **Quality and budget basis.** Accept these as review triggers, not gates, and
   judge the frame against a fresh `perf.json` baseline (relative win: 1.0 ms
   static-heavy, 0.5 ms dynamic-heavy). Recommendation: yes; an absolute number
   from ADR 0040 predates DDGI and would mislead.
2. **Atlas and probes.** 2048 square at 4 texels/m, RGBA16F, no compression;
   keep the 2 m probe grid. Recommendation: yes; 4096, 8 texels/m, BC6H, and a
   1 m grid are measured options, not the first version.
3. **Thin-wall leak.** Accept a dynamic leak up to 6/255; invalidate probes inside
   geometry and dilate. Recommendation: yes, with the cap in the design guide;
   rendering-layer masks are a later tool.
4. **Fixture edits and bake trigger.** Allow live direct changes, show
   `bake.dirty`, and rebake at commit. Blocking startup bake; never per-frame.
   Recommendation: yes.
5. **Bake light cap and fallback.** Target 16 static fixtures, report
   `bake_lights`, range-cull if the count grows; an unbaked static box falls back
   to probe indirect plus `bake_missing`, never black. Recommendation: yes.
6. **Spider emissive.** Accept that the eyes and markings do not bounce.
   Recommendation: yes; a static proxy is overkill.
7. **Harness contract.** Add `bake` (`wait` bool), `state.bake`, `baked_indirect`
   and `probe_indirect` overrides, and a debug atlas capture. Recommendation:
   add them in the implementation change; the matrix depends on them.
8. **Design-guide revision.** Approve "no surface texture; one lighting-data
   texture; one baked probe field; no dynamic GI; no ambient fill" before the
   first visual review. Otherwise the review is against a document that rejects
   the feature.
9. **Evidence owner.** Name the person who signs the evidence log and the run
   directory. Recommendation: owner plus the renderer reviewer; one sign-off.

## Primary sources

The inline links above are the sources. The load-bearing ones:
[Unity Light Modes](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting-light-sources/components/configuring/light-modes/introduction),
[Unity Mixed runtime](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting-light-sources/components/configuring/lighting-mode/runtime),
[Unity lightmap artifacts](https://docs.unity.com/en-us/engine/6000.7/manual/lighting-overview/direct-and-indirect-lighting/lightmapping/baking-before-runtime/troubleshooting/troubleshooting-lightmapping-artifacts),
[Unity light leaking](https://docs.unity.com/en-us/engine/6000.5/manual/lighting-overview/direct-and-indirect-lighting/lightmapping/baking-before-runtime/troubleshooting/troubleshooting-lightmapping-leaking),
[Unity Light Probes](https://docs.unity.com/engine/6000.6/manual/lighting-overview/direct-and-indirect-lighting/light-probes/troubleshooting),
[Unity APV leaks](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting/probevolumes/fixissues/troubleshoot-light-leaks),
[Unreal lightmapping](https://dev.epicgames.com/documentation/en-us/unreal-engine/understanding-lightmapping-in-unreal-engine), [Unreal Volumetric Lightmaps](https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-lightmaps-in-unreal-engine),
[Unreal Stationary](https://dev.epicgames.com/documentation/en-us/unreal-engine/stationary-light-mobility-in-unreal-engine),
[Anomaly 2](https://knarkowicz.wordpress.com/2014/07/20/lightmapping-in-anomaly-2-mobile/),
[The Witness](https://www.the-witness.net/news/2010/04/graphics-tech-multi-lightmaps/),
[TF2](https://wiki.teamfortress.com/wiki/Illustrative_Rendering_in_Team_Fortress_2),
[BC6H](https://learn.microsoft.com/en-us/windows/win32/direct3d11/bc6h-format).
