# Global illumination: options for harbagsa

Research report. No implementation. No shader code. This is the decision-facing
summary. The detail and the citations are in three companion notes:

- [`global-illumination.md`](global-illumination.md) — the method survey.
- [`global-illumination-reconstruction.md`](global-illumination-reconstruction.md)
  — denoisers, temporal reuse, caches.
- [`global-illumination-fit.md`](global-illumination-fit.md) — the pass-graph fit,
  file by file.

> **Scope.** The ranking below assumes the current arena: a sun, a sky, and a
> handful of lamps. The owner's target is interiors, no sun, and many lights.
> Read [`global-illumination-interiors.md`](global-illumination-interiors.md)
> first for that target. The method descriptions here still apply; the ranking
> and the sky-first recommendation do not.

Every cost figure below is either measured on stated hardware or marked as an
estimate.

## 1. Why the planes are black

The lit shader computes direct light only
(`src/renderer/shaders/box.frag`, `main`):

```glsl
vec3 lit = (diffuse * SUN_COLOR * visibility + point_light_radiance(...)) * ao;
vec3 color = v_color * lit + v_color * object.color.a;
```

A surface with `dot(normal, to_light) <= 0` gets zero from the sun term. A lamp
contributes only when it is in range, in front of the surface, and unoccluded.
AO multiplies the result. AO cannot add light. So a shaded plane that no lamp
reaches is exactly black, by construction.

That is correct output for a renderer with no environment light and no bounce.
The missing terms are:

- **Environment light.** The sky is drawn as a background but emits nothing.
- **Transport.** Light that lands on a surface reflects and lights other
  surfaces. Nothing computes that.
- **Emissive transport.** A lamp's emissive face is added to its own colour. It
  lights nothing.

There are two different things called "ambient":

| Term | Has visibility | Lights the sealed room | Physical |
|---|---|---|---|
| Flat ambient / hemisphere ramp | No | Yes | No |
| Sky light with visibility | Yes | No, unless a sky ray escapes | Yes |

ADR 0028 removed the first. The second was never added. That is the gap.

## 2. What a proper system contains

1. **An emitter set.** Sun disk, sky dome, lamps as point lights, and optionally
   the lamp's emissive face as an area emitter.
2. **A visibility-aware gather.** For each visible point, integrate incoming
   radiance over the hemisphere with a ray.
3. **At least one bounce.** The first hit returns the radiance that direct light
   left there. A miss returns sky radiance if the sky is an emitter.
4. **Reconstruction.** Few samples per pixel need temporal and usually spatial
   filtering. TAA alone is a weak denoiser for heavy-tailed radiance.
5. **Validation.** A path-traced reference for quality, and the room capture as a
   hard gate that the fill did not come back.

The options below differ in how they represent steps 2 and 3.

## 3. The options

### Option 0 — Sky visibility (environment light, no bounce)

**What it does.** Trace N cosine-weighted rays from each surface. A ray that
escapes to the sky returns the sky gradient. A ray that hits geometry returns
zero. Multiply by albedo. This is environment lighting with real occlusion, not a
constant fill.

**Cost.** Reuses the existing AO ray loop. The AO build measured about 0.105 ms
per marginal ray at 1440p on the RX 9060 XT. Sky rays are longer than the 1.5 m
AO rays, so budget 0.10–0.18 ms per ray (estimate). Four rays: 0.4–0.7 ms. It can
replace the 0.91 ms of AO rays.

**Fixes.** Shaded outdoor planes stop being black. The colour comes from the sky,
so a blue sky fills with blue. A sealed room stays black by construction: every
sky ray hits the shell. No new pass, no new target, no new descriptor.

**Does not fix.** No bounce. A lamp still does not light around a corner. A
doorway sun patch does not spill into the tunnel. No colour bleeding.

**Artifacts.** Noise at low ray counts, but the integrand is bounded and smooth,
so it converges faster than a bounce. The sun disk must be removed from the
environment term or the sun is counted twice. It couples the background gradient
to the lighting, so the sky colour becomes a lighting control.

**Verdict.** The smallest physically correct answer to "why are shaded planes
black". Not global illumination.

### Option 1 — One-bounce diffuse GI in the lit pass

**What it does.** Trace 1–4 cosine-weighted rays. On a hit, shade the hit point
with the sun and the lamps, then return `albedo/π × that radiance`. On a miss,
return sky radiance. Accumulate with the existing TAA. No recursion, no second
bounce.

**Cost.** Same ray loop as option 0, plus one shadow ray at each hit. Estimate
0.10–0.18 ms per GI ray at 1440p. Four rays: 0.4–0.7 ms, with one sun ray per hit.
The eight AO rays it can replace cost 0.91 ms. Net cost is roughly neutral at
four rays and cheaper at one to two.

**Fixes.** Real indirect light. A sunlit floor bounces onto the wall above it. A
lamp spills past its direct cone. The doorway patch brightens the first tunnel
lane. A crate darkens the floor under it. The sealed room stays black until a
lamp or the door admits light, and then the light spreads by transport rather
than by fill.

**Does not fix.** Multi-bounce. A deep tunnel stays darker than a path tracer
says. No specular GI. The material is one flat colour, so the bounce is a tint
and a gradient, not detail.

**Artifacts.** Noise and boiling, worst after a TAA reset. Fireflies when a ray
hits the emissive lamp face. Temporal lag on disocclusion. One important
measured constraint: the sample phase is `frame_count % 64`
(`src/renderer/debug.odin`, `taa_shadow_phase`), so a 1 spp sequence visits 64
directions and the 512-frame history averages duplicates. One spp gives 64
effective samples, about 11 sRGB levels of error on a 0.10 linear term. Four spp
gives 256, about 5.5 levels, unless the phase sequence is extended to 512.

**New machinery.** None in the pass graph. One gated `gi` override in the shape
of `ao`. A `vec4` in the camera uniform. The TLAS instance custom index must be
set so a hit can read the object colour, because it is never set today
(`src/renderer/acceleration.odin`).

**Verdict.** The smallest real GI system for this renderer. The noise is the
price, and TAA is the only reconstructor that exists.

### Option 2 — DDGI probe grid

**What it does.** Place a grid of probes over the arena. Each probe stores an 8×8
octahedral irradiance map and a 16×16 depth/depth² map. Probes trace rays on a
round-robin schedule and blend into their maps with hysteresis. The lit pass
samples the eight probes around the surface, weighted by position, backface
direction, and a Chebyshev visibility test.

**Cost.** The update is small: a 2.5 m grid over 40×4×40 m is 512 probes, under
1 MB, and 64 rays per probe is 32,768 rays — about 0.02 ms of raw ray cast on a
faster card (estimate). The gather is the cost. The paper measures 0.5 ms for the
per-pixel probe sample at 1080p on an RTX 2080 Ti with 8192 probes
([JCGT 8(2), Table 2](https://jcgt.org/published/0008/02/01/)). It scales with
pixels: about 0.9 ms at 1440p, about 0.22 ms at half resolution.

**Fixes.** Noise-free indirect light with no screen dependence. Off-screen
transport works. A moving sun and moving crates are handled by the TLAS. Probes
naturally give multi-bounce through the hysteresis feedback. Latency is the
trade: a moving sun crawls at `w = 0.97` (8.9 s to 63%), and probe light leaks
through thin or single-sided walls.

**Does not fix.** Detail below the probe spacing. A 2.5 m grid cannot resolve the
0.3 m room walls or the 2.0 m light lock. The room proof is the risk: light leaks
around the four turns, and the current gate expects the chamber at the dither
floor. A finer volume for the room, probe relocation, and classification are
extra work.

**Verdict.** The only option that is both noise-free and off-screen correct at
this scale. It trades accuracy for stability, and the sealed room is where that
trade shows.

### Option 3 — Screen-space GI

**What it does.** March the depth buffer from each visible surface and gather
colour from the scene target. One bounce, half resolution, bilateral upsample.

**Cost.** Estimate 0.2–0.4 ms at 1440p for 8–16 steps plus the upsample.

**Fixes.** Cheap local colour bleeding when the emitter and receiver are both on
screen.

**Does not fix.** Anything off screen. It is blind behind the camera and at the
frame edge. The room is lit through a door that is often off screen. It also
duplicates the AO term, which approximates the same local integral.

**Verdict.** A poor fit for a game whose proof is a sealed room. It would fail
the exact view the project gates.

### Option 4 — Path tracing / ReSTIR GI with a denoiser

**What it does.** Trace multi-bounce paths, reuse them across pixels and frames,
then run a production denoiser. This is what the 2025–2026 shipping high end
does: Cyberpunk RT Overdrive, Alan Wake 2, DOOM: The Dark Ages, Capcom's RE
ENGINE titles.

**Cost.** ReSTIR GI reports 8.9 ms at 1080p on an RTX 3090 against 8.0 ms of path
tracing, with 475 MB of reservoirs. NRD ReBLUR costs 2.55 ms at 1440p on an RTX
4080 for diffuse plus specular, and needs a G-buffer with normals, roughness, and
motion. NRC needs Tensor Cores. ORCA is not shipped. None of these fit a 2 ms
frame, and the target is an RX 9060 XT on RADV.

**Fixes.** Multi-bounce, specular GI, the closest match to a reference.

**Does not fix.** Nothing visually, but it adds a G-buffer, a denoiser, hundreds
of MB, and a hardware floor the project does not have.

**Verdict.** The right destination for a path-traced showcase, not for a movement
demo with eight lamps. Useful as an offline reference to judge the cheaper
options.

### Option 5 — Radiance cascades

**What it does.** A hierarchy of radiance intervals. Near cascades carry high
spatial and low angular resolution, far cascades the opposite, so penumbrae and
detail scale without temporal noise.

**Cost.** The 2D formalisation is 1.85 ms at 512×512 and 7.67 ms at 1024×1024 on
an RTX 3080 Laptop. The 2026 sparse 3D version is 8.6 ms on Sponza and 11.5 ms
on San Miguel for one frame on the same laptop.

**Verdict.** The most interesting research thread in the 2025–2026 record. Not a
candidate for this budget.

## 4. Comparison

Costs are at 1440p. "Est." means arithmetic from a measured per-ray cost, not a
measurement of this option.

| Option | Adds | New pass / target | Cost | Quality | Main artifact | Room stays black | Fits 2 ms |
|---|---|---|---|---|---|---|---|
| 0. Sky visibility | Environment light with occlusion | None | 0.4–0.7 ms est. | Smooth, bounded | Noise at low rays; sky is now a light | Yes | Yes, if AO retires |
| 1. One bounce | Indirect diffuse + sky | None | 0.4–0.7 ms est. | Real bounce, noisy | Fireflies, lag, 64-sample phase | Yes | Yes, if AO retires |
| 2. DDGI | Probe-grid irradiance | Probe pass + buffer | 0.22 ms half-res gather, est. | Noise-free, low frequency | Leak through the room; sun lag | Only with extra work | Tight; ~2.0–2.3 ms |
| 3. SSGI | Screen-space bounce | SSGI pass + target | 0.2–0.4 ms est. | Local, view-dependent | Blind off screen | Yes, but no light either | Yes, if AO retires |
| 4. Path tracer | Full transport | G-buffer, reservoirs, denoiser | 8+ ms | Reference | Denoiser smear, memory | Yes | No |
| 5. Radiance cascades | Radiance intervals | Sparse probe structure | 8.6–11.5 ms | High | Detail below spacing | Unknown | No |

## 5. What the evidence says

- **AO is not GI.** It has no incident radiance and no albedo, so it cannot add
  light. The ambient-occlusion note in this folder covers that in detail.
- **The cheapest real fix is the sky.** A visibility-aware environment light is
  physically correct, and it keeps the sealed room black by construction. Unreal
  states the same thing about Sky Lights: local shadowing is what stops indoor
  areas from being lit by the sky
  ([Epic](https://dev.epicgames.com/documentation/en-us/unreal-engine/sky-lights-in-unreal-engine)).
- **One bounce is cheap but noisy.** The variance comes from the radiance
  distribution, not the visibility count. A single secondary hit can be 100× the
  neighbourhood mean, which is why clamping is energy loss and why TAA alone is
  weak at disocclusion.
- **DDGI is the stable choice but not the accurate one.** It is noise-free and
  off-screen correct, and its own paper accepts leaks and latency. The 2.5 m
  grid cannot resolve the room.
- **Screen space fails the room.** Epic says screen traces make indirect lighting
  view-dependent and cannot support it correctly
  ([Lumen](https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-technical-details-in-unreal-engine)).
- **The high end is path tracing.** Capcom moved direct lighting into the path
  tracer in 2026 and reimplemented ReSTIR GI. That is the direction, at a cost
  this project does not pay today.
- **Radiance cascades are real but expensive.** Split Radiance Cascades is a July
  2026 paper, and its own numbers are 8.6–11.5 ms on a laptop 3080.

## 6. The budget assumption

All of the above assumes the project keeps its current target of roughly 2 ms GPU
total at 1440p. That target is self-imposed; the display frame is 16.7 ms at
60 Hz.

| Target | What opens up |
|---|---|
| 2 ms total | Option 0 or 1, but only by retiring the 0.91 ms of AO rays. On top of today's AO build the budget is roughly zero. |
| 3 ms total | Option 0 or 1 on top of AO, or option 2 at half resolution. |
| 4–5 ms total | Option 2 at full resolution, or option 1 with a spatial filter. |
| 8–10 ms total | A light path tracer with a cheap denoiser, or DDGI plus one bounce. |
| 16 ms total | A real path tracer at reduced resolution, or ReSTIR GI with NRD-class filtering. |

The current scene pass has no post-ADR-0028 measurement. The last AO build
measured 2.17 ms scene and 2.611 ms total at 1440p; the pre-AO optimization
brought the scene to 0.80 ms. Expect 1.5–2.0 ms now. Measure before choosing a
budget.

The accounting matters. At 2 ms total, GI has no room on top of the AO build.
Options 0 and 1 are affordable only because they reuse the eight AO rays. That
is a coupled decision, not a free one: the same 0.91 ms either estimates
visibility for direct light or traces indirect light.

## 7. How the options map to goals

This is not a recommendation. It is the fit between a goal and an option.

| Goal | Option that fits | Why |
|---|---|---|
| Shaded planes are not black | 0 | Sky visibility is the only emitter large enough, and it is physical. |
| The room stays black | 0, 1, or 4 | All three have real visibility. 2 needs extra work; 3 fails the view. |
| A lamp spills around a corner | 1 or 2 | Needs transport, not environment. |
| The doorway patch fills the tunnel | 1 or 2 | The door is often off screen, so 3 loses it. |
| No noise, no boiling | 2 | Probes do not depend on the screen or TAA. |
| Match a path-traced reference | 4 | Only full transport does that. |
| Keep the pass graph small | 0 or 1 | No new pass, target, or descriptor. |
| Keep the flat-colour look | 0 | A sky tint is low-frequency and does not compete with the palette. |
| Colour bleeding between walls | 1 or 2 | One flat hue per surface, so expect a tint, not detail. |

## 8. What is not an option here

- **Lightmaps, APV, PRT, irradiance volumes.** The sun moves live, crates move,
  and the arena ships with a four-turn room. Baked transport assumes fixed
  geometry and a fixed light direction.
- **SSAO / GTAO as a substitute.** They are visibility terms. They cannot add
  light.
- **A constant ambient term.** It lights the sealed room, which is the thing
  ADR 0028 exists to prevent.
- **Lumen or SDFGI as-is.** Lumen is a 200 m, 8 ms console system with a surface
  cache and a radiance cache. Godot's SDFGI is static-occluder only and takes 25
  frames to converge.

## 9. Open decisions

These are the forks the report leaves open. No answer is assumed.

1. **What is the frame budget?** 2 ms, 5 ms, or 16 ms. The option ranking changes
   with the answer.
2. **Is the sky allowed to light the scene?** Yes makes the background and the
   lighting one function and lowers the contrast ADR 0028 chose. No keeps the sky
   as art and collapses the fill to bounce from the sun and lamps only.
3. **Does AO retire?** A real indirect term carries its own visibility, so AO on
   direct light becomes double counting. Retiring it frees 0.91 ms and makes
   contact corners brighter until the bounce fills them. Keeping it preserves
   the current look.
4. **Does the lamp's emissive face emit?** Today it glows and lights nothing. As
   an emitter it gives the room a real source when a lamp is placed, at the cost
   of fireflies unless it is sampled explicitly.
5. **Is a flat tint enough?** The material is one colour per object. GI will
   change luminance and hue, not detail. If the look needs detail, that is a
   material change, not a GI change.

## 10. Reading list

Read in this order. Every link is first-party or the paper itself.

1. **Kajiya 1986; PBRT §9.2.** The transport integral and the Lambertian BRDF.
   [Kajiya](https://www.cs.princeton.edu/courses/archive/fall03/cs526/papers/kajiya86.pdf),
   [PBRT](https://pbr-book.org/4ed/Reflection_Models/Diffuse_Reflection).
2. **Majercik et al., "Dynamic Diffuse Global Illumination with Ray-Traced
   Irradiance Fields", JCGT 8(2), 2019.** The DDGI paper, with cost tables and
   leak limits. [JCGT](https://jcgt.org/published/0008/02/01/).
3. **Majercik et al., JCGT 10(2), 2021.** Probe relocation and classification.
   [arXiv](https://arxiv.org/abs/2009.10796).
4. **Ouyang et al., "ReSTIR GI", HPG 2021.** Path resampling and its bias.
   [NVIDIA](https://research.nvidia.com/publication/2021-06_restir-gi-path-resampling-real-time-path-tracing).
5. **Schied et al., "Spatiotemporal Variance-Guided Filtering", HPG 2017.** The
   denoising baseline. [PDF](https://cg.ivd.kit.edu/publications/2017/svgf/svgf_preprint.pdf).
6. **Epic, Lumen documentation.** A shipping hybrid, limits included.
   [Lumen GI](https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-global-illumination-and-reflections-in-unreal-engine),
   [technical details](https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-technical-details-in-unreal-engine).
7. **Crassin et al., "Interactive Indirect Illumination Using Voxel Cone
   Tracing", Pacific Graphics 2011.** The world-space alternative.
   [PDF](https://research.nvidia.com/sites/default/files/pubs/2011-09_Interactive-Indirect-Illumination/GIVoxels-pg2011-authors.pdf).
8. **Freeman, Sannikov, Pitt-Francis, "Split Radiance Cascades", 2026.** The
   current research thread. [arXiv](https://arxiv.org/abs/2607.20384).
9. **Boissé et al., "GI-1.0", 2023.** A two-level radiance cache, and a clear
   comparison of probes against reservoirs.
   [arXiv](https://arxiv.org/abs/2310.19855).
10. **NVIDIA NRD.** The production denoiser contract and costs.
    [GitHub](https://github.com/NVIDIA-RTX/NRD).

## 11. Sources for the local numbers

- Current lighting model: `src/renderer/shaders/box.frag`.
- Ray costs and the AO build: `docs/adr/0017-sky-ambient-and-ray-traced-ambient-occlusion.md`.
- The direct-light decision: `docs/adr/0028-direct-light-with-surface-occlusion.md`.
- Scene pass measurement: `docs/evidence/perf-scene-pass.md`.
- Lamp cost: `docs/evidence/perf-lamps.md`.
- Room proof: `docs/evidence/room-lighting.md`.
- Sample phase: `src/renderer/debug.odin`, `taa_shadow_phase`.
- History and targets: `src/renderer/taa.odin`.
