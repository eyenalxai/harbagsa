# Baked probes for dynamic objects

Status: research for #373. No renderer code changes. This note assumes the mixed-lighting model from `docs/research/mixed-lighting.md`: static fixtures keep real-time direct light and hard shadows and bake only their indirect bounce; dynamic lamps keep real-time direct light and hard shadows and bake nothing. Static surfaces read the lightmap atlas from `docs/research/lightmap-boxes.md`; dynamic objects read the probe layer described here.

## Bottom line

Keep the **octahedral irradiance atlas with depth moments**, but make it a **baked asset** and change the runtime probe selection from trilinear over eight probes to **tetrahedral over four probes**:

- One probe volume covers the closed arena: `min = [-20, -0.5, -20]`, **1 m spacing**, counts **40 x 5 x 40 = 8000 probes**. Probes sit at `y = 0.5, 1.5, 2.5, 3.5, 4.5`.
- Each probe stores the current 8 x 8 octahedral irradiance map plus first and second depth moments, but the data is written once by the bake, never by a frame pass. Stored as RGBA16F irradiance and RG16F moments, one probe is 768 B; 8000 probes are about 6.1 MB.
- Runtime selects the four probes of the containing tetrahedron, samples each probe's octa map along the surface normal, applies the current facing and Chebyshev depth tests, and renormalizes. The result is per-pixel, not per-object, so a crate crossing a light gradient does not pop.
- Probe validity is computed from **static geometry only**. A dynamic crate must not invalidate a probe. Invalid probes are moved out of geometry by a virtual offset where possible, then filled by dilation; the valid flag and offset are baked data.
- Bake 1024 rays per probe. The 8 x 8 map then receives about 16 rays per texel, which is enough for a low-frequency diffuse field. The probe layer is independent of the lightmap bake and can be rebaked with it.

This is still consistent with "no DDGI" because the field is static: no probe ray pass, no temporal blend, no hysteresis, no per-frame update, no dynamic light in the bake. It is a baked light-probe volume, not a dynamic irradiance field. The owner's map already treats a baked probe layer as a separate, static feature (#370).

Budget note: the sibling quality note tentatively caps the probe field at 4 MiB and assumes 1200 probes; this 1 m/8 x 8 layout is 6.2 MB. If that cap is fixed, use 2 m (0.9 MB) or 1 m/4 x 4 (1.6 MB). The 1 m grid is the quality recommendation, not a hard budget.

## Known representations

The irradiance-volume paper is the origin of the volumetric grid of directional irradiance samples ([Greger et al.](https://gene.greger-weltin.org/professional/publications/irradiance_volume_ieee.html)); diffuse irradiance is low-frequency enough that nine SH coefficients approximate it to about 1% average error ([Ramamoorthi and Hanrahan](https://cseweb.ucsd.edu/~ravir/papers/envmap/envmap.pdf)). Those two facts are why a coarse grid of directional probes is the right family for this scene, and why the argument is about interpolation and leak control, not about angular resolution.

| Representation | Storage | Sampling | Strength | Weakness for this game |
| --- | --- | --- | --- | --- |
| Constant ambient per object | 3 floats | None | Cheapest | No spatial or directional gradient; Unity's LPPV doc says a single probe gives constant ambient across a large object ([LPPV](https://docs.unity3d.com/6000.0/Documentation/Manual/class-LightProbeProxyVolume.html)) |
| L2 spherical-harmonic probes | 27 floats per probe, 9 per channel ([Unity probe format](https://docs.unity3d.com/6000.0/Documentation/Manual/LightProbes-TechnicalInformation.html)) | Tetrahedral over four probes; Unity's moving-object doc says the nearest probes form a tetrahedron and the object is interpolated from its four points ([Unity](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/direct-and-indirect-lighting/light-probes/moving-objects)) | Standard, compact, smooth, per-pixel with APV/LPPV | No direction-dependent visibility; SH ringing near sharp light/dark transitions ([Unity troubleshooting](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/direct-and-indirect-lighting/light-probes/troubleshooting)); Unreal adds SH de-ringing smoothing to its volumetric lightmap ([VLM](https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-lightmaps-in-unreal-engine)) |
| Octahedral irradiance atlas + depth moments | 8 x 8 RGBA16F + 8 x 8 RG moments per probe | Sample octa along normal, blend probes, Chebyshev depth test | Direction-dependent leak test; no SH ringing; already in this renderer | Larger than L2 SH; depth moments must be baked and maintained; octa seams if the map is too small |
| Adaptive Probe Volume (APV) | 4 x 4 x 4 probe bricks; default spacing 1, 3, 9, or 27 m ([APV concept](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting/probevolumes/concept)) | Per-pixel; each pixel samples the eight closest probes ([APV concept](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting/probevolumes/concept)) | Automatic density near geometry, streaming, scenarios, virtual offset, dilation, rendering layers | The machinery is for large multi-room worlds; this game has one 40 m room; no streaming, multiple bakes, or light-probe groups |
| Unreal Volumetric Lightmap (VLM) | Bricks of 4 x 4 x 4 cells; third-order SH per cell; higher density near geometry ([VLM](https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-lightmaps-in-unreal-engine)) | Per-pixel interpolation; border texels clamp outside the importance volume ([VLM](https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-lightmaps-in-unreal-engine)) | Battle-tested for movable characters; per-pixel; no per-object CPU interpolation | Tied to the lightmap bake and importance volume; its own docs say wall leaks are fixed only by smaller cells or thicker walls ([VLM troubleshooting](https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-lightmaps-in-unreal-engine)) |
| Volumetric 3D texture of SH (LPPV) | 3D texture of interpolated SH coefficients ([LPPV](https://docs.unity3d.com/6000.0/Documentation/Manual/class-LightProbeProxyVolume.html)) | Per-pixel sample of the 3D texture | Spatial gradient on one large dynamic object; 16/32-bit float filtering is enough ([LPPV](https://docs.unity3d.com/6000.0/Documentation/Manual/class-LightProbeProxyVolume.html)) | A 3D texture is a different binding and format; the probe grid already gives the same gradient without a texture |

The classic probe failure is also documented in the DDGI paper: irradiance probes leak where visibility is undersampled, which is why DDGI adds a visibility-aware moment-based interpolant ([Majercik et al.](https://jcgt.org/published/0008/02/01/paper.pdf)). The existing harbagsa field already has that moment test, so the bake should preserve it rather than replace it with SH.

## Recommended data contract

```text
Probe_Volume {
  min: [3]f32; spacing: f32; counts: [3]u32
}
Probe_Header {
  volume: Probe_Volume
  probe_count: u32
  texels: u32        // 64 for 8 x 8
  flags_bytes: u32
}
Probe_Texel {
  irradiance: [4]f16 // gamma 5 encoded, alpha unused
  moments: [2]f16    // E[d], E[d^2]
}
Probe_State {
  valid: u8
  offset: [3]f16     // virtual offset from the grid position, in metres
}
```

The probe grid is regular, so the position is derived from `volume` and the index; do not store a position per probe. The current code stores positions only because it rebuilds them from the live box list every frame (`src/renderer/probe_validity.odin:47-72`); a baked volume has no such need.

The runtime budget is four probes, each with one octa bilinear sample and one depth bilinear sample. That is 4 x 4 irradiance fetches and 4 x 4 moment fetches, versus eight probes in the current gather (`src/renderer/shaders/probe_gather.glsl:83-143`). Tetrahedral selection reduces both the fetch count and the number of leak paths.

## Placement and resolution

- **1 m uniform spacing** is the recommendation. The DDGI paper recommends 1-2 m for human-scale scenes and at least one full grid cage in every room-like space ([DDGI](https://jcgt.org/published/0008/02/01/paper.pdf)). The arena has 3 m wide tunnels, 2.5 m wide stairs/ramps, and 0.5 m walls; a 2 m grid does not put a full cage inside a tunnel. Unity APV's default spacing starts at 1 m and increases in open areas ([APV density](https://docs.unity3d.com/6000.0/Documentation/Manual/urp/probevolumes-changedensity.html)); 1 m is the same starting point without adaptive bricks.
- **40 x 5 x 40** covers the 40 m square and the 0.5-5.5 m interior. The current 20 x 3 x 20 grid at 2 m is the fallback if probe memory or bake time is a problem; it is 1200 probes and about 0.9 MB.
- A probe is **invalid** if its center is inside any static box, using the same oriented-box test as `point_inside_boxes` but with the static box list only. The current code passes every box, including crates (`src/renderer/probe_validity.odin:47-72`); a moving crate must not change the baked field.
- A probe is also invalid if too many of its bake rays hit backfaces. Unity exposes this as `Backface Tolerance` for lightmaps and marks probes invalid when their sampling rays hit unlit backfaces inside geometry ([Lightmap Parameters](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting-reference/class-lightmap-parameters), [APV validity](https://docs.unity3d.com/6000.0/Documentation/Manual/urp/probevolumes-light-probe-validity.html)). Start at 100% front-face tolerance: a probe with any backface hit is suspect; relax only if captures show dark blotches.
- **Virtual offset** pushes an invalid probe's capture point out of the nearest static box along the average backface normal, up to about half the probe spacing. Unity documents the same technique, including ray length, move distance, ray origin bias, and a hit-count limit ([APV artefacts](https://docs.unity3d.com/6000.0/Documentation/Manual/urp/probevolumes-troubleshoot-artefacts.html)).
- **Dilation** fills probes that remain invalid from nearby valid probes, weighted by distance; store the valid flag so the runtime can skip a probe whose dilated value is not trustworthy. Unity's dilation is a bake-time operation with a search radius, iteration count, and weighting ([APV artefacts](https://docs.unity3d.com/6000.0/Documentation/Manual/urp/probevolumes-troubleshoot-artefacts.html)).
- There is no per-room volume list. The arena is closed; one volume is enough. If a second room is added, add a second volume rather than growing the first.

## Sampling

**Tetrahedral, not trilinear, over the probe grid.** A regular grid cell can be split into six tetrahedra by ordering the fractional coordinates; the runtime picks the tetrahedron and uses four barycentric weights. This is the same four-point interpolation Unity uses for moving objects ([Unity](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/direct-and-indirect-lighting/light-probes/moving-objects)). It has three advantages: four probes instead of eight, no negative weights, and a smaller set of probes that can leak across a wall.

The lookup is:

```text
p = world position + normal * normal_bias
cell, fraction = volume cell containing p
tetra = select_tetrahedron(fraction)         // 4 corner indices, 4 weights
for each corner:
  if invalid and no dilated value: skip
  direction = normalize(corner_position - p)
  facing = max(dot(-direction, normal), 0)
  weight *= facing^2
  weight *= chebyshev(distance, moments(direction))
sample each probe's octa map along the normal
renormalize weights; if none, return zero
```

- **Normal bias** moves the sample point along the surface normal before the cell lookup. Unity exposes this as `Normal Bias`, scaled by probe spacing ([APV options](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting/probevolumes/options-override-reference)). Start at 0.1 x spacing (0.1 m) and tune with captures. Without it, a crate touching a wall samples probes inside the wall.
- **Facing weight** is the current `max(dot(to_probe, normal), 0)^2` (`src/renderer/shaders/probe_gather.glsl:111-115`). Keep it. It is a cheap normal-weighting term and it rejects probes behind the surface. Unity's `Min Valid Dot Product` is the same idea with a threshold ([APV options](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting/probevolumes/options-override-reference)).
- **Depth moments** are the current first/second moment Chebyshev test with a bias of `max(0.05, spacing * 0.05)` (`src/renderer/shaders/probe_gather.glsl:117-132`). Keep it. This is the main advantage over L2 SH: the test is direction-dependent, so a probe on the far side of a wall can be rejected even when the tetrahedron crosses the wall.
- **No runtime backface ray, no visibility ray, no screen-space test.** The bake does the visibility work; the fragment shader only reads baked data.
- **Clamp to the volume** and return zero outside it. The arena is closed, so a dynamic object outside the volume is a bug; report `probe_missing` in the renderer state rather than silently returning black.

### Why not L2 SH now

L2 SH is the smaller and more standard representation, and Unreal's VLM uses third-order SH ([VLM](https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-lightmaps-in-unreal-engine)). It is rejected for the first version because it loses the direction-dependent depth test that currently controls leaks, and because SH ringing is a known artifact near sharp light/dark boundaries ([Unity troubleshooting](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/direct-and-indirect-lighting/light-probes/troubleshooting)). The octa atlas is already implemented and already produces the look the owner knows. If memory or runtime sampling becomes the constraint, L2 SH is the first measured alternative, not a blind replacement.

### Smallest representation that meets the look

| Variant | Per probe | Total | Comment |
| --- | --- | --- | --- |
| 2 m, 4 x 4 octa + moments | 192 B | 0.24 MB (1200 probes) | Cheapest; too coarse for tunnels and thin walls |
| 1 m, 4 x 4 octa + moments | 192 B | 1.54 MB | Plausible reduction; 4 x 4 is the floor for a normal-directed lookup |
| 1 m, 8 x 8 octa + moments | 768 B | 6.14 MB | Recommended baseline; same angular resolution as today |
| 2 m, 8 x 8 octa + moments | 768 B | 0.92 MB | Current DDGI grid; fallback if bake time matters |

The 8 x 8 map is the smallest map that keeps the current leak test and the current look at the same angular resolution. Do not go below 4 x 4: the octa lookup becomes a single bilinear patch and the depth test loses the angular resolution that makes it useful.

## Bake from static fixtures only

The probe bake is a second output of the same static bake as the lightmap:

- **Sources:** static fixtures (point light position, color, intensity, range) and static emissive boxes. Exclude dynamic lamps, dynamic crates, the spider, and the camera. A miss returns zero; there is no sky or ambient term. Unreal's character lighting samples capture indirect light but not direct light ([CPU Lightmass](https://dev.epicgames.com/documentation/en-us/unreal-engine/cpu-lightmass-global-illumination-in-unreal-engine)), which is the same split: the probe stores bounce, not the receiver's direct light.
- **Hit shade:** `albedo * (direct_from_static_fixtures + emissive)`, using the same point-light falloff and hard-shadow test as the lit pass. The current probe ray does exactly this (`src/renderer/shaders/probe_ray.comp:82-155`); the bake should share the formula, not reimplement a second lighting model.
- **One bounce.** A hit is shaded but not traced further. One bounce is enough for the flat box look and matches the current field.
- **Backface hits** contribute zero radiance but still occlude. The current code stores a negative distance for a backface and excludes it from the irradiance sum while keeping it in the depth moments (`src/renderer/shaders/probe_ray.comp:116,153`); keep that rule.
- **Self-emission:** a static emissive box is a source and a reflector. It must not add its own emission back onto its own probe values; the lit pass already adds the emissive self term (`src/renderer/shaders/box.frag:154`).
- **Fixture body emission:** the starting lamps are emissive boxes with a point light. Counting both the body emission and the point light doubles the fixture's contribution. This is the open double-count question from #371; do not silently pick one. The probe bake should take the same policy as the lightmap bake.
- **Static-only box list:** the bake must not include dynamic crates, because a pushed crate would change the baked field. Exclude them from the static box list, the validity test, and the ray casts.
- **Bake rays:** 1024 per probe, fixed spherical Fibonacci directions with a per-probe rotation derived from the bake key. The current fixed set is the same for every probe (`src/renderer/shaders/probe.glsl:44-53`), which produces structured banding; rotate the set per probe (Cranley-Patterson) and keep it deterministic. Use a hash-based per-probe seed rather than a global random stream so probes can bake in parallel without an order dependency.
- **Depth moments:** store first and second moments as RG16F. The current shader stores two f32; f16 is enough for a 40 m room and halves the probe memory. Keep the distance exponent at 50 (`src/renderer/probe.odin:13`).

## What happens when a dynamic object moves

A dynamic object never reads the lightmap. It reads the probe field at its fragment position, so it can move through a baked lightmap region without a per-object bake, a lightmap seam, or a rebake. This is exactly the split Unity documents: moving objects cannot use lightmaps and receive bounced light only from light probes ([Unity](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/direct-and-indirect-lighting/light-probes/moving-objects)). As the crate crosses a cell boundary, tetrahedral weights change continuously; the value is continuous if the same probe values are used. The derivative can change at a tetrahedron face, which is not visible on a flat-shaded box.

The accepted limitation is that the crate does not occlude static indirect light: the floor's baked value ignores the crate, and the crate's own probe value ignores its own shadow on the floor. Its real-time direct shadow still grounds it. Adding dynamic occlusion would be dynamic GI by another name and would invalidate the bake every frame.

If a dynamic object is flipped to static, it needs a lightmap tile and a rebake; it must not keep reading probes as a static surface. That is a `bake_key` change and belongs to #374 and #377, not to the probe runtime.

## Consistency with "no DDGI"

| Property | DDGI (current) | Baked probes (this note) |
| --- | --- | --- |
| Probe rays | Every frame | Once per bake |
| Probe blend / hysteresis | Every frame, temporal | None; values are final |
| Dynamic lights | Included | Excluded |
| Dynamic occluders | Change the field | Ignored |
| Probe pass in `PASS_ORDER` | Yes (`src/perf/perf.odin:19-50`) | Removed |
| `gi` debug switch | Yes | Replaced by a baked-indirect switch or removed |
| Data lifetime | Per-frame buffers, two in flight | One static asset, plus a rebake publish |

A static probe volume is not DDGI. The owner's requirement is about the per-frame field, not about the existence of baked probes; #370 says a baked probe layer is a separate, static feature. The glossary should say **baked probe volume** and should not call it DDGI.

## Probes versus no dynamic-object indirect

| | No probes | Baked probes |
| --- | --- | --- |
| Dynamic crate under a static fixture | Direct light + emissive only; the side facing away from the lamp is flat and uncolored | Direct light + static bounce; the crate picks up floor/wall color |
| Corner near a static fixture | Static surfaces get lightmap bounce; the crate does not | Crate and static surface agree on the same bounce source |
| Runtime cost | None | 4 probes x (4 octa + 4 depth) taps per fragment |
| Memory | None | 1.5-6.1 MB at 1 m; 0.2-0.9 MB at 2 m |
| Bake cost | None | 8.2M probe rays at 1024 rays/probe |
| Main artifact | Crate looks pasted into the room; no color bleed | Probe leak through thin walls; crate does not occlude indirect |
| Verdict | The budget fallback, not the target | Recommended |

The no-probe option is acceptable only if the owner accepts a flat, uncolored crate. Unity's own example shows the moving object staying flat grey without probes ([Unity](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/direct-and-indirect-lighting/light-probes/moving-objects)). For a mixed-lighting target that explicitly wants static bounce, probes are the minimum.

## Memory and bake cost

Assumptions: 8 x 8 octa, RGBA16F irradiance, RG16F moments, 8 B + 4 B per texel; probe flags and offsets are 8 B per probe. Estimates, not measurements.

| Layout | Probes | Irradiance | Moments | Flags | Total |
| --- | --- | --- | --- | --- | --- |
| 1 m, 8 x 8 | 8000 | 4.10 MB | 2.05 MB | 0.06 MB | **6.20 MB** |
| 1 m, 4 x 4 | 8000 | 1.02 MB | 0.51 MB | 0.06 MB | **1.60 MB** |
| 2 m, 8 x 8 | 1200 | 0.61 MB | 0.31 MB | 0.01 MB | **0.93 MB** |
| 2 m, 4 x 4 | 1200 | 0.15 MB | 0.08 MB | 0.01 MB | **0.24 MB** |

Bake rays: 8000 x 1024 = 8.2M primary probe rays. With three static fixtures, each hit can test up to three shadow rays, so plan for roughly 25M rays. On a 52-box arena, an OBB caster with a BVH should finish in seconds on a desktop CPU; the lightmap bake in #374 is the larger share. Bake time is a build or rebake cost, not a frame cost.

## Known artifacts

| Artifact | Cause | Control |
| --- | --- | --- |
| Probe leak through a 0.5 m wall | A tetrahedron crosses the wall; a probe on the far side contributes | Depth moments; 1 m spacing; normal bias; invalid/dilated probes; if a specific wall still leaks, mark a thin band of probes invalid and dilate, or thicken the wall (Unreal's own VLM advice is smaller cells or thicker walls, [VLM](https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-lightmaps-in-unreal-engine)) |
| Dark blotches near geometry | Invalid probes with no valid neighbor | Virtual offset first, dilation second; check the valid flag and the offset in a debug view (Unity, [APV validity](https://docs.unity3d.com/6000.0/Documentation/Manual/urp/probevolumes-light-probe-validity.html)) |
| Crate near a wall samples the wrong side | Normal bias too small; probe on the wall side | Increase normal bias up to 0.5 x spacing; use `Min Valid Dot Product` style facing rejection; do not shrink the probe spacing without measuring |
| Crate pops at a cell boundary | Invalid probes are skipped and the weight set changes | Dilation fills invalid probes; tetrahedral weights are continuous; capture a crate path across the arena |
| Crate does not darken the floor | Dynamic occluders are excluded from the bake | Accepted; direct shadow does the grounding |
| Static and dynamic indirect disagree at the crate/floor contact | Lightmap and probe are different representations | Same bake, same source list, same `indirect_scale`; normal bias; compare captures |
| Ringing or over-bright back side | L2 SH (not used here) or too few rays | Octa map; no SH; 1024 rays |
| Banding / structured noise | Same fixed ray set for every probe | Per-probe rotation of the sample set; hash seed |
| Black dynamic object | Outside the volume or all four probes invalid | Clamp border; zero outside with a visible `probe_missing`; never a silent black fallback |
| Stale probe field after a static fixture move | Bake key not rebuilt | Bake key and version in the renderer state; rebake before capture; visible stale flag |
| Double-counted fixture glow | Point light plus emissive body | One policy for both bakes; expose a scale |
| Dynamic lamp corner stays dark | Dynamic lamps are excluded from the bake | Intended; the direct pool and hard shadow still read; do not add fill |
| Lamp-free bake is black | No ambient term; all static fixtures removed | Intended by ADR 0041; report an empty bake, never a fill |
| Grid visible on a large flat crate | 1 m probes and tetrahedral interpolation | Expected for a low-frequency field; use 8 x 8 and normal bias; do not add a texture |

## Fit with the current renderer

| Current fact | Consequence |
| --- | --- |
| `Probe_Volume` is 32 B with min, spacing, counts, offset (`src/renderer/probe.odin:20-27`) | Keep the volume layout; drop `probe_offset` only if the volume count stays one. |
| 8 x 8 octa, gamma 5, depth moments, Fibonacci rays (`src/renderer/probe.odin:8-17`, `probe.glsl`) | The encoding and bake math already exist; the bake reuses them. |
| `draw_probes` and `probe_after` are a frame pass (`src/renderer/probe.odin:244-370`) | Remove the pass and the ray buffer; keep the gather. |
| `write_probe_positions` uses every box and is called every frame (`src/renderer/scene_draw.odin:45`, `probe_validity.odin:47-72`) | Replace with baked static validity and offsets; dynamic crates must not invalidate. |
| Gather blends eight probes with facing and Chebyshev (`probe_gather.glsl:83-143`) | Replace the eight-probe loop with four-probe tetrahedral selection; keep the visibility checks. |
| `camera.probe` holds volume count, probe count, and GI flag (`src/renderer/uniforms.odin:17-29`) | Keep volume/probe count; replace the GI flag with a baked-indirect flag or remove it. |
| Render digest hashes probe volumes and `gi` (`src/renderer/render_digest.odin:18-37`) | Add `bake_version` / `bake_key`; otherwise a rebake can compare as the same image. |
| Scene targets are RGBA16F (`src/renderer/frame_targets.odin:8`) | Probe data is HDR and linear; no tone-map change. |
| Harness state exposes probe volume/count (`src/renderer/state.odin:49-83`) | Add `bake.status`, `bake.version`, `bake.key`, `bake.probes`, `bake.ms`, `probe_missing`. |

## Rejected alternatives

| Alternative | Why rejected |
| --- | --- |
| No probes at all | Dynamic crates lose all static bounce and color bleed; Unity's moving-object example is exactly this flat result. |
| Per-object ambient | Constant across the object; no spatial gradient; the LPPV documentation calls this out as the problem it solves. |
| Per-frame DDGI | Owner's explicit no; cost, noise, and leak behavior are the reason for the change. |
| Screen-space GI | Fails at screen edges and cannot see off-screen static fixtures; not transport for a closed room. |
| L2 SH now | Smaller, but loses the direction-dependent depth test and adds ringing; keep as a measured alternative. |
| Full APV | Automatic bricks, streaming, scenarios, and rendering layers are for large multi-room worlds; one 40 m room does not need them. |
| Unreal VLM | Tied to the lightmap/importance-volume machinery; its own leak fix is density or thicker walls; more system than needed. |
| Manual probe placement | No probe editor; the arena is a regular box; automatic grid is simpler and deterministic. |
| 0.5 m grid | 4x the probes and bake rays for detail the flat box look does not need; try 1 m first. |
| Baked direct light in probes | Doubles the real-time direct term and makes the probe field carry sharp shadow edges; Unity warns that direct light in probes causes ringing. |
| Dynamic occlusion / dynamic bounce | That is dynamic GI; the owner asked for static indirect only. |
| Ambient fill | Rejected by ADR 0041; it hides missing lamp coverage. |

## Open decisions for the owner

1. **Octa versus L2 SH.** Recommendation: keep the octa map with depth moments for leak control; revisit L2 SH only if memory or sampling cost is measured as a problem.
2. **1 m versus 2 m.** Recommendation: 1 m, 40 x 5 x 40; 2 m is the fallback if the bake budget or memory is tight. The tunnel is the deciding case.
3. **8 x 8 versus 4 x 4.** Recommendation: 8 x 8 for parity with today; 4 x 4 is the measured reduction, not the default.
4. **Depth moments.** Recommendation: keep first and second moments; they are the main leak control and the reason not to switch to SH.
5. **Validity and dilation policy.** Recommendation: static-box inside test, backface tolerance, virtual offset, then dilation; store valid and offset; skip invalid probes at runtime.
6. **Normal bias.** Recommendation: 0.1 x spacing, tune with a crate-against-wall capture; Unity exposes the same knob.
7. **Fixture emissive double count.** Same decision as #371; do not let the probe bake and the lightmap bake disagree.
8. **Probe border.** Closed arena, so clamp and mark outside as missing. If a future room is added, add a volume, not a stretched border.
9. **Probe debug view.** Recommendation: a debug capture of probe validity and a probe-lit-only view; it is the fastest way to find leaks without a gate.
10. **Static/dynamic boundary.** A crate flipped to static needs a lightmap tile and a rebake; decide whether the editor forbids the flip until the rebake completes.
11. **Probe volume shape.** One volume now; multiple volumes only when a second room exists.
12. **Bake quality budget.** 1024 rays/probe and 8 x 8 is the starting point; 2048 is the quality option; 512 is the draft option.

## Primary sources

- Unity Light Probes: [data format, 27 floats L2 SH](https://docs.unity3d.com/6000.0/Documentation/Manual/LightProbes-TechnicalInformation.html), [moving objects and tetrahedral interpolation](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/direct-and-indirect-lighting/light-probes/moving-objects), [troubleshooting ringing and placement](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/direct-and-indirect-lighting/light-probes/troubleshooting), [Light Probe Proxy Volume](https://docs.unity3d.com/6000.0/Documentation/Manual/class-LightProbeProxyVolume.html).
- Unity APV: [concept, bricks, 1/3/9/27 m, per-pixel eight probes](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting/probevolumes/concept), [density](https://docs.unity3d.com/6000.0/Documentation/Manual/urp/probevolumes-changedensity.html), [validity, virtual offset, dilation](https://docs.unity3d.com/6000.0/Documentation/Manual/urp/probevolumes-light-probe-validity.html), [artefacts and virtual offset settings](https://docs.unity3d.com/6000.0/Documentation/Manual/urp/probevolumes-troubleshoot-artefacts.html), [light leaks, normal/view bias, rendering layers, density](https://docs.unity3d.com/6000.0/Documentation/Manual/urp/probevolumes-troubleshoot-light-leaks.html), [options: normal bias, view bias, leak reduction, min valid dot](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting/probevolumes/options-override-reference).
- Unity lightmaps: [backface tolerance, anti-aliasing, pushoff](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting-reference/class-lightmap-parameters), [indirect samples and probe sample multiplier](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/direct-and-indirect-lighting/lightmapping/baking-before-runtime/lightmaps-reference).
- Unreal: [Volumetric Lightmaps](https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-lightmaps-in-unreal-engine), [Stationary light mobility](https://dev.epicgames.com/documentation/en-us/unreal-engine/stationary-light-mobility-in-unreal-engine), [CPU Lightmass character lighting](https://dev.epicgames.com/documentation/en-us/unreal-engine/cpu-lightmass-global-illumination-in-unreal-engine), [GPU Lightmass](https://dev.epicgames.com/documentation/en-us/unreal-engine/gpu-lightmass-global-illumination-in-unreal-engine).
- Papers: [Majercik et al., DDGI](https://jcgt.org/published/0008/02/01/paper.pdf), [Greger et al., The Irradiance Volume](https://gene.greger-weltin.org/professional/publications/irradiance_volume_ieee.html), [Ramamoorthi and Hanrahan](https://cseweb.ucsd.edu/~ravir/papers/envmap/envmap.pdf), [PBRT Monte Carlo error](https://pbr-book.org/3ed-2018/Monte_Carlo_Integration/The_Monte_Carlo_Estimator), [PCG](https://www.pcg-random.org/pdf/hmc-cs-2014-0905.pdf), [hash-based Owen scrambling](https://jcgt.org/published/0009/04/01/paper.pdf).
- Repository: `docs/research/mixed-lighting.md`, `docs/research/lightmap-boxes.md`, `docs/adr/0041-absolute-darkness.md`, `docs/adr/0042-single-volume-ddgi.md`, `src/renderer/probe.odin`, `src/renderer/probe_validity.odin`, `src/renderer/shaders/probe_ray.comp`, `probe_blend.comp`, `probe_gather.glsl`, `src/renderer/scene_draw.odin`, `src/frame/frame.odin`.
