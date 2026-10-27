# Ambient occlusion: technique research for harbagsa

Research for [Wayfinder ticket #355](https://github.com/eyenalxai/harbagsa/issues/355).
This note is not a decision record and not an implementation plan. It compares
the credible techniques, records the evidence, and gives one recommendation for
the decision ticket that follows.

Measured on 2026-10-27. The development GPU is an AMD Radeon RX 9060 XT
(RADV GFX1200), Mesa 26.2.5.

## Answer in brief

- **Keep no AO as the baseline.** Direct hard shadows already give direct-light
  contact. The only ambient term is a constant 0.055 readability floor, not sky
  or indirect light. AO applied to that floor is a stylistic darkening, not a
  physical transport term.
- **The only AO that fits this renderer is ray-traced AO in the lit pass,
  applied to the ambient floor only.** It reuses the TLAS and the existing ray
  query. Use 8 cosine-weighted rays, a 1.5 m radius, and TAA. Do not add a
  separate AO pass or a denoiser for that sample count.
- **Do not apply AO to the direct lights.** The direct shadows already test
  direct visibility. Multiplying direct light by AO would double-darken contact
  and is physically wrong.
- **Do not add GTAO, HBAO, SSAO, VBAO, or CACAO first.** They need a depth and
  normal input, and they cannot see an occluder outside the view. This renderer
  already pays for ray-query hardware for shadows.
- **A pixel-art box scene may get little from AO.** AO is strongest on small
  creases and dense geometry. This scene is large flat boxes; hard shadows do
  most of the shape work.
- **Do not add AO until a capture shows a concrete visual need beyond the
  shadows.** No AO is a valid result of the decision.

## What AO means here

AO estimates the cosine-weighted fraction of the hemisphere that reaches a
surface:

```text
A(x) = (1 / pi) * integral(V(x, w) * max(n . w, 0) dw)
```

The value is in `[0, 1]`. It becomes a simple multiplier only under three
assumptions: an infinite uniform environment, absorbing occluders, and a
Lambertian receiver. It ignores interreflection, so it over-darkens enclosed
spaces. GTAO adds a near-field bounce term to reduce that error. [4][17]

The current renderer does not have an environment or an indirect bounce. Its
ambient term is a constant floor chosen for readability
(`src/renderer/shaders/box.frag`). AO would multiply that constant. In a lit
area, the direct lights dominate and the AO change is small. In an unlit area,
the surface is already near black. This is the main physical problem with AO
here.

The second problem is visual. Direct hard shadows already create contact where
a crate meets the floor or a wall meets a ceiling. AO in the ambient term would
add a softer, local darkening around those same corners. The flat box style has
few small crevices for a screen-space estimator to find.

The old renderer applied eight AO rays to the ambient term, then to the direct
light after the ambient term was removed. It was part of the same lighting
stack that was deleted when the direct-light model landed. [14][15]

## Current renderer facts

- One cube mesh, scaled and rotated into every box.
- Direct clustered point lights. ADR 0029 sets the long-term target at 96 lights
  and 300 objects.
- Hard ray-query point-light shadows. One cube BLAS, one per-frame TLAS. [15]
- One constant ambient floor of `0.055, 0.060, 0.070`.
- TAA, a depth prepass, scene colour, and velocity. There is no normal target.
- No sun, no sky lighting, no baked lighting, no GI, no probes, no textures.
- The 96-light dense shadow test costs 4.57 ms of shadow work at 1080p; the full
  frame is 6.45 ms with shadows on. [16]

The normal target is the important gap for screen-space AO. A GTAO or HBAO pass
needs depth and normals. It would either add a normal target and another pass,
or reconstruct normals from depth at box edges. RTAO needs neither: it can use
the position and normal already present in the lit shader.

## The candidates

### 1. No AO

**What it does.** Keep the constant ambient floor and the direct shadows.

**Strengths.**

- No extra pass, ray, target, or budget.
- The ambient floor keeps unlit albedo readable, as the visual guide requires.
- Direct shadows already supply the contact cue.
- No risk of AO halos, double darkening, or noise.
- The flat box look has little fine crevice detail for AO to reveal.

**Costs and risks.**

- Large concave corners stay evenly lit by the ambient floor.
- The scene may look slightly flat where no direct light reaches.
- If the owner wants a dark crease under every crate, this option does not give
  it.

**Fit:** the correct baseline. Choose it unless a visual test shows a real gap.

### 2. Ray-traced AO in the lit pass

**What it does.** Trace 8 cosine-weighted hemisphere rays per fragment against
the TLAS, out to a 1.5 m radius. Multiply the ambient floor by the visible
fraction. TAA resolves the rotating sample pattern. This is the old AO path.

**Strengths.**

- Reuses the TLAS, the `occluded` helper, and the ray-query device requirement.
- Sees off-screen occluders. A corner darkens from the wall behind the camera,
  which a screen-space method cannot do. [9][14]
- No new target, render pass, or descriptor set. It runs in the lit shader.
- Eight rays with TAA are stable enough for the old scene; the old build used
  exactly this shape. [14]
- Correctly treats the ambient floor as the only light it can affect.

**Costs and risks.**

- Full-resolution hemisphere rays are incoherent. The old renderer measured
  about 0.91 ms extra at 1440p for 8 rays, about 0.11 ms per marginal ray. That
  was a different scene, so re-measure. [14]
- It multiplies only the ambient floor. The visible effect is small on lit
  faces.
- It reduces the readability floor in corners. That conflicts with the reason
  the floor exists.
- It can double-darken a corner if the direct shadows are already strong and
  the ambient floor is visible there.
- It adds 8 rays per fragment on top of the shadow rays. The 96-light shadow
  budget is already 4.57 ms at 1080p.
- It does not give bent normals or directional occlusion. That is enough for a
  scalar ambient floor, but not for a future environment probe.

**Fit:** the only AO worth implementing for this renderer, and only as an
ambient-only stylistic term.

### 3. Ray-traced AO with a separate pass and denoiser

**What it does.** Trace 1 to 4 rays at full or half resolution in a compute
pass, then reconstruct with a spatiotemporal denoiser such as NVIDIA NRD's
REBLUR occlusion mode. [8]

**Strengths.**

- Handles 1 to 2 rays per pixel, which suits lower-end RT hardware.
- Separates AO from the lit shader and allows a lower resolution.
- NRD and similar filters are production-proven for occlusion input.

**Costs and risks.**

- One more pass, one more AO target, a history buffer, and a library or a
  hand-written denoiser.
- AO is small and low-frequency here. The denoiser costs more than the signal
  is worth.
- TAA already accumulates 8 deterministic rotating rays.
- The old 8-ray path fits in the existing shader. A separate path is more code
  for no clear visual gain.

**Fit:** only if 8 full-resolution rays do not fit the budget and a 1 to 2 ray
path is required. Not the first step.

### 4. GTAO

**What it does.** Reconstruct view-space depth and normals, march horizon slices
in screen space, and integrate the visible horizon analytically. Run at half
resolution with a bilateral upsample. [4]

**Strengths.**

- The mature raster default. It matches ray-traced AO closely and costs about
  0.5 ms at 1080p on a PS4 in the original work. [4]
- DirectX and Vulkan implementations exist. Intel XeGTAO reports 0.56 ms at
  1080p on an RTX 2060 and supports TAA. [6]
- Works without ray-query hardware if a future port needs it.

**Costs and risks.**

- Needs depth and normals. This renderer has no normal target. Reconstructing
  normals from a depth buffer at box edges is possible but adds artifacts.
- Cannot see an occluder outside the view. In a corner, the wall behind the
  camera is often the occluder. [9][14]
- Thin geometry and the height-field assumption remain hard. XeGTAO calls thin
  occluders the main difficulty. [6]
- Half-resolution reconstruction and a spatial filter add code and targets.
- It is designed for screen-space detail; this scene is large flat boxes.

**Fit:** the fallback if ray-query hardware is removed from the product. Not for
the current renderer.

### 5. HBAO and SSAO

**What they do.** March or sample the depth buffer to estimate occlusion. HBAO
uses horizon angles; SSAO uses a hemisphere of screen-space samples. [1][2]

**Strengths.**

- Simple inputs and a long production history.
- Cheap on weak hardware.

**Costs and risks.**

- HBAO's estimator is not the cosine-weighted integral. GTAO is more accurate
  and as fast. [4]
- SSAO has no physical basis and shows scale and halo artifacts.
- Both have the same screen-space limits as GTAO.

**Fit:** no reason to choose them over GTAO if screen-space is the answer.

### 6. VBAO / visibility bitmask

**What it does.** Replaces the two horizon angles in GTAO with a bitmask over
32 sectors. It handles thin surfaces and can output more than one visibility
cone. [5]

**Strengths.**

- Better thin-geometry behavior than GTAO.
- Similar sample budget.
- Can produce directional occlusion.

**Costs and risks.**

- Still screen-space, still needs a depth/normal input, still cannot see behind
  the camera.
- More implementation detail than GTAO for a scene with few thin occluders.
- It is a refinement, not a new input path.

**Fit:** interesting only if GTAO is chosen and thin panels become a visible
problem.

### 7. CACAO

**What it does.** AMD's optimized screen-space AO. It supports Vulkan and runs
at multiple quality levels. [7]

**Strengths.**

- First-party AMD implementation and a production path on RDNA.
- Avoids writing the screen-space estimator and filters by hand.
- Tunable quality settings.

**Costs and risks.**

- It is still screen-space and still needs depth/normals.
- Adds a library, its resource set, and its update cadence.
- The visual limit is the same as GTAO.

**Fit:** a practical fallback for a non-RT target, not for this one.

### 8. Baked or material AO

**What it does.** Store occlusion in a texture or vertex attribute. Material AO
handles self-occlusion on detailed meshes. [10]

**Strengths.**

- Almost free at runtime.
- Correct for static detail.

**Costs and risks.**

- The renderer has no textures, no UVs, and no baked lighting.
- Every box is one flat colour and one normal.
- Dynamic crates and lamps would invalidate a baked solution.
- Static AO fields are an older precomputed alternative, not a dynamic path. [13]

**Fit:** out of scope.

## Comparison

| Technique | Input | Off-screen occluders | New pass or target | Quality and cost | Fit here |
| --- | --- | --- | --- | --- | --- |
| No AO | none | -- | none | baseline | **Default** |
| RTAO in lit pass | TLAS, normal | Yes | No | 8 rays, TAA, historical 0.91 ms at 1440p | **If AO is wanted** |
| RTAO + denoiser | TLAS, normal, history | Yes | Yes | 1-4 rays plus denoiser | Budget fallback |
| GTAO | depth, normals | No | Yes | 0.5 ms PS4, 0.56 ms RTX 2060 at 1080p | Raster fallback |
| HBAO / SSAO | depth | No | Yes | cheaper, less correct | No |
| VBAO | depth, normals | No | Yes | GTAO-like plus thin detail | No |
| CACAO | depth, normals | No | Yes | screen-space AO library, tunable | No |
| Baked / material | texture or vertex | Yes | No | free at runtime | No textures |

## What production renderers do now

- GTAO is still the screen-space baseline. XeGTAO is a tuned implementation and
  reports 0.56 ms at 1080p on an RTX 2060. It was archived in 2024. [4][6]
- CACAO ships as an AMD FidelityFX effect and supports Vulkan. [7]
- Unity HDRP offers ray-traced AO as the more accurate alternative to its
  screen-space AO, specifically because it can use off-screen data. [9]
- NVIDIA NRD provides REBLUR occlusion and directional-occlusion modes for
  traced AO. It is a denoiser library, not an AO estimator. [8]
- At the high end, AO is folded into GI. Unreal states that Lumen Global
  Illumination replaces Distance Field Ambient Occlusion; material AO remains
  for self-occlusion. [10]
- The 2023 VBAO work is the credible screen-space refinement, not a new family.
  [5]

The production split is clear: GTAO or CACAO for raster, RTAO plus a denoiser
for hardware ray tracing, and full GI instead of AO at the top. This renderer
is a rare case: it has ray tracing but no indirect light for AO to modulate.

## Recommendation

### Default: no AO

Keep the current ambient floor and direct shadows. Add AO only after a visual
test shows a concrete darkening that the direct shadows do not supply. The
burden of proof is on AO, not on the absence of AO.

This is not a rejection of AO as a technique. It is a statement about this
renderer: with no indirect source and large flat boxes, the visible signal is
small and the readability floor is at risk.

### If the owner wants AO: RTAO, ambient only

Add the old 8-ray path back to the lit shader:

1. Trace 8 cosine-weighted hemisphere rays from `world_position + normal * 0.01`.
2. Use `gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsOpaqueEXT`, `TMin =
   0.001`, and `TMax = 1.5 m`.
3. Include every box in the ray mask. The lamp housing can occlude ambient
   light; this is not the lamp shadow path.
4. Multiply only the ambient floor:
   `albedo * (ambient_floor * ao + direct_lights) + albedo * emissive`.
5. Rotate the sample pattern with a temporal phase. The current camera uniform
   has no AO phase: `screen.w` holds the plan-view clip height, not a phase.
   Use a new phase field or the TAA jitter index. No separate AO pass and no
   denoiser for 8 rays.
6. Add a gated `ao` debug override for paired captures and performance runs.
7. Measure the 96-light frame before accepting the feature.

Do not multiply the direct point-light sum by AO. Do not apply AO to the emissive
term. Do not gate it to a single light.

### Scale the feature to the budget

The old 8-ray path cost about 0.91 ms at 1440p on the older scene. The current
96-light shadow frame is 6.45 ms at 1080p. If AO pushes the 96-light frame past
the accepted budget, use 4 rays with TAA first. A separate half-resolution pass
with a denoiser is the next step, not the first.

### What would change the recommendation

- **Real ambient or sky lighting returns.** Then AO has a physical source and
  its value rises.
- **The product drops ray-query hardware.** GTAO or CACAO becomes the correct
  path, with a normal target and a half-resolution reconstruction.
- **The scene gains fine geometry or clutter.** AO gets a larger visual job.
- **GI or path tracing is adopted.** Remove the AO pass; the GI solve replaces
  it.
- **A visual test shows no readable difference.** Keep no AO. That is a valid
  outcome.

## Evidence plan if AO is chosen

- `scenarios/ao.json`: a corner with a crate and wall. Capture AO on and off
  from the same camera. The enclosed corner must darken; an open floor must
  stay close.
- `scenarios/ao-taa.json`: settle a static camera and check the frame-to-frame
  delta. The 8-ray pattern must not pulse.
- `scenarios/perf-ao.json`: 96 lights at 1080p, AO on and off, several runs.
  Record the paired cost.
- A renderer test: a concave corner darkens, an open surface does not, and the
  direct-light contribution is unchanged.
- `docs/evidence/ambient-occlusion.md`: the paired captures, the region
  statistic, the machine, and the cost.
- A new ADR if AO is accepted.

The exact gates belong to
[Set the AO budget and evidence gate](https://github.com/eyenalxai/harbagsa/issues/358).

## What this leaves open

- **Visual intent:** is AO wanted as physical ambient visibility, or as a
  contact-darkening look? [Choose the production AO technique and visual intent](https://github.com/eyenalxai/harbagsa/issues/356)
- **Model:** radius, strength, sample count, and whether TAA is enough.
  [Set the AO radius, strength, and temporal model](https://github.com/eyenalxai/harbagsa/issues/357)
- **Budget and evidence:** the 96-light limit and the capture gates.
  [Set the AO budget and evidence gate](https://github.com/eyenalxai/harbagsa/issues/358)

## Method and limits

The research used primary sources: the original papers, vendor manuals,
implementation notes, engine documentation, and the project history.

Limits:

- No new AO benchmark was run for this note. The 0.91 ms figure is from the old
  renderer with a different lighting stack.
- The current renderer has direct shadows and a smaller ambient term, so the
  visual result will differ.
- The hardware evidence is one AMD GPU and one driver.
- The project's old AO was applied to ambient first and direct light later.
  Neither is the current model.
- The recommendation is for this renderer, not for every renderer.

## Sources

1. Martin Mittring, *Finding Next Gen: CryEngine 2*, ACM SIGGRAPH 2007
   Courses. The original SSAO technique.
   <https://web.archive.org/web/2019/https://artis.inrialpes.fr/Membres/Olivier.Hoel/ssao/p97-mittring.pdf>
2. Louis Bavoil, Miguel Sainz, *Image-Space Horizon-Based Ambient Occlusion*,
   ACM SIGGRAPH 2008 Talks. <https://doi.org/10.1145/1401032.1401061>
   <https://developer.download.nvidia.com/presentations/2008/SIGGRAPH/HBAO_SIG08b.pdf>
3. Morgan McGuire, Michael Mara, David Luebke, *Scalable Ambient Obscurance*,
   High Performance Graphics 2012.
   <https://research.nvidia.com/sites/default/files/pubs/2012-06_Scalable-Ambient-Obscurance/McGuire12SAO.pdf>
4. Jorge Jimenez, Xian-Chun Wu, Angelo Pesce, Adrian Jarabo, *Practical
   Realtime Strategies for Accurate Indirect Occlusion*, Technical Memo
   ATVI-TR-16-01, 2016. Ground Truth Ambient Occlusion.
   <https://www.activision.com/cdn/research/Practical_Real_Time_Strategies_for_Accurate_Indirect_Occlusion_NEW%20VERSION_COLOR.pdf>
5. Olivier Therrien, Yannick Levesque, Guillaume Gilet, *Screen Space Indirect
   Lighting with Visibility Bitmask*, 2023. The VBAO technique.
   <https://arxiv.org/abs/2301.11376>
6. Intel, *XeGTAO*, MIT implementation of GTAO, archived 2024.
   <https://github.com/GameTechDev/XeGTAO>
7. AMD GPUOpen, *AMD FidelityFX Combined Adaptive Compute Ambient Occlusion
   (CACAO)*, Vulkan and DirectX 12.
   <https://gpuopen.com/fidelityfx-cacao/>
8. NVIDIA, *NVIDIA Real-Time Denoisers (NRD)*, REBLUR occlusion and
   directional-occlusion modes.
   <https://github.com/NVIDIA-RTX/NRD>
9. Unity, *Ray-Traced Ambient Occlusion*, High Definition Render Pipeline
   documentation. <https://docs.unity3d.com/Packages/com.unity.render-pipelines.high-definition@14.1/manual/Ray-Traced-Ambient-Occlusion.html>
10. Epic Games, *Lumen Global Illumination and Reflections*, Unreal Engine
    documentation. Lumen GI replaces Distance Field Ambient Occlusion.
    <https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-global-illumination-and-reflections-in-unreal-engine>
11. Michael Mara, Morgan McGuire, David Luebke, *Deep G-Buffers for Stable
    Global Illumination and Ambient Occlusion*, 2016.
    <https://research.nvidia.com/sites/default/files/pubs/2016-06_Deep-G-Buffers-for/Mara2016DeepGBuffer-extended-bright.pdf>
12. Jop Vermeer, Leonardo Scandolo, Elmar Eisemann, *Stochastic-Depth Ambient
    Occlusion*, 2021. <https://doi.org/10.1145/3451268>
13. Janne Kontkanen, Samuli Laine, *Ambient Occlusion Fields*, I3D 2005.
    <https://research.nvidia.com/sites/default/files/publications/kontkanen2005i3d_paper.pdf>
14. `harbagsa`, ADR 0017, *Analytic sky and ray-traced ambient occlusion*, and
    ADR 0028, *Direct light with surface occlusion*, at commit
    [`4d7ad86`](https://github.com/eyenalxai/harbagsa/commit/4d7ad867efa69d369fab11752888b9aa4fad60c2).
    These record the old 8-ray AO cost and its two lighting roles.
15. `harbagsa`, [ADR 0040](../adr/0040-hard-point-light-shadows.md), hard
    point-light shadows.
16. `harbagsa`, [point-light shadow evidence](../evidence/point-light-shadows.md),
    the current 96-light shadow budget.
17. Elmar Eisemann, Michael Schwarz, Ulf Assarsson, Michael Wimmer,
    *Real-Time Shadows*, A K Peters/CRC Press, 2011.
    <https://doi.org/10.1201/b11030>
