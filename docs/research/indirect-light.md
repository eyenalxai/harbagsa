# Lighting unlit surfaces: how games add indirect light

Research for the owner question after the ambient floor was removed. This is not
a decision record and not an implementation plan. It explains why a direct-only
view is black, what games use instead, and which path fits this renderer.

Captured on 2026-10-27. The current renderer is on `main` after the ambient
floor removal. The development GPU is an AMD Radeon RX 9060 XT (RADV GFX1200).

## Answer in brief

- **Black is correct for direct-only lighting.** A surface with no direct lamp
  and no emissive term receives zero light. The removed ambient floor was a
  fake fill, not GI.
- **Games do not use direct light alone.** They add indirect light with baked
  lightmaps, probe volumes, dynamic GI, screen-space GI, or a deliberate ambient
  fill. The method follows the scene: static, dynamic, or mixed.
- **The closest fit for this closed box with moving lamps is a one-bounce
  irradiance-probe field: DDGI.** It sees off-screen walls, follows moving
  lamps, and adds colored bounce from the lamp surfaces. The project already had
  a DDGI implementation; a single-volume version is much smaller than the old
  multi-room system.
- **Screen-space GI is the cheaper fallback.** It can add floor and wall bounce,
  but it cannot see an occluder behind the camera. That is the common case in a
  closed room.
- **A small ambient fill is the minimal fix, not the quality fix.** It makes
  unlit surfaces readable, but it hides missing lamp coverage. The owner already
  rejected it.
- **AO is not a substitute.** Ambient occlusion is visibility for ambient light.
  It cannot create a bounce. With the ambient floor gone, AO would multiply zero.
- **Baked lightmaps and baked probe volumes do not fit.** The lamps move. The
  renderer has no textures and no bake pipeline.
- **Lumen and path tracing are overkill** for this box. DDGI is the same idea at
  this scale.

## Why the current view is black

The current lit pass is:

```text
albedo * direct_point_lights + albedo * emissive
```

If no point light reaches the surface and the surface is not emissive, the
result is zero. A closed box adds no sky and no environment light. The direct
shadows only remove light; they never add it.

This is a complete direct-lighting model, not a missing texture. It is also the
model the owner asked for when the ambient floor was removed. The consequence
is exactly what the current captures show.

Games usually keep direct lighting and add a second transport term:

```text
direct lighting + indirect lighting
```

The indirect term is the light that bounced off another surface before it
reached this one.

## The techniques games use

### 1. Baked lightmaps and baked GI

**How it works.** A light build traces or rasterizes light paths offline. Static
surfaces receive a lightmap texture with direct and indirect light. Dynamic
objects sample a volumetric lightmap or probe field.

**Where it fits.** Static worlds and static or stationary lights. Unreal
Lightmass and Unity's baked GI are the common production paths. Unreal's
Volumetric Lightmaps give dynamic objects precomputed indirect light. [1][2][3]

**Why it does not fit here.** Lamps are dynamic-only. The renderer has no UVs,
no textures, and no lightmap pipeline. A bake for every lamp move is not a
runtime solution.

### 2. Baked light probes or adaptive probe volumes

**How it works.** Probes store incoming radiance or irradiance in a volume.
Surfaces interpolate nearby probes. Unity Light Probes and Adaptive Probe
Volumes are the common examples; both bake indirect light. [4][5]

**Where it fits.** Static light with dynamic objects.

**Why it does not fit here.** Same reason as lightmaps: the lamps move. A baked
probe field cannot follow a lamp without a rebake.

### 3. Dynamic probe GI: DDGI

**How it works.** A grid of probes traces rays into the scene every frame. Each
probe stores irradiance in an octahedral texture and a depth moment for
visibility. Surfaces sample the eight surrounding probes with trilinear weights
and a depth test. The result is one-bounce (or multi-bounce if probes sample each
other) diffuse GI. [6][8]

**Where it fits.** Dynamic lights and moving objects. The probes see off-screen
geometry, so a wall behind the camera lights the corner in front of it. The
light is colored by the surface that bounced it.

**Project history.** The renderer had DDGI. The first version used 300 probes and
a 0.154 ms probe pass at 1280x720 with 64 synthetic lights. The later production
version used 2205 probes and cost 1.732 ms at 1280x720 with 64 lights; the full
GPU frame was 5.549 ms. It was removed with the direct-light simplification, not
because the output was wrong. [9][10]

**Why a single volume is simpler now.** The old system had six volumes, invalid
probes, multi-room leak control, and a path-traced reference. The current arena
is one closed box. A single volume removes the room-classification problem. The
remaining work is probe validity inside boxes, interpolation, and update cost.

### 4. Screen-space GI

**How it works.** Use the current depth and colour buffers to trace a short ray
and add the colour of the first visible hit. Unity HDRP SSGI works this way.
Lumen also starts with screen traces before it falls back to a world-space
method. [11][12]

**Where it fits.** A cheap secondary bounce when the important geometry is on
screen. It adds floor and wall colour quickly.

**Why it is not enough here.** A screen-space ray cannot hit geometry behind the
camera. In a room, the wall that should light the corner is often behind the
view. Lumen's documentation says the screen path falls back when a hit is not in
the screen data. That fallback is the expensive part. [12]

### 5. Ray-traced GI and ReSTIR GI

**How it works.** Trace one or more diffuse paths per pixel. ReSTIR GI resamples
paths across space and time so one sample per pixel is usable. A denoiser
removes the remaining noise. [13]

**Where it fits.** High-end hardware and games that already have a denoiser and
a ray-tracing scene.

**Why it is overkill here.** It needs a per-pixel path budget, temporal
reprojection, and a denoiser. The box has one bounce and a small set of lamps.
A probe field amortizes the same bounce over many pixels.

### 6. Lumen and full engine GI

**How it works.** Unreal Lumen solves diffuse indirect lighting and reflections
with screen traces, a surface cache, and hardware or software ray tracing. It
supports infinite diffuse bounces, sky lighting, and emissive materials. [12]

**Where it fits.** A large dynamic world with an engine that already pays for
the scene representation, caches, and denoising.

**Why it is overkill here.** It is a large system. The renderer has one mesh and
a closed box. DDGI is the same dynamic-probe idea without the Nanite-scale
machinery.

### 7. An ambient fill

**How it works.** Add a constant or hemisphere term to every surface. It is
cheap, stable, and art-directable. It is not transport.

**Where it fits.** Low-end targets, stylized games, or a temporary readability
floor. Many games use a small fill even when they have GI.

**Why it is not the quality answer.** It hides missing lamp coverage, flattens
the room, and cannot produce colored bounce. The owner removed it because it read
as a default light. Reintroducing it solves the black screen but not the physical
problem.

### 8. Ambient occlusion

**How it works.** Estimate the visible fraction of the hemisphere. Multiply an
ambient term.

**Why it does not help.** AO is a visibility term, not transport. It cannot add
light. With no ambient term, it multiplies zero. The direct hard shadows already
provide contact. See the closed [ambient occlusion map](https://github.com/eyenalxai/harbagsa/issues/354).

Most games combine two or three of these. A typical mixed scene uses baked
lightmaps for static geometry, a probe field for dynamic objects, and a small
ambient fill. A dynamic scene uses DDGI or ray-traced GI, with screen-space GI as
a cheap first ray. A path-traced scene removes the separate GI pass. The common
principle is the same: direct light is only one term.

## Comparison

| Technique | Dynamic lamps | Off-screen light | Runtime cost | Bake or assets | Fit here |
| --- | --- | --- | --- | --- | --- |
| Baked lightmaps | No | Yes, after bake | Very low | Baked textures and UVs | No |
| Baked probes | No | Yes, after bake | Low | Probe bake | No |
| DDGI, one volume | Yes | Yes | Medium | Probe grid | **Best fit** |
| Screen-space GI | Yes | No | Low | Depth and colour | Fallback |
| Ray-traced GI / ReSTIR GI | Yes | Yes | High | Denoiser and history | Too large |
| Lumen | Yes | Yes | High | Engine-scale scene | Too large |
| Ambient fill | Yes | Yes, fake | Very low | None | Interim only |
| Ambient occlusion | Yes | No | Low | Depth/normals or TLAS | Does not add light |

## What the old DDGI measured

The old code is evidence, not a plan to restore the whole old renderer. It had
sun and sky; the current version would replace the miss with zero and shade hits
with the current point lights and emissive boxes.

| Probe count | Rays per probe | Probe pass at 720p | Lights |
| ---: | ---: | ---: | ---: |
| 300 | 64 | 0.154 ms | 64 |
| 2205 | 256 | 1.732 ms | 64 |

The 2205-probe run made the full GPU frame 5.549 ms at 1280x720. The final
production field had six volumes for the arena, room, roof, and strips. The old
system also had invalid probes, a depth-moment test, a Chebyshev floor, and a
path-traced reference. [9][10]

A single arena volume at 2 m spacing is roughly 20 x 4 x 20, or 1600 probes.
At the old 64-ray rate, that is about 100k probe rays per frame. The old 300-probe
pass was 0.154 ms; a 1600-probe pass is roughly 0.8 ms before the current 96-light
shading cost. That is an estimate, not a measurement.

The current direct + shadow frame is 6.23 ms at 1080p for 96 lights. A coarse
single-volume DDGI would need a measured budget. It is not free, but it is the
right order of cost for this scene.

## Recommendation

### Primary: one-bounce DDGI in a single arena volume

Add a single irradiance-probe volume that covers the playable box. Trace one
bounce from the lamps and emissive boxes. Do not add a sky term; a miss returns
zero.

The shape:

```text
probe update:
  for each valid probe:
    trace 64 rays over the sphere
    shade each hit with the current point lights and emissive boxes
    store octahedral irradiance and a depth moment

surface:
  sample the 8 surrounding probes
  weight by trilinear position, normal facing, distance, and depth
  add the irradiance to the ambient path
```

- Use one volume for the closed arena. Do not recreate the six-volume room
  system.
- Start at 2 m spacing and 64 rays per probe. Measure before increasing.
- Mark a probe inside a box invalid. Skip it in the update and in the gather.
- Give the probe ray its own light selection. The camera cluster index uses
  `gl_FragCoord`, so it cannot be reused in a probe compute shader. A per-probe
  light list or a world-space light list is needed before the 96-light target is
  affordable.
- Store irradiance and a depth moment. The depth test rejects a probe behind a
  wall.
- Add a `gi` debug override for paired captures and performance.
- Keep direct hard shadows. Do not add AO.
- Keep the emissive term. The lamp panels and beacons add bounce.
- A miss returns zero. There is no sky.

This is the same family as Unreal Lumen and the old DDGI, reduced to one volume
and one bounce.

### Fallback: screen-space GI

If the budget cannot pay for probes, use a single-bounce screen-space GI pass.
It is cheaper and adds floor and wall colour. It cannot light around corners.
That limit is exactly the case a closed room creates, so it is a fallback, not
the destination.

### Interim: a small ambient fill

If the only goal is readability, a small ambient fill is the minimal change. It
is not GI and hides missing lamp coverage. The owner removed it for that reason.
Use it only as a deliberate art choice, not as a replacement for transport.

### Do not use

- Baked lightmaps or baked probes: lamps move.
- AO: no ambient term to occlude.
- Lumen or path tracing: too large for one box.
- A large multi-volume DDGI: the old system's complexity came from multiple
  rooms. The current scene is one.

## Evidence plan if GI is chosen

- `scenarios/gi.json`: a lamp around a corner. The far surface must gain coloured
  light with GI on, and go black with GI off.
- `scenarios/gi-dark.json`: no lamps. GI must not invent light. The frame stays
  black.
- `scenarios/gi-move.json`: move the lamp. The bounce must follow.
- `scenarios/gi-sealed.json`: a wall between two areas. No light crosses the
  wall. Probe validity and depth must reject the leak.
- `scenarios/perf-gi.json`: 96 lights, 1080p, GI on and off, several runs.
- A renderer test for a corner: direct light is unchanged; only the indirect
  term changes.
- `docs/evidence/indirect-light.md`: paired captures, probe count, energy, cost,
  and machine.
- A new ADR if GI is accepted.

The exact budget and gates belong to a decision ticket, not this research note.

## What this leaves open

- The probe volume and spacing.
- Whether one bounce is enough.
- The update rate: every frame, checkerboard, or a floor-weighted grid.
- The leak test and invalid-probe policy.
- The 96-light budget.
- Whether a small ambient fill remains as an art fallback.

## Method and limits

The research used primary sources: the DDGI paper and production paper, the
ReSTIR GI paper, Unreal Lightmass and Lumen documentation, Unity probe and SSGI
documentation, and the project's old DDGI ADRs and measurements.

Limits:

- No new GI implementation or benchmark was run for this note.
- The 0.154 ms and 1.732 ms figures are from the old renderer with a different
  sun/sky and light setup.
- The 1600-probe estimate is arithmetic, not a current measurement.
- The hardware evidence is one AMD GPU and one driver.
- The recommendation is for this closed box, not for every renderer.

## Sources

1. Epic Games, *CPU Lightmass Global Illumination*, Unreal Engine documentation.
   <https://dev.epicgames.com/documentation/en-us/unreal-engine/cpu-lightmass-global-illumination-in-unreal-engine>
2. Epic Games, *Volumetric Lightmaps*, Unreal Engine documentation.
   <https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-lightmaps-in-unreal-engine>
3. Epic Games, *Lightmass Basics*, Unreal Engine documentation.
   <https://dev.epicgames.com/documentation/en-us/unreal-engine/lightmass-basics-in-unreal-engine>
4. Unity, *Light Probes*, Unity Manual.
   <https://docs.unity3d.com/Manual/LightProbes.html>
5. Unity, *Introduction to Adaptive Probe Volumes*, Unity documentation.
   <https://docs.unity.com/en-us/engine/7000.0/manual/lighting-overview/lighting/probevolumes/concept>
6. Zander Majercik, Jean-Philippe Guertin, Derek Nowrouzezahrai, Morgan McGuire,
   *Dynamic Diffuse Global Illumination with Ray-Traced Irradiance Fields*,
   Journal of Computer Graphics Techniques 8(2), 2019.
   <https://jcgt.org/published/0008/02/01/>
7. Zander Majercik, Adam Marrs, Josef Spjut, Morgan McGuire, *Scaling
   Probe-Based Real-Time Dynamic Global Illumination for Production*, 2021.
   <https://arxiv.org/abs/2009.10796>
8. Zander Majercik, Jean-Philippe Guertin, Derek Nowrouzezahrai, Morgan McGuire,
   *Dynamic Diffuse Global Illumination with Ray-Traced Irradiance Fields*,
   NVIDIA research page.
   <https://research.nvidia.com/publication/2019-05_dynamic-diffuse-global-illumination-ray-traced-irradiance-fields>
9. `harbagsa`, ADR 0031, *DDGI probe volumes*, at commit
   [`4d7ad86`](https://github.com/eyenalxai/harbagsa/commit/4d7ad867efa69d369fab11752888b9aa4fad60c2).
10. `harbagsa`, ADR 0036, *DDGI probe validity and contact*, at the same commit.
11. Unity, *Screen Space Global Illumination*, High Definition Render Pipeline
    documentation.
    <https://docs.unity3d.com/Packages/com.unity.render-pipelines.high-definition@14.0/manual/Override-Screen-Space-GI.html>
12. Epic Games, *Lumen Technical Details*, Unreal Engine documentation.
    <https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-technical-details-in-unreal-engine>
13. Yaobin Ouyang, Shiqiu Liu, Markus Kettunen, Matt Pharr, Jacopo Pantaleoni,
    *ReSTIR GI: Path Resampling for Real-Time Path Tracing*, Computer Graphics
    Forum 40(8), pp. 17-29, 2021.
    <https://doi.org/10.1111/cgf.14378>
14. Epic Games, *Lumen Global Illumination and Reflections*, Unreal Engine
    documentation.
    <https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-global-illumination-and-reflections-in-unreal-engine>
15. `harbagsa`, [ADR 0041](../adr/0041-absolute-darkness.md), absolute darkness.
16. `harbagsa`, [point-light shadow evidence](../evidence/point-light-shadows.md),
    the current 96-light direct + shadow budget.
