# Making few-sample GI look clean

Research note. No implementation plan, no shader code. Every claim links to the source that owns it. Vendor
claims are marked. Companion to [`ambient-occlusion.md`](ambient-occlusion.md),
[`global-illumination.md`](global-illumination.md) (the method survey), and
[`global-illumination-fit.md`](global-illumination-fit.md) (the renderer fit).

Scope: one or two GI rays per pixel, reconstructed into a stable image. What turns that into something
watchable, and what each option costs.

## The short answer

A GI ray samples a heavy-tailed distribution. AO samples a bounded one. That difference, not the filter, decides
what works.

- **Temporal accumulation is the cheapest win and the first thing to break.** The clamp removes the bright
  samples that carry most of the GI energy. Ghosting and flicker are opposing goals, by the TAA survey's own
  wording.
- **Spatial filtering buys stability with bias.** SVGF is still the baseline: 10.2 ms at 1080p on a Titan X in
  2017, 3.8 ms static for five à-trous iterations at 1080p on an RX 7800 XT in 2026.
- **Reuse before reconstruction is better when it fits.** ReSTIR GI reports 9.3×–166× MSE reduction at 1 spp,
  for 8.9 ms against 8.0 ms of path tracing at 1080p on an RTX 3090, and 475 MB of reservoirs.
- **Caches and probes remove the per-pixel denoiser.** DDGI updates a probe grid for 0.7 ms at 1080p on an RTX
  2080 Ti, independent of pixel count. ORCA rebuilds a world-space voxel cache every frame with no temporal
  history, and is not shipped yet.
- **Vendor denoisers are fast but locked.** NRD ReBLUR is 2.55 ms at 1440p on an RTX 4080 and needs a G-buffer.
  FSR Ray Regeneration is RDNA 4, DirectX 12 and Windows 11 only, at 6.52 ms for indirect diffuse plus specular
  at 1440p on an RX 9070 XT. DLSS Ray Reconstruction is NVIDIA only.

For a 1–2 ms budget at 1440p on an RX 9060 XT, with a forward renderer and no G-buffer, the realistic choices
are a reduced-resolution à-trous chain on a separate GI signal, or a probe grid. Section 12 works through it.

## 1. Why GI noise is not AO noise

AO estimates a normalized integral, `A(x) = (1/π) ∫ V·(n·ω)⁺ dω`, in [0,1]. GTAO states the normalization
explicitly
([§2, Eq. 5](https://www.iryoku.com/downloads/Practical-Realtime-Strategies-for-Accurate-Indirect-Occlusion.pdf)).
Every AO sample is bounded, and one sample already estimates a value in [0,1].

A GI sample estimates `L = Le + ∫ fr·Li·(n·ωi)⁺ dωi`, and `Li` is unbounded. One secondary hit can land on a
sunlit wall, a lamp, or a black corner. The variance is the variance of the radiance distribution, not of the
visibility count.

The arithmetic: if a pixel hits radiance `L` with probability `p` and a dark surface otherwise, `E = pL` and
`Var ≈ pL²`. For `p = 0.01`, `L = 100`, the mean is 1 and the standard deviation is 10. For AO at `p = 0.5`,
`L = 1`, the standard deviation is 0.5 against a mean of 0.5. GI is not "noisier AO"; it is a different
distribution.

Three sources show the consequence:

- SVGF, Figure 5: at low sample counts the variance is *underestimated exactly where paths with lighting
  contributions occur with low probability*
  ([HPG 2017](https://cg.ivd.kit.edu/publications/2017/svgf/svgf_preprint.pdf)).
- ReSTIR GI, Figure 12: a room lit by sunlight through a half-open door, path traced at 2 spp, is "almost black
  with a small number of pixels containing super bright samples"
  ([HPG 2021](https://d1qx31qr3h6wln.cloudfront.net/publications/ReSTIR%20GI.pdf)).
- NRD: "high-energy fireflies in the input signal should be avoided"; energy growth from a probabilistic lobe
  split "should not be more than 20x-30x", which is a minimum probability of about `0.05`
  ([README v4.18.0](https://github.com/NVIDIA-RTX/NRD)).

Call of Duty's 2026 path tracing talk states the practical version: "AO is probably easiest RT feature to
denoise", while mixed-frequency signals such as shadows and GI need more
([SIGGRAPH 2026 Advances](https://advances.realtimerendering.com/s2026/)).

A firefly is not a filter bug. It is a correct sample of a rare, bright path. Clamping it is a bias; the only
question is whether the bias is visible.

## 2. Temporal accumulation alone

Temporal accumulation is an exponential moving average. SVGF uses `α = 0.2`, reprojects with a 2×2 bilinear tap,
tests depth, normal and mesh ID per tap, falls back to 3×3 for thin geometry, then discards history
([§4.1](https://cg.ivd.kit.edu/publications/2017/svgf/svgf_preprint.pdf)). NRD calls the same knobs
`maxAccumulatedFrameNum` plus a "fast" history, and calls 32 accumulated frames "a solid baseline"
([README](https://github.com/NVIDIA-RTX/NRD)).

The clamp is where GI differs from AO. Karis introduced neighborhood clamping: restrict history to the min/max
of the 3×3 neighborhood, then clip instead of clamp
([SIGGRAPH 2014](https://de45xmedrsdbp.cloudfront.net/Resources/files/TemporalAA_small-59732822.pdf)). The
assumption is that the neighborhood brackets the true value. For antialiasing that holds. For GI it fails: the
neighborhood can be all shadow while the history holds the one sample that saw the light.

The TAA survey is honest about the cost ([CGF 2020](http://behindthepixels.io/assets/files/TemporalAA.pdf)):
"avoiding ghosting and flickering are often contradicting goals"; clamping can delete thin, high-contrast detail
permanently, because the foreground colour leaves history on frames where it is missed; and clamping is weakest
at dense high-contrast edges, where the bounding box is large and invalid history passes through.

Epic's TSR documentation gives the production answer: history at display resolution, a parallax disocclusion
mask from depth and velocity, shading rejection, flicker analysis, history resurrection. It also gives
convergence as a formula, `TSR1spp = 1000 / (ScreenPercentage² × FrameRate)`: 50% screen percentage at 60 Hz
needs four frames, 66 ms, before a disoccluded pixel has one sample
([Epic](https://dev.epicgames.com/documentation/unreal-engine/temporal-super-resolution-in-unreal-engine)).

TAA fixes sub-pixel aliasing and variance in a stationary signal. It cannot fix disocclusion (no history), heavy
tails (a clamp turns a firefly into the neighborhood mean, which is energy loss), or correlated error (an
upstream denoiser makes neighbours share samples, so the effective sample count is lower than the frame count
suggests).

Accumulating scalar AO is a different operation. The value is bounded, the neighborhood mean is a valid
estimator of the same bounded quantity, and a clamp to [0,1] is meaningful. A radiance neighborhood mean is a
*different* integral: it averages lighting from different world positions. That is the "bias from spatial
filtering" SVGF accepts and the CoD talk calls unavoidable as the radius grows.

## 3. Spatial filters: bilateral, à-trous, SVGF

A bilateral filter weights neighbours by depth, normal and colour similarity. SVGF drives the colour term with a
temporally estimated variance instead of a fixed falloff
([HPG 2017](https://cg.ivd.kit.edu/publications/2017/svgf/svgf_preprint.pdf)).

| Stage | What it does | Parameters |
|---|---|---|
| Temporal | Reproject colour and the first two luminance moments | `α = 0.2` |
| Variance | `σ² = µ2 − µ1²` from accumulated moments | 3×3 spatial fallback under 4 frames |
| À-trous | Five 5×5 cross-bilateral iterations, dilated by `2^i − 1` | 65×65 footprint |
| Edge stops | Depth (local plane fit), normal (cosine), luminance | `σz = 1`, `σn = 128`, `σl = 4` |

Variance is filtered too, with the same weights, so edge stopping weakens as the signal smooths. That keeps a
large footprint from erasing contact shadows. The first à-trous output feeds history, not the last: the authors
found it "best balances improved temporal stability with bias".

At launch the filter cost 4.1–5.8 ms at 1280×720 and 10.2 ms at 1920×1080 on a Titan X (Pascal), gave 10× better
temporal stability than prior work on a 60-frame Sponza sequence, and scored 5–47% better SSIM against a 4096
spp reference.

The 2026 JCGT paper re-measures the same algorithm on current hardware and gives per-iteration costs, which are
more useful for budgeting ([Pikulsky, JCGT 15(1)](https://jcgt.org/published/0015/01/02/)):

| Stage, 1920×1080 | RX 7800 XT | RTX 2080 Super |
|---|---|---|
| Reprojection | 0.54 ms | 0.65 ms |
| Variance, static / dynamic | 0.12 / 1.78 ms | 0.17 / 1.47 ms |
| Spatial, 5 iterations, static | 3.77 ms | 5.19 ms |
| Spatial, 5 iterations, dynamic | 5.43 ms | 6.49 ms |
| Per iteration, 1→5 | 0.73 / 0.60 / 0.53 / 0.49 / 0.48 | 0.74 / 0.74 / 0.76 / 0.77 / 0.98 |

The same paper reports 1.3–2.5× speedup from memory-layout changes with no quality loss. Note the shape: spatial
filtering dominates, it grows with resolution, and the variance pass spikes on disocclusion. A dynamic frame at
1080p costs 40% more than a static one.

## 4. Adaptive and iterative variants

**A-SVGF** attacks lag rather than noise. It spends part of the ray budget on gradient samples: forward-project
surface samples from the previous frame, re-evaluate shading with the same random sequence, estimate a temporal
gradient, adapt `α`. Changed regions get a large `α`; stable regions keep a long history. The authors report "a
significant reduction of lag and ghosting", and 2 ms at 1080p for the temporal filter
([PACMCGIT 2018](https://cg.ivd.kit.edu/publications/2018/adaptive_temporal_filtering/adaptive_temporal_filtering.pdf)).
The cost is real: gradient samples are rays not spent on the image, and shading must be re-evaluable at an
arbitrary previous surface point.

**BMFR** replaces the filter with a per-block regression. It fits a linear model of noisy colour against
multi-order feature buffers (normals, albedo, world position and its powers) over 32×32 blocks, with QR
factorisation and stochastic regularisation for rank deficiency, then accumulates and applies TAA
([ACM TOG 2019](https://webpages.tuni.fi/foi/papers/Koskela-TOG-2019-Blockwise_Multi_Order_Feature_Regression_for_Real_Time_Path_Tracing_Reconstruction.pdf)).
It runs in 2.4 ms at 720p on a Titan X, 1.8× faster than SVGF, with better RMSE/SSIM/VMAF in most scenes. Its
limitations section is the useful part: features smaller than a block blur, specular highlights smear, and the
block grid can become visible. It needs the G-buffer a forward renderer lacks.

## 5. Production denoisers

NRD is a source-available, API-agnostic library for 1 path/pixel signals. Each radiance denoiser also ships
occlusion and spherical-harmonic ("SH") variants. Cost and memory are vendor-reported.

| Denoiser | Algorithm | Signals | Cost, 1440p, RTX 4080 |
|---|---|---|---|
| NRD REBLUR | Recurrent blur | Radiance, AO, SO, directional occlusion | 2.55 ms (3.40 "SH") |
| NRD RELAX | À-trous | Radiance | 3.25 ms (4.80 "SH") |
| NRD SIGMA | Per-light | Shadow masks, translucency | 0.40 ms |

Anti-firefly costs +0–2% on REBLUR and +7–10% on RELAX. At 1440p, REBLUR diffuse + specular has a 262.56 MB
working set, 157.50 MB persistent; RELAX is 300.06 MB, 172.50 MB persistent
([README v4.18.0](https://github.com/NVIDIA-RTX/NRD)).

The integration contract defines what a GI signal must carry:

- **Motion vectors**, preferably 2.5D (2D plus `viewZ` delta) or 3D. 2D vectors "can lead to massive history
  reset on moving objects".
- **World normal, linear roughness, linear view Z.** `R10G10B10A2` normals are preferred for curvature.
- **Hit distance** for the first bounce, in-lobe, not divided by PDF.
- **Diffuse and specular separated**, demodulated by material, so albedo is applied after denoising.
- **Optional confidence** in [0,1] per signal, "the best way to mitigate temporal lags".

NRD also states that with FP16 internals and second moments, HDR input should stay in [0, 250], because `x²`
must fit FP16. That constrains a 16-bit scene colour target. Its claim that the "SH" mode is "comparable with
DLSS-RR" is a vendor claim with no measurement.

Other first-party options:

- **FSR Ray Regeneration**: optional AO, SO, direct and indirect diffuse/specular signals. Vendor cost on an RX
  9070 XT: 8.10 ms at 1440p for four signals, 6.52 ms for indirect diffuse plus specular, 5.34 ms for indirect
  specular. RDNA 4, DirectX 12, SM 6.6, Windows 11 ([GPUOpen](https://gpuopen.com/amd-fsr-rayregeneration/)).
- **FSR Radiance Caching**: December 2025 preview of an online-trained cache, also RDNA 4 and DirectX 12
  ([GPUOpen](https://gpuopen.com/amd-fsr-radiancecaching/)).
- **OptiX**: a recurrent-autoencoder denoiser, CUDA/OptiX only, aimed at interactive and offline feedback, with
  no published latency ([page](https://developer.nvidia.com/optix-denoiser),
  [paper](https://research.nvidia.com/publication/interactive-reconstruction-monte-carlo-image-sequences-using-recurrent-denoising)).
- **FidelityFX Denoiser**: shadows and reflections only; there is no diffuse-GI denoiser
  ([GPUOpen](https://gpuopen.com/fidelityfx-denoiser/)).
- **Intel OIDN**: the credible first-party option, and not real-time. CPU or GPU, 1 spp to converged, RDNA 4
  supported, right for reference images ([openimagedenoise.org](https://www.openimagedenoise.org/)).

## 6. Machine-learning reconstruction

**DLSS Ray Reconstruction** replaces the game's denoisers and DLSS Super Resolution with one network. The
Streamline guide lists the inputs
([guide](https://github.com/NVIDIA-RTX/Streamline/blob/main/docs/ProgrammingGuideDLSS_RR.md)): noisy HDR colour,
depth, dense motion vectors, diffuse and specular albedo, normals and linear roughness, specular motion vectors
(or specular hit distance plus matrices), and optional transparency, SSS and DOF guides. It overrides DLSS SR,
does not support dynamic resolution scaling, expects 1 spp jittered input (the Blender integration notes this),
and needs an RTX GPU. NVIDIA claims
it was "trained on 5x more data than DLSS 3" and "replaces hand-tuned denoisers"
([2023](https://developer.nvidia.com/blog/generate-groundbreaking-ray-traced-images-with-next-generation-nvidia-dlss/)).
Both are vendor claims.

**DLSS 5** stops being a denoiser. It takes colour and motion vectors plus engine data (albedo, normals,
lighting) and *generates* high-frequency detail, including AO and GI, deterministically, one frame in and one
frame out. It needs RTX 50-series hardware and shipped in September 2026
([NVIDIA](https://www.nvidia.com/en-us/geforce/news/dlss-5-3d-guided-neural-rendering/)). Treat it as a vendor
claim about a new product.

**AMD's research line** is the non-NVIDIA counterpart: a joint denoise-and-upscale network trained on 1 spp
input, taking colour plus albedo, normal, roughness, depth and specular hit distance, with SSIM and LPIPS
comparisons
([GPUOpen](https://gpuopen.com/learn/neural_supersampling_and_denoising_for_real-time_path_tracing/), I3D 2025).
Its shipping form is FSR Ray Regeneration.

| Feature | Lock |
|---|---|
| DLSS Ray Reconstruction | NVIDIA RTX, Windows, HDR pipeline |
| DLSS 5 | NVIDIA RTX 50 series |
| FSR Ray Regeneration | AMD RDNA 4, DirectX 12, Windows 11 |
| FSR Radiance Caching | AMD RDNA 4, DirectX 12, Windows |
| NRD | Vendor-neutral, needs the G-buffer contract |
| OIDN | Vendor-neutral, not real-time |

## 7. Radiance caches

A radiance cache stores incoming radiance at world-space points so a path can stop early. Ward's 1988 irradiance
cache is the origin: it stores indirect illuminance at selected points, reuses it across views, and "the density
of the calculation is adjusted to maintain a constant accuracy"
([SIGGRAPH 1988](https://eta.lbl.gov/publications/ray-tracing-solution-diffuse)). That is still the trade: more
points for accuracy, fewer for memory.

| Cache | Stores | Update cost | Bias and failure |
|---|---|---|---|
| SHaRC | Hash grid, 40 B/voxel | ~4% of paths/frame, 160 MiB at `2^22` | Stale entries, collisions, thin walls |
| NRC | Online-trained MLP | ~2.6 ms at 1080p (2021 HW) | Training cost, "little induced bias" (authors) |
| ORCA | Multi-scale voxel hash, no history | 5.04 ms at 864p, incl. 1.97 ms PT | Voxel shapes, misses, firefly pollution |
| Neural visibility | MLP + hash grid over visibility | Not stated | Sampling only, not radiance |

SHaRC uses three buffers (hash, per-frame accumulation, resolved), 40 bytes per voxel or 64 with directional
encoding, and a suggested `2^22` elements (160 MiB). The update traces "one random pixel per 5×5 block, ~4% of
paths", spreads coverage over time, accumulates with a maximum frame count, and evicts stale entries; expected
occupancy is 10–20% ([integration guide](https://github.com/NVIDIA-RTX/SHARC/blob/main/docs/Integration.md)).
NRC trains while rendering, reports "about 2.6 ms on full HD resolution" for updates and queries, and needs no
pretraining ([SIGGRAPH 2021](https://arxiv.org/abs/2106.12372)). Neural visibility caches store visibility
rather than radiance and feed weighted reservoir sampling
([JCGT 14(2)](https://jcgt.org/published/0014/02/01/)).

ORCA (EA SEED) keeps no temporal state: "all data structures are instantaneous and don't need to survive the
frame" ([SIGGRAPH 2026](https://advances.realtimerendering.com/s2026/)). It uses a multi-scale voxel hash
(`8^-2` to `8^3`), 4-bit octahedral directions (256 slots), sparse paths at roughly 1/16 rate, and a
reconstruction pass that scans from small to large voxels until it hits. On an Xbox Series X-class machine at
864p, 14.2 ms of path tracing becomes a 5.04 ms pass that includes 1.97 ms of sparse tracing; on PS5 Pro at
1080p, 38.42 ms becomes 21.75 ms. Miss rate is "< 1–2%". The talk says ORCA "hasn't shipped yet".

The bias is structural: a cache answers "radiance here and now" with data from another point, direction, or
time. That is the à-trous bias moved to world space and amortised over frames. ORCA's slides list the failures:
tunnelling through thin walls (first hit only, no distance in the key), fireflies polluting the cache (clamp
before store, "booo"), voxel-shaped highlights after denoising (dither the lookup), and hash collisions (second
checksum hash).

## 8. Reuse before reconstruction: ReSTIR GI

ReSTIR GI resamples indirect paths, not pixels. Each pixel keeps a reservoir of candidate paths; temporal and
spatial passes merge reservoirs with resampled importance sampling, plus a Jacobian to move a sample between
shading points ([HPG 2021](https://d1qx31qr3h6wln.cloudfront.net/publications/ReSTIR%20GI.pdf)).

| Measurement, 1080p RTX 3090 | Value |
|---|---|
| MSE improvement at 1 spp | 9.3× to 166× |
| Equal-time | 8.0 ms path tracing vs 8.9 ms ReSTIR GI, 15.1× MSE |
| Initial sampling / reuse | 3.2 ms one bounce, 4.6 ms reuse (1920×1050, RTX 3080) |
| Memory | 475 MB, 48 B per reservoir |
| Bandwidth | 570 MB/frame read, 285 MB/frame write |
| Reuse limits | temporal `M ≤ 30`, spatial `M ≤ 500` |

The bias section is the part to read before adopting it:

- **Spatial reuse is biased** unless a visibility ray proves the source PDF covers the current pixel. The
  unbiased form costs a ray per reused sample.
- With the biased form, "bias is mainly in shadow areas due to visibility change", and glossy floors make it
  worse because the target function concentrates samples near the reflection direction.
- **Temporal reuse is biased** in dynamic scenes because stored radiance goes stale. The authors re-trace and
  validate every 6 frames, and clamp `M` so a bright sample cannot become un-replaceable. The reconnection
  Jacobian is cheap and "there is no reason not to include" it.

Reuse changes what the denoiser sees. The surviving samples are no longer independent: neighbouring pixels share
path vertices, so noise is spatially correlated and a 3×3 variance estimate underestimates it. The distribution
also becomes more uniform in direction while staying heavy-tailed in radiance. That correlation point is my
reading, not a claim in the paper; the paper claims "a substantial error reduction" and, "in conjunction with a
denoiser", real-time GI.

## 9. Probe-based reconstruction

DDGI replaces per-pixel rays with a probe grid. Each probe stores an 8×8 octahedral irradiance map and a 16×16
octahedral depth/depth² map. Shading looks up the eight probes of the cage around the point, weights by
trilinear position, backface direction and a Chebyshev visibility test against the stored mean and variance of
depth ([JCGT 8(2), 2019](https://www.jcgt.org/published/0008/02/01/)).

The update is the reconstruction: trace `n` rays per probe on a rotated Fibonacci spiral, shade the hit surfels
with the same routine as pixels, blend into the octahedral texels with hysteresis `α` of 0.85–0.98, and filter
irradiance by a cosine lobe during the update. At 1080p on an RTX 2080 Ti with 32×8×32 probes at 64 rays, the
probe update is 0.7 ms of a 2.6 ms indirect budget, and per-pixel probe sampling is 0.5 ms. The paper reports 6
ms/frame for the full pipeline against about a minute offline, and above 1.5 GRays/s in most configurations.

There is no per-pixel denoiser here. The per-pixel work is eight probe fetches plus a Chebyshev test. Noise is
absorbed by the probe's temporal accumulation, so there is no radiance history clamp and no per-pixel
disocclusion test. Cost also does not scale with resolution, which is why probe grids fit fixed budgets.

The 2021 follow-up adds what production needs ([JCGT 10(2)](https://www.jcgt.org/published/0010/02/01/)):
**relocation** moves probes out of static geometry by at most half the grid spacing; **classification** into
`Off`, `Sleeping`, `Newly Awake`, `Newly Vigilant`, `Awake`, `Vigilant` skips work on probes that cannot affect
the image; a **self-shadow bias** replaces several Chebyshev parameters with one world-space term, and backface
hits are ignored so a probe inside an object does not leak; **per-texel hysteresis** drops after a large
lighting change to shorten latency. Stated limits: low-frequency signal only, "an unavoidable minimum latency",
memory-heavy storage in large worlds, and leaks when probe density is too low.

## 10. Validation

There is no single number. Each metric hides a different failure.

| Metric | Catches | Hides | Used by |
|---|---|---|---|
| MSE / RMSE vs reference | Overall error, fireflies | Blur, which lowers error | ReSTIR GI, SVGF |
| SSIM | Structure | Blur; smoother can score higher | SVGF, BMFR |
| VMAF | Perceptual video quality | Localised temporal artefacts | BMFR |
| Temporal error | Frame-to-frame flicker | Ghosting and lag, which are stable | SVGF §5.4 |
| Equal-time | Practical cost | Implementation quality | ReSTIR GI, BMFR |

SSIM is Wang et al., "Image Quality Assessment: From Error Visibility to Structural Similarity", IEEE TIP 2004;
VMAF is Netflix's Video Multi-Method Assessment Fusion. SVGF defines its temporal-error metric as the average
luminance of the per-frame difference.

SVGF's own evaluation is the cautionary example: the edge-avoiding wavelet filter has lower temporal error than
SVGF because it blurs more, and SVGF still wins on image quality. "While EAW exhibits higher temporal stability
than our SVGF, it has significantly higher reconstruction error"
([§5.4](https://cg.ivd.kit.edu/publications/2017/svgf/svgf_preprint.pdf)).

Protocol, assembled from what the papers do:

1. **Fix the reference.** Path trace at 4096 spp (SVGF) or use an offline render. Compare at 1:1, not on a
   tonemapped thumbnail.
2. **Compare at equal time.** ReSTIR GI's headline is 8.0 vs 8.9 ms. A 1 spp method at 8 ms is not cheaper than
   a 4 spp method at 6 ms.
3. **Report temporal error twice.** Frozen camera measures convergence; moving camera measures lag. They
   disagree by design.
4. **Test three artefacts separately.** Over-blurring: high-frequency detail against the reference. Light
   leaking: camera inside a closed box, as Epic's Lumen page does. Fireflies: a dark interior with one small
   bright source.
5. **Instrument the internals.** Epic exposes rejection, clamping and accumulation masks; NRD exposes history
   length, resets and normalized hit distance; CoD shows ray-request heatmaps. A denoiser without these is
   untunable.

Missing from the literature I read: a standard temporal-stability benchmark and a perceptual study of GI
denoising artefacts.

## 11. Comparison

Source numbers refer to §13. Costs are as reported; hardware and resolution are in the cell.

| Method | Inputs | Cost | Stability | Main artefact | Shipping | Src |
|---|---|---|---|---|---|---|
| TAA only | Colour, depth, velocity | ~0.2–1 ms | Good when static | Ghosting, clamp energy loss | Universal | 14, 15 |
| SVGF | Colour, depth, normal, moments | 10.2 ms, 1080p, Titan X | 10× prior work | Over-blur, variance underestimation | Baseline | 1, 12 |
| A-SVGF | SVGF + gradient samples | 2 ms, 1080p, temporal only | Better lag | Gradient-sample ray cost | Research | 2 |
| BMFR | Colour + feature buffers | 2.4 ms, 720p, Titan X | Good | Block artefacts, blurred highlights | Research | 3 |
| NRD REBLUR | G-buffer + hit distance | 2.55 ms, 1440p, RTX 4080 | High | Lag on fast light change | 15+ titles | 4 |
| NRD RELAX | G-buffer + hit distance | 3.25 ms, 1440p, RTX 4080 | High | Needs clean RTXDI input | RTXDI | 4 |
| NRD SIGMA | Shadow mask + distance | 0.40 ms, 1440p, RTX 4080 | High | Contact-hardening errors | Shadows | 4 |
| OptiX | Beauty + albedo/normal | Not stated | Not real-time | Blur, smear | DCC preview | 21 |
| FidelityFX Denoiser | Shadow or reflection rays | Not stated | Good | No GI path | Shadows, reflections | 23 |
| FSR Ray Regeneration | AO/SO, DI/DS, II/IS | 6.52 ms, 1440p, RX 9070 XT | Vendor claim | RDNA 4 / DX12 lock | Shipping 2026 | 20 |
| DLSS Ray Reconstruction | Colour, depth, MV, albedo, normals, roughness | Not stated | Vendor claim | Vendor lock, no DRS | Shipping 2023– | 16 |
| ReSTIR GI + denoiser | G-buffer + reservoirs | 8.9 ms, 1080p, RTX 3090 | Good | Shadow bias, 475 MB | Research | 6 |
| DDGI | Probes + rays | 2.6 ms, 1080p, RTX 2080 Ti | Very stable | Leaks, latency | RTXGI, UE, Unity | 7, 8 |
| SHaRC | Hash grid + sparse paths | ~4% paths + 160 MiB | Accumulated | Stale entries, collisions | RTXGI | 11 |
| NRC | Neural cache + tracer | ~2.6 ms, 1080p | Accumulated | Training cost, bias | Research | 9 |
| ORCA | Voxel hash, no history | 5.04 ms, 864p | Instantaneous | Voxel shapes, misses | Not shipped | 10 |

## 12. Decision guide

The renderer here has: forward pass, motion vectors, depth, 16-bit scene colour, 32-bit RGBA history, 512-sample
cap, 1440p, RX 9060 XT (RDNA 4), Vulkan, and a 1–2 ms budget. No G-buffer means no world normals or roughness
for a filter.

Budget arithmetic removes most options:

- 1440p is 3.69 Mpx, 1.78× the pixel count of 1080p.
- SVGF's five-iteration spatial pass is 3.77 ms static at 1080p on an RX 7800 XT, a faster card. Scaled by pixel count
  alone, 1440p is about 6.7 ms, before variance and before rays.
- NRD ReBLUR is 2.55 ms at 1440p on an RTX 4080, and needs the G-buffer this renderer does not have.
- FSR Ray Regeneration is 5.34–8.10 ms at 1440p on an RX 9070 XT, and is DirectX 12 and Windows 11 only. This
  renderer is Vulkan.
- DLSS Ray Reconstruction and DLSS 5 need NVIDIA hardware.
- ReSTIR GI is 8.9 ms and 475 MB at 1080p; at 1440p the reservoirs scale to roughly 844 MB by pixel count,
  before double buffering.

What is left:

| Option | Why it fits | Cost | What to watch |
|---|---|---|---|
| A. Temporal + 2–3 à-trous iterations at half res, separate GI signal | Half-res 1440p is 0.92 Mpx, 0.44× the 1080p count. Three iterations are ~1.9 ms at 1080p on the 7800 XT, so ~0.8 ms scaled. Estimate, not a measurement. | Detail loss from half res; needs a depth/luma edge stop without normals | Fireflies survive iteration one and smear; clamp before accumulation |
| B. DDGI-style probe grid | 0.7 ms probe update at 1080p on a 2080 Ti, independent of output resolution | Low-frequency GI only; hysteresis latency; grid memory | Leaks at low density; relocation needs static geometry |
| C. Temporal accumulation only, wide clamp | Nearly free inside the existing resolve | Ghosting at disocclusion; energy loss on moving GI | The existing 2σ YCoCg clip will crush fireflies |

Option A is closest to the current pipeline. Option B is the only one whose cost does not grow with resolution,
which matters at 1440p. Option C is what happens by default if GI goes into scene colour and nothing else
changes.

Four constraints decide between them:

1. **Signal separation.** Denoise GI separately from direct light. NRD requires diffuse and specular separated
   at the primary hit and demodulated by material, because a filter that sees direct-light edges cannot use a
   wide kernel on the GI. The current resolve sees composited colour; feeding it GI would clamp the GI against
   direct-light variance.
2. **Precision.** The 16-bit scene colour is fine for display, not for accumulation. NRD's rule is [0, 250] for
   HDR input when second moments are FP16. The 32-bit history is the right place for radiance, and 512 samples
   is generous against NRD's 32-frame baseline.
3. **Fireflies.** Clamp before history, not after. NRD caps energy growth at 20–30×; ORCA clamps before storing
   and calls it "booo" while doing it. A clamp is a bias; an unclamped firefly is a smear that lasts as long as
   the history.
4. **Disocclusion.** Without a G-buffer the test is depth plus velocity, which the current resolve already does
   with a 2% depth tolerance. A GI signal with a 512-frame history will lag at disocclusion unless the count
   resets. Same rule as TAA, but more visible because GI is low frequency.

Two things not to do on this budget: run full SVGF at 1440p, or adopt a neural denoiser that needs a G-buffer.
Both exceed the budget before the rays are traced.

## 13. Reading list

Read in this order. Numbers match the `Src` column above.

1. **Schied et al., "Spatiotemporal Variance-Guided Filtering", HPG 2017.** The baseline: temporal pass,
   moments, à-trous weights. [PDF](https://cg.ivd.kit.edu/publications/2017/svgf/svgf_preprint.pdf)
2. **Schied, Peters, Dachsbacher, "Gradient Estimation for Real-Time Adaptive Temporal Filtering", PACMCGIT
   2018.** The lag fix.
   [PDF](https://cg.ivd.kit.edu/publications/2018/adaptive_temporal_filtering/adaptive_temporal_filtering.pdf)
3. **Koskela et al., "Blockwise Multi-Order Feature Regression", ACM TOG 2019.** The regression alternative.
   [PDF](https://webpages.tuni.fi/foi/papers/Koskela-TOG-2019-Blockwise_Multi_Order_Feature_Regression_for_Real_Time_Path_Tracing_Reconstruction.pdf)
4. **NVIDIA NRD, README v4.18.0.** Integration contract, cost, memory.
   [GitHub](https://github.com/NVIDIA-RTX/NRD)
5. **Yang, Liu, Salvi, "A Survey of Temporal Antialiasing Techniques", CGF 2020.** Clamp failure modes.
   [PDF](http://behindthepixels.io/assets/files/TemporalAA.pdf)
6. **Ouyang et al., "ReSTIR GI", HPG 2021.** Reuse, plus the bias section.
   [PDF](https://d1qx31qr3h6wln.cloudfront.net/publications/ReSTIR%20GI.pdf)
7. **Majercik et al., "Dynamic Diffuse Global Illumination", JCGT 8(2), 2019.**
   [JCGT](https://www.jcgt.org/published/0008/02/01/)
8. **Majercik et al., "Scaling Probe-Based Real-Time Dynamic Global Illumination for Production", JCGT 10(2),
   2021.** [JCGT](https://www.jcgt.org/published/0010/02/01/)
9. **Müller et al., "Real-time Neural Radiance Caching", SIGGRAPH 2021.**
   [arXiv](https://arxiv.org/abs/2106.12372)
10. **Greenberg, "Speeding up Path Tracing via ORCA", SIGGRAPH 2026 Advances.** Slides only.
    [Course](https://advances.realtimerendering.com/s2026/)
11. **NVIDIA SHaRC integration guide.** Bytes per voxel, occupancy, eviction.
    [GitHub](https://github.com/NVIDIA-RTX/SHARC/blob/main/docs/Integration.md)
12. **Pikulsky, "Optimizing SVGF for Modern GPU Architectures", JCGT 15(1), 2026.**
    [JCGT](https://jcgt.org/published/0015/01/02/)
13. **Olejnik, "Variable Rate Ray Tracing in Call of Duty: Modern Warfare 4", SIGGRAPH 2026 Advances.**
    [Course](https://advances.realtimerendering.com/s2026/)
14. **Epic, "Temporal Super Resolution".**
    [Docs](https://dev.epicgames.com/documentation/unreal-engine/temporal-super-resolution-in-unreal-engine)
15. **Karis, "High Quality Temporal Supersampling", SIGGRAPH 2014.**
    [Slides](https://de45xmedrsdbp.cloudfront.net/Resources/files/TemporalAA_small-59732822.pdf)
16. **NVIDIA, DLSS Ray Reconstruction Streamline guide.**
    [Guide](https://github.com/NVIDIA-RTX/Streamline/blob/main/docs/ProgrammingGuideDLSS_RR.md)
17. **Epic, "Lumen Technical Details".** Leaks, trace distance, latency.
    [Docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-technical-details-in-unreal-engine)
18. **Bokšanský, Meister, "Neural Visibility Cache", JCGT 14(2), 2025.**
    [JCGT](https://jcgt.org/published/0014/02/01/)
19. **Ward, Rubinstein, Clear, "A Ray Tracing Solution for Diffuse Interreflection", SIGGRAPH 1988.**
    [Record](https://eta.lbl.gov/publications/ray-tracing-solution-diffuse)
20. **AMD, FSR Ray Regeneration and FSR Radiance Caching.** [RR](https://gpuopen.com/amd-fsr-rayregeneration/),
    [RC](https://gpuopen.com/amd-fsr-radiancecaching/)
21. **NVIDIA, OptiX AI-Accelerated Denoiser.** [Page](https://developer.nvidia.com/optix-denoiser)
22. **AMD, "Neural Supersampling and Denoising for Real-time Path Tracing".**
    [GPUOpen](https://gpuopen.com/learn/neural_supersampling_and_denoising_for_real-time_path_tracing/)
23. **AMD, FidelityFX Denoiser.** [GPUOpen](https://gpuopen.com/fidelityfx-denoiser/)

## 14. Open problems, as the sources state them

- **Short history is unsolved.** CoD: the spatial filter is unstable at small radius with short history, a
  larger radius adds bias, and the variance estimate is wrong exactly then. Their answer is more rays in
  unstable pixels.
- **Variance underestimation at low spp.** SVGF states it: one sample gives a poor spatial variance estimate,
  and rare bright paths look stable.
- **Bias from reuse.** ReSTIR GI's unbiased form needs a visibility ray per reused sample; the biased form
  concentrates error in shadows and gloss.
- **Cache staleness.** DDGI accepts latency by design; SHaRC needs eviction; ORCA avoids the problem by keeping
  no history.
- **ORCA is not shipped.** Its numbers are a demo on PS5 Pro and Xbox Series X-class hardware.
- **Neural denoisers are black boxes with vendor locks.** NRD's SH mode claims DLSS-RR quality; no independent
  measurement exists in these sources.
- **No standard metric.** SSIM rewards blur, temporal error rewards ghosting, MSE is dominated by fireflies.
  Nobody reports all three on the same scene.

## What did not check out

- **"SVGF costs 10 ms" is a 2017 Titan X number.** The same algorithm is 3.77 ms for five iterations at 1080p on
  an RX 7800 XT, and 1.67 ms for one iteration.
- **NRD's "comparable with DLSS-RR"** is a README claim with no measurement, scene, or metric attached.
- **ACM returned 403** for the Ward 1988 and ReSTIR GI record pages. Their content here comes from the LBNL
  record and the author PDF.
- **The LBNL PDF of Ward 1988 sits behind a Cloudflare challenge.** Only the abstract page was readable; the
  "constant accuracy" quote is from it.
- **FLIP could not be verified.** No first-party page resolved, so it is not cited despite being a common
  denoiser metric.
- **ORCA has no paper.** All numbers come from text extracted from a 436 MB PPTX; the abstract only claims "no
  temporal history".
- **"Denoisers replace ray tracing" is not what the sources say.** Every method here still traces rays. The best
  results spend effort on better samples first.
- **JCGT volume number:** the SVGF optimisation paper is Vol. 15, No. 1, 2026 in the PDF header. The
  ambient-occlusion note cites 16(1). The PDF wins.

