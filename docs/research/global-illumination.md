# Global illumination: the methods and the papers, 2026

Research note. No implementation plan, no shader code. Every claim links to the
source that owns it. Vendor claims are marked as such.

Companion notes: [`global-illumination-reconstruction.md`](global-illumination-reconstruction.md)
(denoisers, temporal reuse, caches) and
[`global-illumination-fit.md`](global-illumination-fit.md) (which architecture
fits this renderer).

## The short answer

Direct light is solved here. Indirect light is a second integral, and it is the
one that is missing. Ambient occlusion does not compute it. An ambient fill does
not compute it either.

The renderer has a sun, eight point lights, ray-query shadows, and AO. It has no
bounce term (`README.md`, `GLOSSARY.md`).

Five families cover the field: **baked transport**, **runtime probe grids**,
**screen space**, **world space**, and **path tracing**.

This scene narrows the choice. The 1440p GPU total is 1.11 ms on an RX 9060 XT,
and the scene pass is 0.80 ms (`docs/evidence/perf-scene-pass.md`). A 1–2 ms
budget leaves at most 0.9 ms for GI. DDGI's screen-space gather alone cost 0.5 ms
at 1080p on an RTX 2080 Ti in 2019
([Table 2](https://jcgt.org/published/0008/02/01/)). At 1440p that is about
0.9 ms by pixel count, before any probe work. A full-resolution DDGI gather does
not fit. A half-resolution gather is the only version with a plausible cost.

The most active thread in the 2025–2026 record is **radiance cascades** moving
from 2D to sparse 3D ([Split RC](https://arxiv.org/abs/2607.20384)), alongside
**resampled path tracing** in shipping titles
([ReSTIR GI](https://research.nvidia.com/publication/2021-06_restir-gi-path-resampling-real-time-path-tracing)).
Neither fits 1 ms on this GPU today.

## 1. The transport problem

The rendering equation is emission plus the integral of incoming radiance times
the scattering function and the cosine term
([Kajiya 1986](https://doi.org/10.1145/15922.15902),
[PDF](https://www.cs.princeton.edu/courses/archive/fall03/cs526/papers/kajiya86.pdf)):

```
L_o(x, ω_o) = L_e(x, ω_o) + ∫_H² L_i(x, ω_i) · f_r(x, ω_i, ω_o) · (n·ω_i)⁺ dω_i
```

**Direct light** sets `L_i` to the radiance of the sun and the lamps. **Indirect
light** sets `L_i` to radiance leaving other surfaces. That is the only
difference, and it is why AO cannot stand in: AO has no `L_i` and no albedo.

For a Lambertian surface `f_r = ρ/π`, where `ρ` is the diffuse albedo
([PBRT §9.2](https://pbr-book.org/4ed/Reflection_Models/Diffuse_Reflection)):

```
L_o = L_e + (ρ/π)∫L_direct·V·cos dω + (ρ/π)∫L_indirect·V·cos dω
```

The **one-bounce** approximation replaces the last term with a single gather of
radiance that direct light has already reached:

```
L_1(x) = L_e(x) + (ρ/π) ∫ L_0(x') · V · (n·ω_i)⁺ dω_i
```

`L_0` is the direct-lit radiance at the first hit `x'`. Every one-bounce method
below computes that term in a different representation. **Multi-bounce** feeds
`L_1` back as incident radiance. DDGI does it across frames
([§5.3](https://jcgt.org/published/0008/02/01/)); Lumen claims infinite bounces
([Epic](https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-global-illumination-and-reflections-in-unreal-engine)).

**AO is not GI.** AO is the cosine-weighted visible fraction of the hemisphere,
`A(x) = (1/π)∫V·cos dω`. It becomes a multiplier on ambient light only under
three assumptions: an infinite uniform environment, purely absorbing occluders,
and a Lambertian receiver. Then `L = L_i·(ρ/π)·A(x)`. The assumptions are the
error: AO has no interreflection, so it over-darkens enclosed regions
([GTAO §2](https://www.iryoku.com/downloads/Practical-Realtime-Strategies-for-Accurate-Indirect-Occlusion.pdf)).

| Quantity | Depends on | Changes when the sun moves | Adds bounce light |
|---|---|---|---|
| Direct light | Sun and lamp radiance, visibility | Yes, every frame | No |
| AO | Visibility only | Only through sun direction | No |
| One-bounce GI | Direct-lit radiance at first hit | Yes, every frame | Yes |
| Multi-bounce GI | Previous bounce radiance | Yes, with lag | Yes |

## 2. Precomputed and semi-static

These methods move the integral to build time. Runtime is a lookup.

| Method | Stores | Dynamic sun | Dynamic boxes | Runtime cost | Source |
|---|---|---|---|---|---|
| Lightmap | Irradiance per surface texel | No, unless rebaked per angle | No | One fetch | [Lightmass](https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-lightmaps-in-unreal-engine) |
| Irradiance volume | SH irradiance on a 3D grid | No | No | Trilinear plus dot product | [Greger 1998](https://doi.org/10.1109/38.656788) |
| PRT | Transfer per vertex or texel | Low-frequency rotation only | No | 9–25 element dot product | [Sloan 2002](https://www.microsoft.com/en-us/research/publication/precomputed-radiance-transfer-real-time-rendering-dynamic-low-frequency-lighting-environments/) |
| Bent normal | Least-occluded direction | Baked direction, live sky colour | No | One lookup | [Unreal](https://dev.epicgames.com/documentation/en-us/unreal-engine/sky-lights-in-unreal-engine) |
| Unity APV | Baked probe bricks | No, Lighting Scenarios blend | No | Per-pixel interpolation | [Unity](https://docs.unity3d.com/6000.0/Documentation/Manual/urp/probevolumes-concept.html) |
| Unreal VLM | Baked SH samples in space | No | No | 0.02 ms per character, PS4 | [Epic](https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-lightmaps-in-unreal-engine) |

**PRT** precomputes how an object transfers low-frequency lighting, including
self-shadowing and interreflection. Runtime is a dot product of 9 to 25
spherical-harmonic coefficients for diffuse receivers. The paper's limits are
low-frequency lighting, rigid rotation only, and fixed transfer
([abstract](https://www.microsoft.com/en-us/research/publication/precomputed-radiance-transfer-real-time-rendering-dynamic-low-frequency-lighting-environments/)).

**Unity APV** uses bricks of 64 probes in a 4×4×4 grid, at 1, 3, 9, or 27 m
spacing. Each pixel samples the eight closest probes. The data is baked, so
geometry cannot move between Lighting Scenarios
([Unity](https://docs.unity3d.com/6000.0/Documentation/Manual/urp/probevolumes-concept.html)).
**Unreal VLM** places 4×4×4 SH sample bricks and interpolates per pixel. Epic's
figure is 0.02 ms per character on PS4, and 5 MB to 30 MB in its Paragon map
([Epic](https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-lightmaps-in-unreal-engine)).

Every row breaks when the sun or a box moves: the baked term assumes a fixed light
direction and fixed occluders.

## 3. Runtime probe grids: DDGI

DDGI stores spherical irradiance at each probe, plus mean and mean squared
distance to the nearest surface. Both go into octahedral maps, 8×8 for colour and
16×16 for depth, with a one-texel border, packed into an atlas
([§3](https://jcgt.org/published/0008/02/01/)).

The query interpolates eight probes with three weights: trilinear position,
backface, and visibility. Visibility adds a normal bias and uses a Chebyshev bound
on the mean and variance of depth, the same idea as variance shadow maps
([§5.2](https://jcgt.org/published/0008/02/01/)). That bound suppresses most
leaks. It is not a geometric test, so a thin wall still leaks when the depth
distribution is ambiguous.

| Item | Value | Hardware and settings | Source |
|---|---|---|---|
| Probe grid | 32×8×32 = 8192 | Largest test scenes | [Table 1](https://jcgt.org/published/0008/02/01/) |
| Rays per probe | 64 | Same | [Table 1](https://jcgt.org/published/0008/02/01/) |
| Ray throughput | 1.5–1.65 GRays/s | RTX 2080 Ti, 876k primitives | [Table 1](https://jcgt.org/published/0008/02/01/) |
| Ray cast | 0.8 ms | 1080p, 8192 probes, 64 rays | [Table 2](https://jcgt.org/published/0008/02/01/) |
| Probe update | 0.7 ms | Same | [Table 2](https://jcgt.org/published/0008/02/01/) |
| Irradiance gather | 0.5 ms | Same | [Table 2](https://jcgt.org/published/0008/02/01/) |
| Indirect total | 2.6 ms | Same | [Table 2](https://jcgt.org/published/0008/02/01/) |
| Full frame with glossy | 6 ms | 1920×1080, RTX 2080 Ti | [Figure 1](https://jcgt.org/published/0008/02/01/) |

The 6 ms headline includes glossy ray tracing. The indirect diffuse components
alone are 2.6 ms. The paper updates all probes every frame; adaptive selection
would cut the update cost ([§6.2](https://jcgt.org/published/0008/02/01/)).

Memory is small here. An 8×8 colour map at 32 bits per texel is 256 B; a 16×16
depth map at 32 bits per texel is 1 KB. That is about 1.25 KB per probe before
gutters, by arithmetic from the stated formats. A 512-probe volume is under 1 MB;
4096 probes are about 5 MB.

**Production fixes.** The follow-up paper adds probe relocation out of walls (at
most 45% of the cell), probe classification with off/sleeping/vigilant/awake
states (a 30–50% average speedup), one self-shadow bias instead of several, and
second-order glossy at maximum roughness
([Majercik et al. 2021](https://arxiv.org/abs/2009.10796),
[RTXGI](https://github.com/NVIDIAGameWorks/RTXGI-DDGI/blob/main/docs/DDGIVolume.md)).
NVIDIA's SDK adds 32 fixed rays, a variability metric, and an infinite scrolling
volume. It also says updates may run below frame rate or asynchronously
([RTXGI](https://github.com/NVIDIAGameWorks/RTXGI-DDGI/blob/main/docs/DDGIVolume.md)).

**Where it leaks.** Each bounce is seeded from the previous frame, so a small
bright light ghosts; the authors accept that they "trade some quality for
generality" ([§8.1](https://arxiv.org/abs/2009.10796)). Thin walls are the other
failure. The Chebyshev test compares a depth distribution, not a solid occluder. A
probe ray that misses a 0.3 m wall produces a bright sample, and interpolation
spreads it. Epic states the same limit for distance fields: "Walls should be no
thinner than 10 centimeters (cm) to avoid light leaking"
([Lumen](https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-technical-details-in-unreal-engine)).
The room walls are 0.3 m, above Epic's distance-field floor. The 2.0 m light lock
is harder: 1–2 m probe spacing cannot resolve its turns.

## 4. Screen space

Screen-space methods reuse the colour and depth buffers as a stand-in for the
scene. They gather screen-space radiance from the colour buffer. They are cheap
because the data exists. They are wrong for the same reason.

| Method | Input | Bounce | Shipping |
|---|---|---|---|
| SSDO ([Ritschel 2009](https://doi.org/10.1145/1507149.1507161)) | Depth, normals | One, local | Research, older engines |
| SSGI ([Unity HDRP](https://docs.unity3d.com/Packages/com.unity.render-pipelines.high-definition@17.0/manual/Override-Screen-Space-GI.html)) | Depth, colour | One | Unity HDRP |
| SSIL ([Godot](https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/introduction_to_global_illumination.html)) | Previous frame colour | One | Godot 4 |

Unity describes SSGI as using "the depth and color buffer of the screen to
calculate diffuse light bounces". It replaces lightmap and Light Probe data on
affected cameras. Ray marching uses one ray per pixel at full resolution, or one
ray per four pixels, and a miss falls back to probes, sky, or both
([Unity](https://docs.unity3d.com/Packages/com.unity.render-pipelines.high-definition@17.0/manual/reference-screen-space-global-illumination.html)).
Godot calls SSIL a "secondary source" and runs it at half resolution. It warns
that "its screen-space nature will result in some artifacts, especially when
objects enter and leave the screen"
([Godot](https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/introduction_to_global_illumination.html)).

**What it cannot see.** Off-screen geometry, backfaces, and anything behind the
camera. A lamp behind the player cannot bounce onto the wall in front. A sealed
room with no on-screen source stays dark, which is correct, but a corridor lit
through a door loses the bounce when the door leaves the frame.

## 5. World-space approximations

These methods build a representation that the camera does not limit.

**Voxel cone tracing.** Crassin et al. voxelize into a sparse voxel octree, filter
radiance into the hierarchy, and trace about five wide cones for diffuse plus one
narrow cone for specular. They report two bounces, dynamic content, and 25–70 fps
on a GTX 480
([Pacific Graphics 2011](https://research.nvidia.com/publication/interactive-indirect-illumination-using-voxel-cone-tracing),
[PDF](https://research.nvidia.com/sites/default/files/pubs/2011-09_Interactive-Indirect-Illumination/GIVoxels-pg2011-authors.pdf)).
The leak is set by voxel size: a wall thinner than a voxel does not occlude.

**SVOGI** is a family name for sparse-voxel-octree GI. I found no peer-reviewed
paper with that title. The published algorithm is Crassin et al.'s. Treat "SVOGI"
as a family name, not a citation.

**SDFGI** builds cascaded signed distance fields around the camera. Dynamic lights
work; dynamic occluders and emissive surfaces do not. It bounces once by default,
`Bounce Feedback` above 0.5 can cause "infinite feedback loops", convergence takes
about 25 frames, and moving a nearby static object makes the GI wrong until the
camera moves away and back
([Godot](https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_sdfgi.html)).

**Lumen** has four parts. The surface cache holds offline material cards, 12 per
mesh by default. The radiance cache stores lighting at hit points; Epic names it
for translucency, where layers other than the front use "the lower quality
Radiance Cache method". Final gather traces per-pixel rays and solves sky
lighting, including sky shadowing. Hardware ray tracing is optional and can light
at the hit instead of the cache
([Epic](https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-technical-details-in-unreal-engine),
[Lumen GI](https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-global-illumination-and-reflections-in-unreal-engine)).

Lumen's software path traces mesh distance fields for the first 2 m and a merged
global field after that. It covers 200 m, and thin or one-sided geometry leaks.
Epic's cost claim is 8 ms for GI and reflections at 1080p internal resolution on
next-generation consoles at the Epic scalability level. That is a vendor claim.
The same page gives the limits: 200 m, 10 cm walls, and multi-second propagation
([Epic](https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-technical-details-in-unreal-engine)).

## 6. Hardware ray tracing

The simplest hardware path is one diffuse ray per pixel, a shadow ray at the hit,
and a denoiser. Unity HDRP exposes exactly that: enable ray tracing under the SSGI
override, set a bounce count, denoise
([Unity](https://docs.unity3d.com/Packages/com.unity.render-pipelines.high-definition@17.0/manual/reference-screen-space-global-illumination.html)).
NVIDIA's NRD is the matching denoiser family
([NRD](https://github.com/NVIDIA-RTX/NRD)).

**ReSTIR GI** resamples indirect paths across pixels and frames. At one sample
per pixel it reports 9.3× to 166× lower MSE than plain path tracing
([HPG 2021](https://research.nvidia.com/publication/2021-06_restir-gi-path-resampling-real-time-path-tracing)).

| Title | Ships | Bounces | Denoiser | Source |
|---|---|---|---|---|
| Cyberpunk 2077, 1.62 | Path-traced Overdrive, "technology preview" | Not stated | DLSS | [CDPR, 11 Apr 2023](https://www.cyberpunk.net/en/news/47875/patch-1-62-ray-tracing-overdrive-mode) |
| Alan Wake 2 | Full path tracing, three presets | 3 high, 1 medium | NRD or DLSS RR | [NVIDIA, 24 Oct 2023](https://www.nvidia.com/en-us/geforce/news/alan-wake-2-dlss-3-5-full-ray-tracing-out-this-week) |
| DOOM: The Dark Ages | Path tracing in id Tech 8 | Not stated | DLSS RR | [NVIDIA, 30 Sep 2025](https://developer.nvidia.com/blog/how-id-software-used-neural-rendering-and-path-tracing-in-doom-the-dark-ages) |
| PRAGMATA, RE Requiem | Path tracing, direct light inside the tracer | Not stated | DLSS RR | [NVIDIA, 16 Jul 2026](https://developer.nvidia.com/blog/qa-how-capcom-brought-path-tracing-to-re-engine-across-pragmata-and-resident-evil-requiem/) |

CDPR recommends an RTX 4070 Ti or better, or a 3090 at 1080p and 30 fps, for the
Cyberpunk preview. Alan Wake 2 runs 3 bounces on High, 1 on Medium, and none on
Low, with ray-traced AO on the last hit
([NVIDIA](https://www.nvidia.com/en-us/geforce/news/alan-wake-2-dlss-3-5-full-ray-tracing-out-this-week)).

**Direct lighting moves into the tracer.** Capcom states that "direct lighting now
runs through the path tracer instead of shadow maps". It reimplemented ReSTIR GI
from the paper and added next-event estimation for emissive samples
([NVIDIA](https://developer.nvidia.com/blog/qa-how-capcom-brought-path-tracing-to-re-engine-across-pragmata-and-resident-evil-requiem/)).
Once you path trace, the shadow map and the GI pass are the same integral.

## 7. Radiance cascades

Radiance cascades are a hierarchy of radiance intervals. Near probes carry high
spatial and low angular resolution; far cascades do the opposite. The claim is
that this matches how penumbrae scale with distance, so the result is noiseless
without temporal accumulation
([Sannikov, WIP preprint](https://github.com/Raikiri/RadianceCascadesPaper)).

- **2023–2024, original.** A technical report in the JCGT template. The author
  states he never submitted it and it was never published. The implementation is
  2D and screen-space; the conclusion suggests world-space tracing as future work
  ([README](https://github.com/Raikiri/RadianceCascadesPaper)).
- **2025, 2D formalisation.** Holographic Radiance Cascades reports 1.85 ms at
  512×512 and 7.67 ms at 1024×1024 on an RTX 3080 Laptop
  ([arXiv](https://arxiv.org/abs/2505.02041)).
- **2026, sparse 3D.** Split Radiance Cascades stores world-space probes in a
  sparse hashmap and adds "ray splitting". It reports 8.6 ms on Sponza and 11.5 ms
  on San Miguel for one frame on an RTX 3080 Laptop; the teaser is 13.2 ms, of
  which 6.1 ms is 1 spp ray tracing
  ([arXiv](https://arxiv.org/abs/2607.20384)).

Split RC's own limits: it misses detail below the base probe spacing, leaks during
merging, over-blurs hard shadows, and stores radiance as 32-bit floats. It is not
a drop-in for a 1 ms budget.

**Does anyone ship it?** One data point. Split RC cites a GDC 2026 talk by
Tianlong Ruan, "The Evolution of Real-Time Global Illumination in 'Love and
Deepspace'", for 3D radiance cascades on mobile. I did not verify that talk. No
desktop title is confirmed by a first-party source. The author works at Grinding
Gear Games, but I found no GGG statement that Path of Exile 2 uses it.

## 8. Emissive surfaces

An emissive material returns light. It is not automatically a light source. It
contributes only when a GI ray hits it and the hit shader evaluates its emission,
or when the renderer samples it as an area light.

In this renderer the Lamp prefab has an emissive box and a point light; the
emissive term is added after the sun and point lights, and the light budget
uploads only the eight nearest lamps (`GLOSSARY.md`). A lamp outside the budget
glows but does not light. A GI method must treat it as an emitter explicitly, or
the probe data will show a glow that never bounces.

- **Lumen.** Emissive materials propagate through Final Gather "with no additional
  performance cost", but small bright emitters are noisy. Culled small meshes need
  the `Emissive Light Source` flag
  ([Epic](https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-global-illumination-and-reflections-in-unreal-engine),
  [troubleshooting](https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-technical-details-in-unreal-engine)).
- **Godot SDFGI.** Dynamic emissive surfaces are not supported. Emissive lighting
  updates only when an object enters a cascade
  ([Godot](https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/introduction_to_global_illumination.html)).

**Sampling.** A mesh light is an area light with many primitives. The standard
solution is next-event estimation (NEE): sample a point on the emitter, connect it
to the shading point, and combine that with BSDF sampling using multiple
importance sampling (MIS)
([Veach and Guibas 1995](https://doi.org/10.1145/218380.218498)). Capcom names
exactly this: "we use a dedicated sampling structure for Next Event Estimation"
because BSDF-only sampling of emissive hits is noisy
([NVIDIA](https://developer.nvidia.com/blog/qa-how-capcom-brought-path-tracing-to-re-engine-across-pragmata-and-resident-evil-requiem/)).

## 9. Sky light, sky visibility, and portals

Sky light is an environment emitter:

```
L_sky(x) = (ρ/π) ∫ L_environment(ω) · V(x, ω) · (n·ω)⁺ dω
```

A sealed room is dark for a physical reason. Every sky direction has `V = 0`
except the door. The door admits a solid angle of sky. That light lands on the
floor and walls, and each bounce multiplies by an albedo below one. With no
emitter inside, the room's radiance is a finite series in the door's solid angle.
It is dim, not zero, and it falls off with each turn of the lock. The arena's room
is built to show this: the four-turn lock admits no straight sun ray
(`GLOSSARY.md`, `scenarios/room-lighting.json`).

**Ambient fill is not that.** A constant ambient term has no `V`. It adds the same
light to the sealed room as to the open floor. Unreal states the physical version:
"A Sky Light should be used instead of the Ambient Cubemap to represent the sky's
light because Sky Lights support local shadowing, which prevents indoor areas from
getting lit by the sky"
([Epic](https://dev.epicgames.com/documentation/en-us/unreal-engine/sky-lights-in-unreal-engine)).
Lumen exposes `Skylight Leaking` as a "non-physically based" art knob to keep
interiors from going fully black
([Epic](https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-global-illumination-and-reflections-in-unreal-engine)).
That setting is the honest name for an ambient fill.

- **Unity APV** bakes a per-probe occlusion scalar and multiplies it by the ambient
  probe colour. `Sky Direction` adds a direction per probe for caves and windows
  ([Unity](https://docs.unity3d.com/6000.0/Documentation/Manual/urp/probevolumes-skyocclusion.html)).
- **Unreal Sky Light** uses Distance Field AO for movable shadows and baked bent
  normals for stationary ones. Epic's figure for Real Time Capture of a 128×128×6
  cubemap is about 1.465 ms on PS4, or at most 0.20 ms per frame when time-sliced
  over nine frames. `RecaptureSky()` needs at least 120 ms and hitches
  ([Epic](https://dev.epicgames.com/documentation/en-us/unreal-engine/sky-lights-in-unreal-engine)).

**Portals are a bake-time tool.** Unreal's Lightmass Portals tell the lightmapper
to send more rays through an opening, for skylights and emissive meshes. Epic's
limits are explicit: portals are not occluded by anything, and they belong in very
small levels, or build times grow badly
([Epic](https://dev.epicgames.com/documentation/en-us/unreal-engine/lightmass-portals-in-unreal-engine)).
They do not exist at runtime and do not help a moving sun.

## 10. Comparison

| Method | Computes | Inputs | Dyn. boxes | Dyn. sun | Cost | Quality | Main artifact | Shipping |
|---|---|---|---|---|---|---|---|---|
| Lightmap | Baked surface irradiance | UV2, static geo | No | No | One fetch | High static | Baked shadow on moved object | Lightmass |
| Irradiance volume / PRT | SH irradiance or transfer | Bake, SH | No | PRT only, low freq | Dot product | Low freq | No local occlusion change | Older engines |
| APV / VLM | Baked probe grid | Bake | No | No | Per-pixel lookup | Medium | Thin-wall leaks | Unity 6, UE5 |
| DDGI | Irradiance + depth moments | TLAS, rays | Yes | Yes | 2.6 ms indirect, 2080 Ti, 1080p | Medium | Probe leak, bounce lag | RTXGI, Unity, UE4 |
| SSGI / SSIL | One screen-space bounce | Depth, colour | Yes | Yes | 1 ray/pixel or 1/4 | Low–medium | Off-screen blindness | HDRP, Godot |
| Voxel cone tracing | Voxel radiance, 2 bounces | Voxelization | Yes | Yes | 25–70 fps, GTX 480 | Medium | Voxel leaks | Crassin prototype |
| SDFGI | Cascaded SDF radiance | SDF, cascades | No | Yes | High; 25 frames to converge | Medium | Cascade shift, leaks | Godot 4 |
| Lumen | Cache + gather | Cards, SDF or BVH | Yes | Yes | 8 ms GI+refl, consoles, 1080p (vendor) | High | 200 m, thin walls | UE5 |
| RTGI + denoiser | One traced bounce | BVH, denoiser | Yes | Yes | Not stated | High | Denoiser smear | Unity HDRP |
| ReSTIR GI / path tracing | Multi-bounce paths | BVH, reservoirs | Yes | Yes | Whole frame | Highest | Noise, denoiser | Cyberpunk, AW2, DOOM, RE |
| Radiance cascades | Radiance intervals | Probes, hash | Yes | Yes | 8.6–11.5 ms, 3080 Laptop | High | Detail below spacing | Love and Deepspace (unverified) |

## 11. Decision guide for this scene

Constraints: 40 m arena, 4 m walls (`src/game/arena.odin`); an 11 m room with
0.3 m walls and a 2.0 m light lock (`src/game/arena_room.odin`, `GLOSSARY.md`);
128 placed objects today (`src/game/prefabs.odin`), 256 in the brief; one sun with
a 0.53° disk and eight point lights (`GLOSSARY.md`); 1.11 ms GPU total at 1440p on
an RX 9060 XT, with 0.80 ms in the scene pass
(`docs/evidence/perf-scene-pass.md`). The GI budget is 0–0.9 ms.

The first question is not "which method is best". It is "which light must exist
that does not exist now".

| Goal | Method that fits | Why | Cost |
|---|---|---|---|
| Stop flat outdoor shading | Sky visibility + AO | Sky is the only large emitter | Near zero; not GI |
| Red wall tints the floor | DDGI, coarse grid, half-res gather | Needs off-screen colour bleed | ~0.3 ms, estimate |
| Door spills light into the lock | DDGI with a finer volume near the room | Screen space loses the door off-frame | More probes, more leak risk |
| Crates cast coloured bounce | DDGI | Dynamic occluders are in the TLAS | Update follows box motion |
| Match a path-traced reference | Path tracing + denoiser | Only full transport does this | Whole-frame change |

**Cheap paths.** Sky visibility plus a bent normal is not GI: no bounce. Screen
space is bounded by the frame: one ray per four pixels cannot bounce light from
an off-screen lamp, and the bounce changes when the camera turns.

**DDGI.** The only family that handles a moving sun, moving crates, and off-screen
transport in one structure. Arithmetic from the DDGI paper:

- A 2.5 m grid over 40×4×40 m is 16×2×16 = 512 probes, about 0.65 MB.
- 64 rays per probe is 32,768 rays per frame. At 1.6 GRays/s that is about
  0.02 ms of raw ray cast, on a faster RT GPU.
- Probe update at 1/16 of the paper's 8192 probes is about 0.04 ms.
- The gather does not shrink. It was 0.5 ms at 1080p on a 2080 Ti and scales with
  pixels. At 1440p it is about 0.9 ms; at half resolution, about 0.22 ms.

That sums to roughly 0.3 ms at half resolution, plus pass overhead, on hardware
that is not the 2080 Ti. This is an estimate, not a measurement. The risk is
quality: 2.5 m probes cannot resolve a 0.3 m wall or a 2 m corridor. The light
lock will leak unless the room gets a finer volume or hand-placed probes.

**Out of budget.** Path tracing needs RTX 40-class hardware, and 3D radiance
cascades cost 8.6–11.5 ms on an RTX 3080 Laptop
([Split RC](https://arxiv.org/abs/2607.20384)).

No source measures GI on an RX 9060 XT at 1440p. The numbers above come from a
2080 Ti, a 3080 Laptop, a GTX 480, and console claims. The local probe is the
existing scene pass: 0.80 ms at 1440p with 8 AO rays per pixel. A GI prototype
that adds more than 0.5 ms breaks the 2 ms ceiling. Measure the gather first, with
the room in frame.

## 12. Reading list

Read in this order.

1. **Kajiya 1986; PBRT §9.2.** The integral, then the Lambertian BRDF.
   [Kajiya](https://www.cs.princeton.edu/courses/archive/fall03/cs526/papers/kajiya86.pdf),
   [PBRT](https://pbr-book.org/4ed/Reflection_Models/Diffuse_Reflection).
2. **Greger 1998; Sloan 2002.** The baked probe grid, then precomputed transfer.
   [Greger](https://doi.org/10.1109/38.656788),
   [Sloan](https://www.microsoft.com/en-us/research/publication/precomputed-radiance-transfer-real-time-rendering-dynamic-low-frequency-lighting-environments/).
3. **Majercik et al., JCGT 8(2), 2019.** DDGI and its cost tables.
   [JCGT](https://jcgt.org/published/0008/02/01/).
4. **Majercik et al., JCGT 10(2), 2021.** Relocation and classification.
   [arXiv](https://arxiv.org/abs/2009.10796).
5. **NVIDIA RTXGI DDGI reference.** Fixed rays and scrolling volumes.
   [GitHub](https://github.com/NVIDIAGameWorks/RTXGI-DDGI/blob/main/docs/DDGIVolume.md).
6. **Ouyang et al., HPG 2021.** ReSTIR GI.
   [NVIDIA](https://research.nvidia.com/publication/2021-06_restir-gi-path-resampling-real-time-path-tracing).
7. **Epic, Lumen documentation.** A shipping hybrid system, limits included.
   [Lumen GI](https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-global-illumination-and-reflections-in-unreal-engine),
   [details](https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-technical-details-in-unreal-engine).
8. **Crassin et al., Pacific Graphics 2011.** Voxel cone tracing, two bounces.
   [PDF](https://research.nvidia.com/sites/default/files/pubs/2011-09_Interactive-Indirect-Illumination/GIVoxels-pg2011-authors.pdf).
9. **Sannikov, WIP 2023–2024; Freeman et al., 2026.** Radiance cascades, 2D to 3D.
   [Sannikov](https://github.com/Raikiri/RadianceCascadesPaper),
   [Split RC](https://arxiv.org/abs/2607.20384).
10. **Capcom Q&A, July 2026.** Path tracing in RE Engine.
    [NVIDIA](https://developer.nvidia.com/blog/qa-how-capcom-brought-path-tracing-to-re-engine-across-pragmata-and-resident-evil-requiem/).

## 13. Open problems, as the papers state them

- **DDGI:** small bright lights ghost because each bounce is seeded from the
  previous frame; a per-frame ray budget would need per-probe apportioning
  ([§8.1](https://arxiv.org/abs/2009.10796)).
- **Production probes:** relocation is limited to the voxel; second-order glossy
  is forced to maximum roughness ([§5, §8.1](https://arxiv.org/abs/2009.10796)).
- **Split RC:** detail below probe spacing, leaks during merging, over-blurred hard
  shadows, 32-bit radiance ([§7](https://arxiv.org/abs/2607.20384)).
- **Lumen:** 200 m range, thin-wall leaks, multi-second propagation
  ([Epic](https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-technical-details-in-unreal-engine)).
- **SDFGI:** static occluders only, cascade shifts, feedback above 0.5 can diverge
  ([Godot](https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_sdfgi.html)).

## What did not check out

- **Radiance cascades are not a published paper.** The document uses the JCGT
  template, but the author states it was never submitted or published.
- **RTXGI v2 does not contain DDGI.** Version 2 ships Neural Radiance Cache and
  SHaRC. DDGI lives in RTXGI-DDGI, version 1.3
  ([RTXGI](https://github.com/NVIDIA-RTX/RTXGI),
  [DDGI](https://github.com/NVIDIAGameWorks/RTXGI-DDGI)).
- **There is no "SVOGI paper".** The name covers a family; the published algorithm
  is Crassin et al. 2011.
- **Unity APV is baked, not runtime.** Sky occlusion is a baked scalar.
- **Unreal Lightmass Portals are not runtime portals.** They are bake-time ray
  hints, not occluded, and limited to small levels.
- **Lumen's "infinite bounces" is a vendor claim.** The docs give a 200 m range,
  10 cm walls, and multi-second propagation.
- **Cyberpunk Overdrive is a "technology preview".** CDPR recommends an RTX 40
  card, or a 3090 at 1080p and 30 fps.
- **The DOOM article is dated 30 September 2025**, not the June 2025 release.
- **"SSGI" is a screen-space one-bounce approximation.** HDRP's page says it
  replaces lightmaps and probes and falls back on a ray miss.
- **No source measures GI on an RX 9060 XT.** The 0.9 ms gather estimate is
  pixel-count scaling from a 2080 Ti measurement.
- **The "Love and Deepspace uses radiance cascades" claim is second-hand.** It
  rests on a GDC 2026 talk cited by Split RC. I did not verify the talk.
- **ACM and IEEE blocked automated fetches.** The SSDO, PRT, and MIS DOIs returned
  403; the IEEE irradiance-volume DOI returned an empty 202. Metadata came from
  OpenAlex and publisher pages.
- **Search engines were unreliable.** Web search returned 403, DuckDuckGo served a
  CAPTCHA, and Bing returned unrelated results. Discovery used arXiv, OpenAlex,
  the Wayback CDX index, and direct documentation URLs.
