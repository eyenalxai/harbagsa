# Ambient occlusion: what to read in 2026

Research note. No implementation plan, no shader code. Every claim links to the
source that owns it. Vendor claims are marked as such.

## The short answer

Ambient occlusion used to be one question: how do you estimate visibility from a
depth buffer? That question is settled. The answer is still **GTAO**
([Jimenez et al. 2016](https://www.iryoku.com/downloads/Practical-Realtime-Strategies-for-Accurate-Indirect-Occlusion.pdf)),
with **VBAO**
([Therrien et al. 2022](https://arxiv.org/abs/2301.11376))
as the one credible improvement for thin geometry.

The live question in 2026 is different. AO is no longer a pass. High-end
renderers trace a few visibility rays per pixel and reconstruct the result with a
denoiser. Path-traced titles drop the AO pass completely and keep only material
AO. The newest research no longer filters AO values; it **reuses occlusion
points** before they become values
([Jin et al. 2026](https://arxiv.org/abs/2607.23122)).
The newest shipping feature asks a network to *generate* the AO detail instead of
estimating it
([NVIDIA DLSS 5, September 2026](https://www.nvidia.com/en-us/geforce/news/dlss-5-3d-guided-neural-rendering/)).

So: screen-space AO is mature and static. The frontier is reconstruction.

## 1. What AO measures

AO is the cosine-weighted fraction of the hemisphere that is visible from a
point:

```
A(x) = (1/π) ∫ V(x, ω) · (n·ω)⁺ dω
```

The `1/π` normalizes the result to [0,1]. GTAO states the normalization
explicitly
([§2, Eq. 5](https://www.iryoku.com/downloads/Practical-Realtime-Strategies-for-Accurate-Indirect-Occlusion.pdf)).

AO is not a transport quantity. It becomes a simple scalar multiplier only under
three assumptions: an infinite uniform environment, purely absorbing occluders,
and a Lambertian receiver. Under those, `Lr = Li · (ρ/π) · A(x)`.

The assumptions are the error. AO ignores interreflection, so it over-darkens
enclosed regions. Older methods hid that with an ad-hoc distance falloff. GTAO
rejects the falloff and adds a near-field bounce term instead.

Directional occlusion keeps the direction of open sky, not only the scalar. Two
encodings matter: a **bent normal** (average unoccluded direction) and a
**visibility cone** (axis plus aperture). Both enable specular occlusion and
rotated ambient probes. See
[GTAO §6](https://www.iryoku.com/downloads/Practical-Realtime-Strategies-for-Accurate-Indirect-Occlusion.pdf)
and
[Kontkanen and Laine 2005](https://research.nvidia.com/sites/default/files/publications/kontkanen2005i3d_paper.pdf).

## 2. The screen-space family

| Method | Year | Input | Reported cost | Why it matters |
|---|---|---|---|---|
| SSAO ([Mittring](https://web.archive.org/web/2019/https://artis.inrialpes.fr/Membres/Olivier.Hoel/ssao/p97-mittring.pdf)) | 2007 | depth | — | The original. Sphere samples in screen space. No physical basis. |
| HBAO ([Bavoil, Sainz](https://developer.download.nvidia.com/presentations/2008/SIGGRAPH/HBAO_SIG08b.pdf)) | 2008 | depth | — | Horizon marching. Estimator `sin h − sin t` with uniform, not cosine, weighting. |
| SAO ([McGuire et al.](https://research.nvidia.com/sites/default/files/pubs/2012-06_Scalable-Ambient-Obscurance/McGuire12SAO.pdf)) | 2012 | depth MIPs | 7× over prior work at 2560×1600 | Makes cost predictable. Prefiltered depth, thread-level tuning. |
| GTAO ([Jimenez et al.](https://www.iryoku.com/downloads/Practical-Realtime-Strategies-for-Accurate-Indirect-Occlusion.pdf)) | 2016 | depth + normals | 0.5 ms, PS4, 1080p | The current default. Horizon-based, analytically integrated, matched to ray-traced ground truth. |
| Deep G-buffers ([Mara et al.](https://research.nvidia.com/sites/default/files/pubs/2016-06_Deep-G-Buffers-for/Mara2016DeepGBuffer-extended-bright.pdf)) | 2016 | two depth layers | 5 ms, GTX 980, 1080p | Recovers occluders the single-layer depth buffer hides. |
| VBAO ([Therrien et al.](https://arxiv.org/abs/2301.11376)) | 2022 | depth + normals | similar sample budget to GTAO | Replaces the two horizon angles with a 32-sector bitmask. Handles thin surfaces, adds bent cones. |
| XeGTAO ([Intel](https://github.com/GameTechDev/XeGTAO)) | 2021 | depth + normals | 0.56 ms, RTX 2060, 1080p | Not a new algorithm. A tuned GTAO implementation. Archived April 2024. |

Three details decide quality more than the estimator name:

- **Resolution.** GTAO runs at half resolution, takes one horizon direction per
  pixel, and reconstructs over a 4×4 bilateral neighbourhood. Six temporal
  rotations give 96 effective directions per pixel
  ([§4.1](https://www.iryoku.com/downloads/Practical-Realtime-Strategies-for-Accurate-Indirect-Occlusion.pdf)).
- **Thickness.** A depth buffer has no back faces. GTAO assumes object thickness
  scales with screen-space width. XeGTAO reports that thin occluders and the
  height-field assumption remain "the main difficulty"
  ([README](https://github.com/GameTechDev/XeGTAO)).
- **Sampling noise.** XeGTAO replaces the paper's 4×4 noise tile with a Hilbert
  curve index driving an R2 sequence, then leans on TAA for the temporal part.

VBAO's own comparison is the useful critique: "When using a wide radius, GTAO has
a tendency to produce halos around objects"
([§1](https://arxiv.org/abs/2301.11376)).
It also notes that GTAO's fixed thickness fails behind thin surfaces, and that
several visibility cones beat one bent normal.

## 3. Out of screen space

- **Baked AO.** An authored texture that occludes indirect light and derives
  specular occlusion
  ([Unity HDRP](https://docs.unity3d.com/Packages/hdrp/manual/Ambient-Occlusion.html)).
  Still the correct answer for static detail.
- **AO fields.** One radial field per occluder, built offline, looked up at
  runtime
  ([Kontkanen, Laine 2005](https://research.nvidia.com/sites/default/files/publications/kontkanen2005i3d_paper.pdf)).
- **Distance-field AO.** Nine cones minimum cover the hemisphere, traced against
  mesh and global SDFs at 1/8 resolution
  ([Wright, SIGGRAPH 2015](https://www.realtimerendering.com/advances/s2015/DynamicOcclusionWithSignedDistanceFields.pdf)).
  The cone of least occlusion gives the bent normal. Reports 3.7 ms on PS4.
- **Voxel AO.** Voxelize every frame, cone-trace opacity voxels
  ([Tatarinov, Panteleev, GDC 2016](https://developer.download.nvidia.com/gameworks/events/GDC2016/atatarinov_alpanteleev_advanced_ao.pdf)).
  Vendor claims: 1–4 ms and 10–140 MB on a GTX 980.
- **Ray-traced AO.** Rays against the BVH. Off-screen geometry occludes
  correctly, which no depth-buffer method can do. Unity HDRP pairs it with a
  spatio-temporal denoiser
  ([docs](https://docs.unity3d.com/Packages/hdrp/manual/Ray-Traced-Ambient-Occlusion.html)).

## 4. What ships in 2026, by tier

**Mid tier, raster only.** GTAO or VBAO at half resolution, temporally
accumulated. CACAO is the AMD first-party equivalent
([GPUOpen](https://gpuopen.com/fidelityfx-cacao/)). Baked AO covers static detail.

**High tier, hardware ray tracing.** A few rays per pixel plus a spatiotemporal
denoiser. NVIDIA NRD ships dedicated modes for it: REBLUR handles diffuse and
specular occlusion, and exposes `OCCLUSION` and `DIRECTIONAL_OCCLUSION` variants
([README](https://github.com/NVIDIA-RTX/NRD)).
NRD reports 15+ shipped titles and about 2.55 ms for REBLUR diffuse plus specular
at 1440p on an RTX 4080 (vendor claim, v4.18.0).

**Top tier, path tracing.** The AO pass is gone. Epic states it directly: "Lumen
Global Illumination replaces Distance Field Ambient Occlusion (DFAO)"
([Lumen GI](https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-global-illumination-and-reflections-in-unreal-engine)).
Sky shadowing happens inside Final Gather. What remains is *material* AO, a
texture input for self-occlusion on skeletal meshes. Epic also notes it "is not
visible when using the Buffer Visualization Ambient Occlusion view mode", which
is a good sign the buffer itself no longer exists.

DFAO survives as the fallback for "previous-generation consoles ... and legacy
PC hardware"
([Lumen technical details](https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-technical-details-in-unreal-engine)).

Shipped proof points:

- *DOOM: The Dark Ages*, id Tech 8, June 2025. Path tracing with DLSS Ray
  Reconstruction
  ([NVIDIA](https://developer.nvidia.com/blog/how-id-software-used-neural-rendering-and-path-tracing-in-doom-the-dark-ages)).
- *Cyberpunk 2077* RT Overdrive, April 2023. Path-traced mode, REBLUR-era
  denoising
  ([patch notes](https://www.cyberpunk.net/en/news/47875/patch-1-62-ray-tracing-overdrive-mode)).
- *PRAGMATA* and *Resident Evil Requiem*, RE ENGINE, 2026. "Direct lighting now
  runs through the path tracer instead of shadow maps", plus a custom ReSTIR GI
  and DLSS Ray Reconstruction
  ([NVIDIA Q&A, July 2026](https://developer.nvidia.com/blog/qa-how-capcom-brought-path-tracing-to-re-engine-across-pragmata-and-resident-evil-requiem/)).

That last one is the cleanest statement of the shift: the AO pass and the shadow
map leave together, because both were approximations of the same visibility
integral.

## 5. The frontier is reconstruction, not estimation

**Occlusion-point reuse.** Jin et al. reformulate AO and area-light shadows as
integrals over *first-hit occluders*. Neighbouring pixels then share occluder
samples under MIS, instead of sharing finished AO values. They derive unbiased
estimators, and biased ones for real time. They report better AO and shadow
quality than non-reuse ray-traced baselines at comparable cost
([ACM TOG / arXiv, July 2026](https://arxiv.org/abs/2607.23122)).
This is a sampling change. It reduces the noise the denoiser must remove, so it
composes with everything below.

**Stochastic depth maps.** Brüll, Kern and Grosch replace the depth buffer with a
ray-traced stochastic one, which restores most of the information a plain depth
buffer lacks. They report results "almost indistinguishable from a ground truth
solution with all depth samples", and better performance than the earlier
stochastic-depth method
([EGSR 2024](https://diglib.eg.org/handle/10.2312/sr20241160)).
It is screen-space AO with a better input, not a new estimator.

**Variable-rate ray budgets.** Call of Duty: Modern Warfare 4 allocates rays per
pixel: below 1 spp where the temporal gradient says the pixel is stable, above
1 spp where it is not. A temporal gradient prepass plus explicit disocclusion
detection drive it, and a frame-level scheduler holds the total ray count
constant
([SIGGRAPH 2026 Advances](https://advances.realtimerendering.com/s2026/)).
The talk's own framing is that fixed-rate tracing with screen-space denoising
"proved insufficient" under fast motion.

**SVGF is still the baseline.** Schied et al. reconstruct 1 spp path tracing at
about 10 ms at 1080p, and report 5–47% better SSIM and 10× better temporal
stability than the alternatives they test
([HPG 2017](https://research.nvidia.com/publication/2017-07_spatiotemporal-variance-guided-filtering-real-time-reconstruction-path-traced)).
A 2026 JCGT paper still finds headroom in its à-trous stage: 1.3–2.5× speedup
with no quality loss
([Pikulsky, JCGT 16(1)](https://jcgt.org/published/0015/01/02)).

**Neural reconstruction.** DLSS Ray Reconstruction replaces hand-tuned denoisers
with a trained network; id and Capcom both name it as their denoiser. The 2026
step goes further. DLSS 5 "3D-Guided Neural Rendering" takes colour and motion
vectors and synthesises high-frequency detail, including AO. Its "Structure
Intensity" control governs "high-frequency details such as ambient occlusion,
reflections, and subsurface scattering". It is deterministic, one frame in and
one frame out, and needs RTX 50-series hardware
([NVIDIA, September 2026](https://www.nvidia.com/en-us/geforce/news/dlss-5-3d-guided-neural-rendering/)).
Treat this as a vendor claim about a new product, not as an evaluated method.

**Neural caches.** ORCA (EA SEED) is a radiance cache with no temporal history;
all structures are instantaneous, which suits fully dynamic scenes
([SIGGRAPH 2026 Advances](https://advances.realtimerendering.com/s2026/)).
An earlier point on the same curve is real-time neural radiance caching
([Müller et al. 2021](https://arxiv.org/abs/2106.12372)).
JCGT 2025 adds a neural visibility cache for light sampling
([Bokšanský, Meister](https://jcgt.org/published/0014/02/01)).
None of this is AO-specific, but all of it competes with AO for the same budget.

## 6. Is the AO pass going away?

The evidence says yes at the top end, and slowly.

- Epic states that Lumen replaces DFAO, and keeps only material AO.
- Two 2026 titles run direct lighting through a path tracer.
- NRD's AO modes exist to denoise traced occlusion, not to filter an SSAO buffer.
- The newest pure screen-space AO paper in the window is VBAO (2022). The 2024
  EGSR paper improves the *input* to SSAO instead.
- JCGT volumes 14–16 (2025–2026) contain no screen-space AO paper.

The inference is mine, and it is an inference: no first-party source says "we
deleted the AO pass". But the pieces line up.

What survives: screen-space AO wherever ray tracing is too expensive, and
material AO as a texture. Neither is where the research is.

## 7. Failure modes

| Artifact | Cause | Source |
|---|---|---|
| Halo around objects | Wide radius on a height field | [VBAO §1](https://arxiv.org/abs/2301.11376) |
| Thin features over-darken | No back faces; thickness assumed equal to screen width | [GTAO §4.1](https://www.iryoku.com/downloads/Practical-Realtime-Strategies-for-Accurate-Indirect-Occlusion.pdf), [XeGTAO](https://github.com/GameTechDev/XeGTAO) |
| Light trapped behind bars and fences | Binary horizon, constant thickness | [VBAO §4.1](https://arxiv.org/abs/2301.11376) |
| Banding at depth edges | Neighbouring pixels disagree on depth | [HBAO slides](https://developer.download.nvidia.com/presentations/2008/SIGGRAPH/HBAO_SIG08b.pdf) (about 30° angle bias) |
| Missing off-screen occluders | Screen space only | [GTAO §2](https://www.iryoku.com/downloads/Practical-Realtime-Strategies-for-Accurate-Indirect-Occlusion.pdf) |
| Noise | Few samples per pixel | [GTAO §4.1](https://www.iryoku.com/downloads/Practical-Realtime-Strategies-for-Accurate-Indirect-Occlusion.pdf) |
| Temporal smear and disocclusion | Reprojection error | [Deep G-buffers](https://research.nvidia.com/sites/default/files/pubs/2016-06_Deep-G-Buffers-for/Mara2016DeepGBuffer-extended-bright.pdf), [NRD](https://github.com/NVIDIA-RTX/NRD) |
| Over-darkening in enclosed spaces | AO ignores interreflection | [GTAO §2](https://www.iryoku.com/downloads/Practical-Realtime-Strategies-for-Accurate-Indirect-Occlusion.pdf) |

## 8. How quality is measured

The common method is a ray-traced reference. GTAO compares against Monte Carlo
AO and path-traced references across several scenes. VBAO compares against a
ray-traced reference across radius and sample-count settings. XeGTAO tunes its
heuristics against a 512 spp cosine-weighted reference, then reports MSE.

Numeric metrics appear mostly in reconstruction work: SVGF reports SSIM and
temporal stability. That measures a denoiser, not an AO estimator.

Gap worth knowing: I found no peer-reviewed perceptual study of AO correctness.
The evaluations above are visual side-by-sides plus, in one case, SSIM.

## 9. Reading list

Read in this order.

1. **Jimenez, Wu, Pesce, Jarabo, "Practical Realtime Strategies for Accurate
   Indirect Occlusion", SIGGRAPH 2016.** The single most useful document. It
   covers the integral, the estimator, the temporal scheme, bent normals,
   specular occlusion, and multi-bounce. Free:
   [technical report](https://www.iryoku.com/downloads/Practical-Realtime-Strategies-for-Accurate-Indirect-Occlusion.pdf),
   [slides](https://blog.selfshadow.com/publications/s2016-shading-course/activision/s2016_pbs_activision_occlusion.pdf).
2. **Therrien, Levesque, Gilet, "Screen Space Indirect Lighting with Visibility
   Bitmask", The Visual Computer (online 2022; vol. 40, 2024).** The best
   critique of GTAO's thin-geometry failure, and a working alternative. Free
   preprint: [arXiv](https://arxiv.org/abs/2301.11376).
3. **McGuire, Mara, Luebke, "Scalable Ambient Obscurance", HPG 2012.** Read for
   the depth-MIP and memory-bandwidth reasoning, not for the estimator. Free:
   [PDF](https://research.nvidia.com/sites/default/files/pubs/2012-06_Scalable-Ambient-Obscurance/McGuire12SAO.pdf).
4. **Mara, McGuire, Nowrouzezahrai, Luebke, "Deep G-Buffers for Stable Global
   Illumination Approximation", HPG 2016.** What a second depth layer buys, and
   how temporal error behaves. Free:
   [PDF](https://research.nvidia.com/sites/default/files/pubs/2016-06_Deep-G-Buffers-for/Mara2016DeepGBuffer-extended-bright.pdf).
5. **Schied et al., "Spatiotemporal Variance-Guided Filtering", HPG 2017.** The
   denoising baseline for every RTAO pipeline. Free preprint:
   [PDF](https://research.nvidia.com/publication/2017-07_spatiotemporal-variance-guided-filtering-real-time-reconstruction-path-traced).
6. **Jin et al., "Occlusion-Point Reuse for Ray-Traced Ambient Occlusion and
   Shadow", ACM TOG 2026.** The newest idea in the area, and the one most likely
   to matter. Free preprint: [arXiv](https://arxiv.org/abs/2607.23122).
7. **Wright, "Dynamic Occlusion with Signed Distance Fields", SIGGRAPH 2015.**
   The alternative branch: analytic cone tracing instead of depth. Free:
   [PDF](https://www.realtimerendering.com/advances/s2015/DynamicOcclusionWithSignedDistanceFields.pdf).
8. **Brüll, Kern, Grosch, "Ray Traced Stochastic Depth Map for Ambient
   Occlusion", EGSR 2024.** The bridge between screen-space AO and ray tracing.
   Free: [EG digital library](https://diglib.eg.org/handle/10.2312/sr20241160).
9. **Bavoil, Sainz, "Image-Space Horizon-Based Ambient Occlusion", SIGGRAPH 2008
   talk.** History, and the source of the horizon formulation. Free slides:
   [PDF](https://developer.download.nvidia.com/presentations/2008/SIGGRAPH/HBAO_SIG08b.pdf).
10. **Zhdan, "ReBLUR: A Hierarchical Recurrent Denoiser", Ray Tracing Gems II,
    2021.** How production AO denoising actually works. Open access:
    [DOI](https://doi.org/10.1007/978-1-4842-7185-8_49).

Non-paper sources that carry real weight: Epic's
[Lumen GI](https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-global-illumination-and-reflections-in-unreal-engine)
and
[Lumen technical details](https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-technical-details-in-unreal-engine)
pages, Intel's [XeGTAO README](https://github.com/GameTechDev/XeGTAO) (the most
honest engineering write-up in the area), and the
[SIGGRAPH 2026 Advances course](https://advances.realtimerendering.com/s2026/).

## 10. Open problems, as the papers state them

- **Occlusion-point reuse:** unbiased estimators are "too expensive for
  real-time use"; biased ones "can introduce block-like artifacts when that
  assumption fails"; the shared-group pattern is fixed; extension to full direct
  illumination is "theoretical in this paper"
  ([Jin et al.](https://arxiv.org/abs/2607.23122)).
- **VBAO:** one constant thickness for the whole frame, and the height-field
  assumption remains ([arXiv](https://arxiv.org/abs/2301.11376)).
- **XeGTAO:** thin occluders and the height-field assumption are "the main
  difficulty" ([README](https://github.com/GameTechDev/XeGTAO)).
- **Lumen:** sky occlusion and GI are maintained only for the first 200 m by
  default; light leaking in caves needs longer traces and more scene detail
  ([docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-technical-details-in-unreal-engine)).
- **Stochastic depth maps:** the earlier method was "not suitable for real-time
  rendering in large scenes"; the fix needs ray tracing and extra memory
  ([EGSR 2024](https://diglib.eg.org/handle/10.2312/sr20241160)).

## What did not check out

Recorded so the next reader does not chase them.

- **VBAO is not a 2023 result.** The journal version is 2022. Only the preprint
  is 2023.
- **XeGTAO is not a new algorithm**, and Intel archived it in April 2024.
- **No new screen-space AO method displaced GTAO after 2022.** Searches of arXiv
  cs.GR and the JCGT feed found none.
- **"3DAP" does not appear in the GTAO report.** It is community shorthand for
  the analytically solved inner integral.
- **ACM Digital Library and Springer returned 403** to automated fetches, so a
  few venue attributions rest on author copies and arXiv records. The HBAO ACM
  record could not be checked; the slides themselves are the source used.
