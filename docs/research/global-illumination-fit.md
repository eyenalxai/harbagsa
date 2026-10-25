# Global illumination: which architecture fits this renderer

Research note. No shader code, no implementation plan. External claims link to
their source; internal claims name a file and a line. Estimates are marked.

Companion notes: [`global-illumination.md`](global-illumination.md) (the method
survey) and
[`global-illumination-reconstruction.md`](global-illumination-reconstruction.md)
(denoisers, temporal reuse, caches).

> **Scope.** This note assumes the current arena with a sun. For the owner's
> interior, many-light target, the verdict changes. Read
> [`global-illumination-interiors.md`](global-illumination-interiors.md) instead.
> The pass-graph seams and the ray-cost arithmetic below still apply.

**Verdict.** Fit a one-bounce gather into the lit pass and retire the
ambient-occlusion rays. The renderer already has the TLAS, the ray-query path, the
light buffer, and a 32-bit TAA history. A probe grid or a screen-space pass adds
a pass for a signal this scene does not need; a radiance cache adds a G-buffer and
a denoiser that cost more than the whole frame.

## The renderer as it stands

Pass order: `Tlas → Depth → Scene → Sky → Taa → Overlay`
(`src/perf/perf.odin:27-50`, walked at `src/renderer/scene_draw.odin:84-89`).
`Scene` is the lit pass (`src/renderer/pass_builders.odin:62-105`).

| Fact | Value | Source |
| --- | --- | --- |
| Targets | scene and velocity 16-bit, history 32-bit | `src/renderer/taa.odin:9-15` |
| History | 512-frame cap, reset on >2 m or >45° | `src/renderer/taa.odin:18-23, 245-247` |
| Rays per pixel | 16 sun, 8 occlusion, one per in-range lamp | `box.frag:44, 115-163` |
| Occlusion | 8 any-hit rays, 1.5 m, strength 0.5 | `box.frag:174-198`, `scene.odin:26-28` |
| Point lights | 8 active, nearest to camera | `lights.odin:9`, `src/game/lights.odin:142-177` |
| Scene | 40 x 40 x 4 m arena, 256 instances, 200 m far plane | `arena.odin:6-8`, `uniforms.odin:6`, `scene.odin:11` |
| Acceleration | one cube BLAS, TLAS rebuilt per frame, 0.17 ms | `acceleration_build.odin:6-100`, `perf-baseline.md:38` |
| Sample phase | 64 frames, `frame_count % 64`; jitter 8 frames | `debug.odin:68-72`, `jitter.odin:6` |

The whole lighting model (`src/renderer/shaders/box.frag:224-225`) is
`(sun * diffuse * visibility + point_lights) * occlusion`, plus `albedo * emissive`.

There is no ambient term. The sky is a background (`docs/adr/0028:21-31`). The
occlusion multiplies the **direct** light: physically odd, but deliberate, since
it is the only contact cue (`docs/adr/0028:24-25`).

The material is one flat colour per object. The cube mesh has position and
normal only (`box.vert:3-4`), `v_color` is the object colour (`box.vert:34`), and
`object.color.a` is one emissive scalar (`box.frag:225`). No texture, no vertex
colour.

## Budget: what a ray costs

ADR 0017 reports the AO feature at +0.91 ms at 1440p, and four rays save
0.42 ms (`docs/adr/0017:96-98`). Two equations give the line:
`T(8) - T(4) = 4b = 0.42` gives `b = 0.105 ms` marginal per ray, and
`T(8) = a + 8b = 0.91` gives `a = 0.07 ms` fixed.

The quoted 0.11 is `0.91 / 8`, the average at eight rays. The underlying slope is
0.105 ms, for incoherent hemisphere rays on the old ambient build, not a hardware
constant. It is consistent with the 2.17 ms scene pass in the same ADR:
`2.17 / 24 = 0.090 ms` per ray on average, and incoherent AO rays cost more than
coherent sun rays (`docs/adr/0017:99-100`).

The point-light data gives a lower figure: 0.0555 ms per shadow ray at 1440p
(`docs/evidence/perf-lamps.md:46-51`); those rays stop at the light.

There is **no published post-ADR-0028 total**. The 0.80 ms scene and 1.11 ms GPU
total in `docs/evidence/perf-scene-pass.md:35, 51` come from the scene-pass change
alone (`:4-5`); the sky and AO landed later and are not in it. The AO build
measured 2.17 ms scene and 2.611 ms total (`docs/adr/0017:91-95`). The eight AO
rays still run, so estimate 1.5 to 2.0 ms for the current scene pass
(`0.80 + 0.91 = 1.71`, minus the ramp). Re-run `scenarios/perf.json` before
committing a budget.

For this note: **0.10 to 0.18 ms per GI ray at 1440p on the RX 9060 XT**
(estimate). A GI ray needs a closest-hit traversal plus one hard sun ray at the
hit, so about 1.5 to 2 times an AO any-hit ray (`0.105 × 1.5 = 0.16`,
`0.105 × 2 = 0.21`, rounded down for one 12-triangle BLAS). Four rays add 0.4 to
0.7 ms, or 2.4% to 4.2% of the 16.7 ms frame. The eight AO rays they replace cost
0.91 ms. **The AO rays are the budget.**

## Budget: what one bounce does to the noise

One cosine-weighted ray is a bad estimator. The integrand is a visibility test
times the hit radiance, so a sample returns one of a few values: sky, sunlit
floor, lit wall, black wall, lamp face. The variance comes from visibility, not
from the BRDF.

A pixel sees 10% sky at 0.6, 10% sunlit floor at 0.4, and 80% black wall at 0.
Then `mean = 0.06 + 0.04 = 0.10`, `E[X²] = 0.036 + 0.016 = 0.052`,
`var = 0.042`, `sigma = 0.205`, and the coefficient of variation is 2.05.

Standard error is `sigma / sqrt(N)`
([PBRT §2.1.4](https://pbr-book.org/4ed/Monte_Carlo_Integration/Monte_Carlo_Basics)).
At 0.10 linear the sRGB encode at `taa.frag:34-36` has a slope of 1.68, so the
level column is `fraction × 1.68 × 255`.

| Samples | Error / mean | Error on a 0.10 term, sRGB levels |
| ---: | ---: | ---: |
| 64 | 25.6% | 11.0 |
| 256 | 12.8% | 5.5 |
| 512 | 9.1% | 3.9 |
| 2048 | 4.5% | 1.9 |
| 8192 | 2.3% | 1.0 |

The output dither is 1.5/255 (`taa.frag:44`), so the last row is at the dither
scale.

**The 512-frame history does not give 512 independent samples at one ray per
pixel.** The phase is `frame_count % 64` (`debug.odin:72`), and the AO phase
reads it (`box.frag:216-217`). A 1 spp sequence visits 64 directions, then
repeats them; frames 65 to 512 average the same values. The effective count is
64. Four spp is capped at 256. The history cap only pays off if the GI sequence
runs longer than 64 frames; that is a seam in `debug.odin:68-72`.

Precision is not the limit: the 16-bit scene target has a `6e-5` step at 0.1
linear (0.026 sRGB levels), and the 32-bit history is sufficient
(`docs/adr/0027:9-15`). The TAA clamp clips the history to a 2-sigma YCoCg box
around the current neighbourhood (`taa.frag:49-51, 91-118`). On a flat wall it
behaves like a 3x3 blur, which is the spatial filter this low-frequency term
needs. It is not a denoiser at a geometry edge.

## A. One-bounce gather in the lit pass

**Computes.** `s` cosine-weighted rays per fragment. Shade the first hit with the
sun and the lamps: one hard sun ray at the hit, and the lamps use the range
falloff without a secondary shadow ray. No recursion. A miss adds zero.

**Pass graph and targets.** Unchanged: `Tlas → Depth → Scene(+gi) → Sky → Taa →
Overlay`. No new `perf.Pass`, so the overlay cannot separate GI from direct light.
Add a gated `gi` override in the shape of `ao` (`debug.odin:12-25, 49-60`). Zero
new bytes: the value lives one frame in the 16-bit scene target, then in the
32-bit history.

**Descriptors.** None. The fragment shader already binds the TLAS, objects,
lights, and camera (`uniforms.odin:51-54`). Only a new `vec4` for count,
distance, and strength; `occlusion.w` and `jitter.zw` are unused, but an explicit
field with the assert at `uniforms.odin:46` is clearer. One real gap: the TLAS
instance custom index is never set (`acceleration.odin:84-91`), so a hit cannot
find its object. Set `instanceCustomIndex = index`; the shader reads
`scene.objects[i].color`. The hit normal comes from the hit triangle.

**Cost.** 0.10 to 0.18 ms at 1 spp, 0.4 to 0.7 ms at 4 spp (estimate), with one
sun ray at the hit. A shadow ray per in-range lamp would add 0.05 to 0.06 ms for
each (`docs/evidence/perf-lamps.md:46-51`). The AO rays it can replace cost
0.91 ms. Net: neutral at 4 spp, cheaper at 1 to 2.

**Quality.** Low-frequency and directionally correct. One bounce only, so an
indirect corner stays dark. At 1 spp the 64-frame period gives 64 effective
samples, about 11 sRGB levels of error on a 0.10 linear term. Two spp gives 128
(about 7.8), and four gives 256 (about 5.5). Extend the phase to 512 frames and
4 spp reaches 2048 samples and about 1.9 levels.

**Artifacts.** Noise and boiling, worst after a history reset. Fireflies from a
hit on the emissive lamp face (`box.frag:225`), which has no PDF guard. Temporal
lag on disocclusion.

**Fixes.** Bounce from sun and lamps: the doorway patch spills into the first
lane, and a lamp fills the chamber past its direct cone. **Does not fix.**
Multi-bounce, colour or texture detail, specular, or the noise after a turn.

**Seams.** `shaders/box.frag`, `uniforms.odin`, `shaders/camera.glsl`,
`scene.odin:172-197`, `debug.odin`, `state.odin`, `render_digest.odin`,
`acceleration.odin:84-91`.

## B. DDGI probe grid

**Computes.** A probe grid holding 8x8 octahedral irradiance plus depth moments.
Each update traces R rays per probe, shades the hit, and blends into the probe
with hysteresis. The lit pass samples 8 probes
([Majercik et al. 2019](https://research.nvidia.com/publication/2019-05_dynamic-diffuse-global-illumination-ray-traced-irradiance-fields)).

**Pass graph.** `Tlas → Probe → Depth → Scene(probe) → Sky → Taa → Overlay`. The
probe update is a compute dispatch with `has_rendering = false` (`pass.odin:50-52`).
It adds a `perf.Pass`, a `PASS_ORDER` row, a timestamp, and an overlay row
(`perf.odin:27-50`, `timing.odin:10`). The TLAS barrier ends at
`.FRAGMENT_SHADER` (`acceleration.odin:127-129`); it must cover `.COMPUTE_SHADER`.
A probe buffer on binding 4 of the shared scene set (`uniforms.odin:51-54, 95-99`),
a grid uniform, a compute pipeline, and a pass builder are the rest.

**Targets and memory.** One storage buffer, no image. An 8x8 irradiance map plus
8x8 depth moments is 640 B per probe: 800 probes at 2 m give 500 KiB, and 6,400
at 1 m give 3.9 MiB. A 16x16 visibility map raises that to 8.6 MiB. The history
alone is 118 MB at 1440p (`docs/adr/0027:65`), so memory is not the problem.

**Cost.** 128 rays per probe: 102,400 rays for 800 probes, 819,200 for 6,400.
The lit pass at 1440p traces at most `3.69M × 24 = 88.5M`, so the update is 0.1%
to 0.9% of the ray count. Estimate 0.02 to 0.10 ms for the update. The update is
not the problem. The gather is.

The DDGI paper measures 0.5 ms for the per-pixel probe sample at 1080p on an
RTX 2080 Ti, with 8192 probes and a 32×8×32 grid
([Table 2](https://jcgt.org/published/0008/02/01/)). The gather scales with
pixels, not probe count: about 0.9 ms at 1440p, about 0.22 ms at half
resolution. Full-resolution DDGI spends the whole 0.9 ms GI budget on the sample
alone, before the update and the pass overhead. The half-resolution gather is
the only version that fits. The overhead estimate in the main note
([`global-illumination.md`](global-illumination.md), §11) agrees: about 0.3 ms
total at half resolution. The DDGI author reports 1 to 2 ms per frame and 5 MB
per cascade, with 1080p demo images on an RTX 2080 Ti
([McGuire](https://morgan3d.github.io/articles/2019-04-01-ddgi/)).

**Quality.** Steady-state noise-free and stable under camera motion, because it
does not depend on the screen or on TAA.

**Latency.** At 1/16 round-robin a full update is 16 frames, 267 ms; at this cost
it could run every frame. Hysteresis is the larger lag: weight `w` reaches 63% of
a step in `1/(1-w)` updates, so `w = 0.9` gives 2.7 s and `w = 0.97` gives 8.9 s.
Sun placement moves the sun live (`README.md:149-151`), so a moving sun would
crawl. Probes "suffer from a lack of details and slow response times to changes
in lighting" ([Boissé et al. 2023](https://arxiv.org/abs/2310.19855)).

**Artifacts.** Light leak is the dangerous one: the method "cannot prevent leaks
from zero-thickness/single-sided walls" and needs a bias "tuned to scene scale"
([McGuire](https://morgan3d.github.io/articles/2019-04-01-ddgi/)). The 0.3 m shell
(`arena_room.odin:12`) is survivable; the door and turns are not. At 2 m spacing
the 1.6 m door and 2.0 m tunnel (`arena_room.odin:15, 20`) are smaller than one
cell; at 1 m there are two probes across the tunnel. Expect light to creep around
the last turn, which is what `scenarios/room-lighting.json` gates at 0.17 mean
green (`docs/evidence/room-lighting.md:36-38`). Relocation, an inside/outside
mask, and a finer room grid are extra work. Also: blocky gradients, popping, sun
lag.

**Fixes.** Noise-free bounce with no screen dependence. **Does not fix.**
Multi-bounce (unless two bounces), thin-wall leaks, sun lag, colour detail.

**Seams.** New `probes.odin` and probe shader, `pass_builders.odin`,
`perf.odin`, `uniforms.odin`, `acceleration.odin:127-129`, `shaders/box.frag`,
`scene.odin`, `state.odin`.

## C. Screen-space GI

**Computes.** A depth-buffer march from each visible surface against the depth
prepass, shaded by scene colour, at half resolution, then a bilateral upsample.

**Pass graph.** `Tlas → Depth → Ssgi → Scene(+ssgi) → Sky → Taa → Overlay`. The
depth image has `.DEPTH` usage only (`taa.odin:170-176`) and the format check
requires only `DEPTH_STENCIL_ATTACHMENT` and `TRANSFER_SRC` (`taa.odin:133`).
SSGI needs `.SAMPLED` and `SAMPLED_IMAGE`.

**Targets and memory.** A half-res 16-bit target: 1280 x 720 x 8 B = 7.4 MB at
1440p. Normals can come from depth, so no normal target is required.

**Descriptors and seams.** A new fullscreen pipeline, a sampled-depth binding, a
half-res target binding on the scene set, and `taa.odin`, new `ssgi.odin`,
`pass_builders.odin`, `uniforms.odin`, `pipeline.odin`, `box.frag`.

**Cost.** Estimate 0.2 to 0.4 ms for 8 to 16 steps, plus the upsample.

**Quality and artifacts.** Accurate where both emitter and receiver are on
screen; wrong everywhere else. Blind behind the camera, at the edge, and for
light through a door behind the player. Epic states it directly: screen traces
make indirect lighting view-dependent, and "Screen Traces cannot support it
correctly"
([Lumen](https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-technical-details-in-unreal-engine)).
The same page shows the enclosed-box case, where missing occluders leak light.

**Fixes.** Nothing this scene needs: the chamber is lit by a lamp or a door that
is often off screen. **Does not fix.** The room, the tunnel, or view-dependent
popping. It also duplicates the AO term, which approximates the same integral.

**Verdict.** Not worth a pass: the camera cannot see the light path.

## D. Radiance cache or ReSTIR GI

**Computes.** ReSTIR GI keeps one light-path sample per pixel in a reservoir,
reuses it in space and time with shift mapping, and denoises
([Ouyang et al. 2021](https://doi.org/10.1111/cgf.14378)). A hashed cache stores
world-space radiance and ends paths on a cache hit. ORCA is the research end of
the same family: a cache with no temporal history
([SIGGRAPH 2026 Advances](https://advances.realtimerendering.com/s2026/)).

**Pass graph.** `Tlas → Depth → Gbuffer → GiTrace → Reuse → Denoise →
Scene(+gi) → Sky → Taa → Overlay`. Four to five new passes, a G-buffer, a
reservoir ping-pong, a denoiser descriptor set, and files `restir.odin` or the
cache, `pass_builders.odin`, `pipeline.odin`, `uniforms.odin`, `taa.odin`,
`box.frag`.

**Targets and memory.** A 32 B reservoir at 3.69M pixels is 118 MB; a ping-pong
pair is 236 MB, twice the TAA history (`docs/adr/0027:65`). SHaRC's baseline is
`2^22` entries at 40 B, or 160 MiB
([RTXGI guide](https://github.com/NVIDIA-RTX/RTXGI/blob/main/Docs/SharcGuide.md)).
A G-buffer adds 15 to 30 MB; the 40 m scene leaves the cache empty, so this is
overhead, not signal.

**Cost.** The denoiser is the problem. NRD reports 2.55 ms at 1440p for REBLUR
diffuse plus specular on an RTX 4080 ([NRD](https://github.com/NVIDIA-RTX/NRD)),
2.3 times this renderer's pre-AO frame on a faster GPU. NRD also needs a G-buffer
with normal, roughness, view Z, and motion, none of which exists. NRC needs
Tensor Cores and an NVIDIA GPU ([RTXGI](https://github.com/NVIDIA-RTX/RTXGI));
the target is an RX 9060 XT on RADV (`docs/evidence/perf-baseline.md:3-4`), so
NRC is unavailable. The NRC paper reports about 2.6 ms at 1080p for cache update
and query ([Müller et al. 2021](https://arxiv.org/abs/2106.12372)).

**Quality and artifacts.** Best: multi-bounce, low noise, stable. But ReSTIR's
win is many lights and hard visibility, and this scene has one sun, eight lamps,
and one 12-triangle BLAS. GI-1.0 says reservoir methods are "poorer performance
and increased amounts of noise" than probes
([Boissé et al. 2023](https://arxiv.org/abs/2310.19855)). Expect reservoir
boiling, temporal bias, and disocclusion. Flat albedo still caps the payoff at a
tint and a gradient.

**Fixes.** Second bounce and quiet indirect light. **Does not fix.** The flat
albedo.

**Verdict.** A GI showcase destination, not a movement demo with eight lamps.

## E. Sky visibility plus one bounce

**Computes.** The same rays as A, with one change: a miss returns sky radiance
instead of zero. The rays are then both sky visibility and the one-bounce
gather. That is the rendering equation's incoming-radiance integral with a
two-part environment
([PBRT eq. 1.1](https://pbr-book.org/4ed/Introduction/Photorealistic_Rendering_and_the_Ray-Tracing_Algorithm)).

**Why it is not the removed ramp.** `sky_ambient(normal)` was a function of the
normal only (`docs/adr/0017:16-19`). It could not see geometry, so it lit the
chamber because the chamber's normals point up. Sky visibility is an integral
over directions with a visibility test. Every direction from the chamber hits the
shell, so the integral is exactly zero. The depth capture already proves no sky
pixel is visible in the chamber (`docs/evidence/room-lighting.md:39-40`). A miss
term therefore keeps the room at the dither floor with no special case.

**Pass graph, targets, memory, cost.** The same as A: no new pass, no new target,
no new descriptor, zero new bytes, 0.4 to 0.7 ms at 4 spp (estimate), replacing
0.91 ms of AO rays.

**Quality.** Better than A at the same ray count: the sky radiance is analytic,
and in the open arena most rays escape, so the sky part converges faster than the
bounce. In the room no ray escapes, so the term is the noisy lamp bounce, the
smaller part of the frame.

**Artifacts.** A's noise on the bounce. One new risk: `sky_color()` puts the sun
disk at 12.0 plus a glow (`sky.glsl:20-27`). If the environment uses it, the sun
is counted twice. The environment needs a `sky_environment()` without the disk.
The horizon is also brighter than the zenith, 0.52 to 0.74 against 0.10 to 0.42
(`sky.glsl:4-5`), so as a light it favours vertical walls.

**Fixes.** Bounce, an environment light with real visibility, and retirement of
the AO term. The room stays black because no sky ray escapes it. **Does not fix.**
Multi-bounce, or colour detail beyond one flat hue per surface.

**Seams.** A's files, plus `shaders/sky.glsl` and a sky-gain uniform; the sky pass
and the lit pass would share the gradient.

## What GI does to the rest of the design

**AO.** AO multiplies direct light (`box.frag:224`) as a stand-in for the missing
indirect occlusion. With a real gather it is wrong both ways: it darkens direct
light a path tracer leaves alone, and it darkens indirect light that already
carries visibility. **Retire it** and spend the eight rays on GI. A contact
corner gets brighter: the multiplier is `mix(1, ao, 0.5)` (`box.frag:219`,
`scene.odin:27`), so a fully occluded pixel keeps 50% of direct light; removing it
can double the direct there. GI then adds the bounce back.
`scenarios/stairs-ao.json` gates the current darkening
(`docs/evidence/sky-ao.md:48-55`); that gate changes with the decision.

**Flat albedo.** A bounce carries one colour, so colour bleed is a large smooth
tint, not detail. The teal room bounces teal; the orange wall bounces orange onto
grey. The luminance part is the useful part: a lamp spills past its cone, the
doorway patch brightens lane 1, a crate darkens the floor under it. GI is worth
it for luminance and marginal for chroma; expose an indirect-saturation scale. A
1 spp gather reads as dirt on a flat surface, which is the strongest argument for
4 spp plus a longer sequence.

**The sky becomes a control.** Background and lighting are independent today:
ADR 0017 says the ambient palette "is not the integral" of the sky
(`docs/adr/0017:115-121`). Making the sky a light removes that independence, and
that is the real cost of E.

**Harness.** The room proof survives and gets stronger. Add a gate: with the sky
on and no lamp, the chamber stays at 0.17 mean green
(`docs/evidence/room-lighting.md:32-47`). With a lamp, one bounce raises the mean;
add a capture with the bounce off to prove the delta. Add a gated `gi` override
so a paired perf run separates the gather, in the shape of
`scenarios/perf-lamps.json:1-13`.

## Ranking

| Rank | Option | Fit | One-line reason |
| ---: | --- | --- | --- |
| 1 | **E. Sky + one bounce** | High | One shader edit, no new target, retires the AO rays, keeps the chamber black by construction. |
| 2 | **B. DDGI grid** | Medium | The only noise-free, motion-stable option, but the sealed room turns leak into a product risk. |
| 3 | **A. One bounce only** | High | The same code as E with the sky at zero: cheap, noisier than B, less capable than E. |
| 4 | **D. Cache / ReSTIR** | Low | Best quality, but 200+ MB and a denoiser that costs more than the frame; NRC is unavailable. |
| 5 | **C. SSGI** | Low | Blind exactly where the room's proof lives, so it fails the one view the project gates. |

| Goal | A | B | C | D | E |
| --- | --- | --- | --- | --- | --- |
| Room stays black by construction | high | low | low | high | high |
| No flat fill | high | medium | medium | high | high |
| Payoff with flat albedo | medium | medium | low | high | high |
| Fits the pass graph | high | medium | medium | low | high |
| Stable under a fast camera | low | high | low | medium | medium |
| Cost at 1440p | high | high | high | low | high |

B moves first if the first frame after a turn must be clean; E and A are one build.

## Open design questions

1. **Is the sky allowed to light the scene?** Yes makes the background and the
   lighting one function and adds a blue-grey fill that lowers the contrast ADR
   0028 chose. No collapses E to A and keeps the hard black base.
2. **Does the lamp's emissive face become a GI emitter?** Today `object.color.a`
   is added unshadowed and lights nothing (`box.frag:225`). Letting a hit read it
   makes every lamp a GI source, and the chamber stops being black when a lamp is
   present.
3. **Does AO retire from direct light?** Retiring is physically right, frees
   eight rays, and makes contact corners up to twice as bright. Keeping it holds
   the current contact look at the cost of double-counted occlusion.

## Sources

- Majercik et al., "Dynamic Diffuse Global Illumination with Ray-Traced Irradiance Fields", JCGT 8(2), 2019. [NVIDIA](https://research.nvidia.com/publication/2019-05_dynamic-diffuse-global-illumination-ray-traced-irradiance-fields), [JCGT](http://jcgt.org/published/0008/02/01/).
- McGuire, "Dynamic Diffuse Global Illumination", 2019. Costs, leak limits, bias warning. [Article](https://morgan3d.github.io/articles/2019-04-01-ddgi/).
- Boissé et al., "GI-1.0", 2023. [arXiv](https://arxiv.org/abs/2310.19855).
- Ouyang et al., "ReSTIR GI", CGF 40(8), 2021. [DOI](https://doi.org/10.1111/cgf.14378).
- Müller et al., "Real-time Neural Radiance Caching for Path Tracing", 2021. [arXiv](https://arxiv.org/abs/2106.12372).
- NVIDIA, [RTXGI v2.0](https://github.com/NVIDIA-RTX/RTXGI), [SHaRC guide](https://github.com/NVIDIA-RTX/RTXGI/blob/main/Docs/SharcGuide.md), [NRD](https://github.com/NVIDIA-RTX/NRD). Cost and G-buffer inputs.
- Epic Games, [Lumen Technical Details](https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-technical-details-in-unreal-engine). Screen-trace limits, cave leaks, slow propagation.
- Pharr, Jakob, Humphreys, *Physically Based Rendering*, 4th ed. [Eq. 1.1](https://pbr-book.org/4ed/Introduction/Photorealistic_Rendering_and_the_Ray-Tracing_Algorithm), [§2.1](https://pbr-book.org/4ed/Monte_Carlo_Integration/Monte_Carlo_Basics).
- House survey of AO, denoising, and reconstruction: [ambient-occlusion.md](ambient-occlusion.md).
