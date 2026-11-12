# Lighting system review: the mixed baked-indirect / real-time-direct pipeline

Date: 2026-11-10
Status: partial. The architecture and the code findings are answered; the
evidence gaps are named, not guessed.

Scope: this reviews the lighting system in this repository. The request excludes
path tracing, ray-traced GI, and every method whose image depends on stochastic
noise plus a denoiser. The existing offline bake and the existing hard ray-query
direct shadows are the baseline, not a recommendation. If "no ray tracing" also
means removing the direct shadow rays, the alternative is a shadow-map path;
that is called out separately.

The repository has no lightning or weather system. "Lightning" is read as the
lighting/illumination system.

Companion notes in this directory:

- `baked-gi-lightmaps.md` — radiosity, lightmap baking, charting, filtering,
  multi-bounce, and the atlas growth limits.
- `probe-volumes-and-sh.md` — irradiance volumes, SH, DDGI, storage formats, and
  a source-level comparison to this probe field.
- `realtime-gi-without-rays.md` — LPV, RSM, SSGI, SDFGI, radiance cascades, PRT,
  and the selective LPV proposal for this arena.
- `direct-lighting-and-shadows.md` — clustered forward+, shadow maps, PCSS, LTC,
  ray-query costs, falloff, and the direct-light scale risks.
- `production-lighting-case-studies.md` — shipped analogues, budgets, and the
  production failure modes of this architecture.

The review below is the synthesis; the companion notes carry the source-level
detail and the annotated bibliographies.

## Answer

The core is sound and correctly matched to the design rule. The rule is: static
objects are baked and immovable; every other object is movable and direct-only.
That is the same family as Unreal's Stationary lights plus Volumetric Lightmaps,
and Unity's Mixed lighting plus Adaptive Probe Volumes.

The weak points are implementation details, not the split.

1. The probe field is an 8 x 8 octahedral irradiance map decoded in the shader.
   The decode is applied after the four-probe interpolation, so the interpolation
   is not linear in radiance. At a 50/50 mix of a lit and an unlit probe the
   result is about half the linear value. This may be a deliberate gamma-2 blend
   (DDGI uses the same order) or an unintended bias; either way it darkens
   lit/unlit boundaries, and a capture should decide which it is.
2. A movable crate receives the static probe field but does not occlude it or
   contribute to it. That follows from the rule. The open question is visual:
   the contact between a 1 m probe field and a 25 cm lightmap is unmeasured.
3. One diffuse bounce is enough for the evidence captured so far. The arena is
   closed, so a second bounce exists in corners; the project has no reference
   bake to say how large it is. A deterministic radiosity or iterative-lightmap
   solve would add it without noise.

A short list of smaller items (the emissive-as-lamp shadow mask, the fixed
atlas, the hard-coded probe bounds, and the debug constant) is in the findings.

## 1. What the system is

The arena is a closed 40 m box with 5.5 m walls and a ceiling. Every object is a
box drawn with one cube mesh. There is no surface texture, normal map, specular
term, or tone map.

```text
static fixture ─┬─> direct: clustered point light, 1 ray/pixel ──> hard shadow
                └─> bake: 128 cosine rays/texel ──> 1024² RGBA16F lightmap
static geometry ───> bake: 1024 rays/probe ───────> 1 m probe grid (8×8 octa)
dynamic lamp ──────> direct only
dynamic object ────> direct + probe sample
emissive box ──────> albedo * emissive (not a light source)
```

- Direct: point lights, a 16 x 9 x 24 cluster grid with a fixed 256-index stride
  per cluster. The fixed stride and first-N overflow policy make it closer to
  Light Indexed Deferred than to canonical Forward+ (which uses variable-size
  lists). Finite-range falloff `(1 - (d/r)²)²`, one hard ray query per light per
  fragment against a per-frame TLAS. `src/renderer/shaders/terms.glsl:85`;
  `src/renderer/shaders/cluster.glsl:5`.
- Emissive: `albedo * emissive`; it is not a direct light and it does not cast a
  shadow. `src/renderer/shaders/box.frag:33`, `src/renderer/lights.odin:25`.
- Static indirect: one diffuse bounce. Static boxes read a 1024² RGBA16F atlas
  at 4 texels/m (25 cm per texel), one chart per box face, 128 cosine-weighted
  rays per texel, then a separable 3 x 3 binomial pass per chart.
  `src/bake/bake.odin:17`, `src/bake/lightmap.odin:157`,
  `src/bake/denoise.odin:6`.
- Dynamic indirect: a static probe grid at 1 m spacing (40 x 5 x 40 = 8000
  probes), 8 x 8 octahedral irradiance plus depth moments, 1024 rays per probe,
  tetrahedral interpolation of four probes, normal bias, facing weight, and a
  Chebyshev depth test. `src/bake/probe.odin:191`;
  `src/renderer/shaders/probe.glsl:172`.
- Bake lifecycle: a keyed `.hbake` artifact with `missing`, `stale`, `current`,
  and `failed` states. A static edit marks it stale; the old indirect stays
  bound until an explicit publish. `docs/adr/0044-bake-data-contract.md`,
  `docs/adr/0045-mixed-static-baked-indirect.md`.
- Runtime cost: 1.50–1.52 ms GPU total at 1080p with 96 synthetic lights; the
  lightmap and probe terms add about 0.03 ms. `docs/evidence/mixed-lighting.md`.
- Bake cost: about 5.1 s at 16 threads, 3.0–3.1 s of it in the lightmap stage,
  1.9 s in the probes, and a 14.6 MB artifact. The 2 s target is missed.
  `docs/evidence/mixed-lighting.md`.

## 2. What it gets right

These are not consolations; they are the reason the system is worth refining
rather than replacing.

- Determinism. The bake seed follows the surface, not the atlas position, and
  the result is independent of thread count. Three 1 m runs wrote identical
  bytes. That is a stronger property than most lightmap bakers offer, and it is
  what makes the stale/current contract meaningful.
- No silent fallback. A missing or failed artifact binds placeholders and reports
  the state. It does not quietly turn into black or into an old bake. Most
  engines would do the opposite.
- Observability. The term views (`direct`, `lightmap`, `probe`, `emissive`,
  `shadow`, `lightmap_grid`, `probe_cell`) turn "which term is this pixel?" into
  a capture instead of a guess. `docs/adr/0046-diagnostic-views.md`.
- A coherent art direction. Absolute darkness, hard shadows, flat boxes, and one
  texture are consistent decisions, not accidents. The lighting serves the look.
- The lightmap stores one RGB value per texel, not a directional basis. Source's
  Radiosity Normal Mapping stores three lightmaps per texel to support normal
  maps; here every face has one constant normal, so one RGB lightmap is the
  right amount of data. Do not add RNM or a directional lightmap for the current
  geometry; it would triple memory for a normal that does not vary across a face.
- A real evidence protocol. Paired captures, fixed regions, stddev and gradient
  as noise measures, sealed-cell leak tests, byte-identical bake runs. The
  project measures the thing it claims.

### 2.1 The production analogue

The closest shipped match is Frostbite's *Battlefield 3* path: lightmap-lit static
geometry receives and bounces, lightprobe-lit dynamic geometry receives only,
dynamic lights contribute direct light, and a static precompute changes only when
the geometry changes. Unity's Baked Indirect plus APV and Unreal's Stationary
plus Volumetric Lightmaps are the general-purpose versions of the same split.
The 25 cm lightmap density matches Frostbite's *Battlefront II* target; the 1 m
probe grid is denser than *The Division*'s 4 m grid. The architecture is
conventional, not exotic.

That is the strongest argument for keeping the current shape. It also names the
real risk: not the algorithm, but the known failure modes of this pattern —
thin-wall probe leaks, stale indirect mistaken for current, and "looks right"
judged without a corner, contact, or colour-bleed test.

See `production-lighting-case-studies.md` for the case-by-case sources.

## 3. The bias ledger

"Noise-free" does not mean "unbiased". Every method that avoids a stochastic
estimator pays for it with a deterministic approximation. The useful question is
not "which method has no noise?" but "which bias can the look tolerate?".

| Method | What it assumes | The bias it buys |
| -- | -- | -- |
| Baked lightmap / radiosity | Static geometry and lights, diffuse surfaces | Texel resolution, seams, leaks through thin walls, bake time |
| Irradiance volume | The field is low-frequency and can be interpolated on a grid | Probe spacing, leaks, normal bias, invalid probes |
| Spherical harmonics | The transfer is low-frequency | Ringing, loss of sharp visibility, order-dependent error |
| Reflective shadow maps | One bounce from the shadow-map texels | Noise from VPL sampling, missing off-screen transport |
| Light propagation volumes | The field can be propagated on a coarse lattice | Light bleeding, anisotropy, grid resolution |
| Screen-space GI / SSDO | The needed transport is on screen | Off-screen failure, thickness, edges |
| Shadow maps / PCSS | A depth map is enough visibility | Bias, peter-panning, cube seams, penumbra approximation |
| Ray-query shadows | One ray is the visibility | Hard edge, per-pixel cost, RT hardware |
| LTC area lights | The light is a polygon and the BRDF fits the LTC family | No visibility, polygon approximation |
| SDFGI | The scene fits a signed distance field | Convergence over 25–30 frames, no dynamic occluders |
| Radiance cascades | The radiance field can be reused across scales | SDF memory/build cost, implementation complexity |

The current system's bias set is: static-only transport, one bounce, 25 cm
surface resolution, 1 m volume resolution, no dynamic occlusion, hard shadows,
and a non-inverse-square falloff. Several of those are deliberate. The review
below separates the deliberate ones from the ones that show.

## 4. Findings

### 4.1 High: probe reconstruction is a gamma-2 blend, not a linear average

`src/renderer/shaders/probe.glsl:242` accumulates `pow(encoded, 2.5)`, which is
`sqrt(radiance / 2)`, then line 248 squares the weighted average and multiplies
by two. That is an average in square-root space, not a linear average of
radiance.

For two equally weighted probes with values `L` and `0`:

```text
stored encoded value        (L/2)^(1/5)
decoded before weighting    sqrt(L/2)
average of four probes      sqrt(L/2) / 2
square and scale by two     L/4
linear average              L/2
```

The effect is strongest at a lit/unlit boundary, which is exactly where a probe
field is visible: contact, corners, and the edge of a lamp's reach. The same
nonlinearity applies inside one probe, because the 8 x 8 atlas is sampled with a
hardware bilinear tap on encoded values (`probe_atlas_uv`, line 57). The
lightmap does not have this problem: it is linear `RGBA16F`.

This may be deliberate. DDGI-Production uses the same gamma-5 storage and the
same `pow(encoded, 2.5)` decode to leave a gamma-2 curve; the reason is
perceptual temporal convergence and firefly reduction, not a linear estimator.
A static bake has neither a temporal filter nor fireflies, so the original
reason does not apply, but the look may still be the one that was tuned. The
comment at `src/renderer/shaders/probe.glsl:169` calls the encoding "legacy",
which suggests the order was not re-examined when the field became static.

If the intent is linear irradiance, fix it in one of these ways:

1. Store linear radiance in the probe atlas. `R11G11B10F` or `RGBA16F` is enough,
   and it removes the `pow` from the inner loop.
2. If the gamma encoding stays, decode each tap to linear before weighting and
   average linear values. For the intra-probe tap this means four `texelFetch`
   taps and a manual bilinear decode, because the sampler filters the encoded
   values.
3. Replace the directional map with SH9 (see 4.6), which has no decode step.

If the gamma-2 blend is the intended look, document it next to the decode and
keep it; then the finding is "test whether the darkening at contact is
acceptable", not "fix the math".

Severity: high if the darkening is visible; medium if the blend is intentional.
Cost: low for (1), medium for (3). Evidence needed: a paired capture of a
dynamic crate at a lit/unlit probe boundary, decoded both ways.

### 4.2 The static/direct rule is intentional, not a defect

ADR 0045 states the rule: a static fixture bakes one bounce and cannot move; a
movable lamp is direct-only. That is the intended architecture. The three starting
lamps are static because they are authored fixtures. A movable lamp placed in the
game is direct-only by definition. To get baked indirect from a lamp, the lamp has
to be static and immovable.

A movable crate receives direct light and the static probe field but does not
occlude or contribute to it. That also follows from the rule. The open question is
visual: the contact between a 1 m probe field and a 25 cm lightmap is unmeasured.
Add a capture. Do not change the rule for it.

Dynamic GI is out of scope. LPV, Enlighten, SDFGI, and DDGI are not candidates
under this rule.

### 4.3 Medium: movable objects do not occlude or contribute indirect, by rule

The bake's inputs are the static boxes and the static fixtures. Movable crates and
the spider receive the probe field but do not enter it. A crate next to a wall
does not darken the wall's bounce; a crate on the floor does not change the floor's
lightmap. That follows from the rule, not from a bug. The visual question is how
large the contact mismatch is between the two baked fields.

There is also a resolution seam. A static floor samples a 25 cm lightmap; a
dynamic crate resting on it samples a 1 m probe grid with tetrahedral
interpolation. The two fields are baked from the same transport but at different
resolutions, and no evidence in the repository measures their agreement at a
static/movable contact. The existing seam test is static-to-static.

One more static/dynamic seam: a static box placed after the last bake has a slot
identity but no matching artifact slot, so `write_object_data` gives it weight
zero, not the probe path (`src/renderer/scene_object_data.odin:40-48`). Its
indirect term is black until a rebake. That is consistent with the rule "a static
box samples the lightmap". It is a stale-state edge case, visible in the status,
not a rule violation.

Noise-free mitigations:

- Screen-space ambient occlusion (GTAO/HBAO) applied to the indirect term, not
  as a replacement for it. A fixed sample pattern is deterministic; it darkens
  the contact under a crate without changing the bake. It cannot see off-screen
  geometry, but the contact case is on screen by definition.
- A small dynamic occlusion volume (a coarse voxel/SDF of the movable boxes)
  tested by the probe sample. More work, fewer screen-space failures.
- A probe/lightmap blend near the contact, so the two baked fields meet with the
  same value instead of a step.

Evidence needed: a crate placed in a corner, captured with the crate present and
removed, measuring the wall/floor indirect in the same region; and a
static/movable contact strip measuring the step between the lightmap and the
probe term.

### 4.4 Medium: static fixture direct shadows are a cost, not a defect

A static fixture has a static body. It cannot move, but its direct light and
shadow are evaluated per pixel per frame. That is correct for the rule: direct
light is always real-time so movable objects can receive it. Baking the static
fixture's direct shadow is an optional cost reduction, not a requirement. Unreal
Stationary does it; this renderer does not. The 25 cm lightmap is too coarse for a
crisp hard shadow, so a hybrid would need a separate shadow mask or a shadow map.
Measure it if the light count or resolution grows. Do not change the rule for it.

There is a free fix in the same loop. `point_light_radiance` computes
`diffuse = max(dot(normal, direction), 0)` at `src/renderer/shaders/terms.glsl:118`,
then traces the shadow ray at line 123 without testing `diffuse`. A light behind
a box face contributes zero, but the ray is still cast. Gating the ray on
`diffuse > 0` (and `falloff > 0`) is image-identical and roughly halves the
shadow rays on box faces. This is the first optimization to take; it does not
change the look and it does not need a new architecture.

### 4.5 Medium: emissive is used as lamp identity in the shadow mask

`src/renderer/lights.odin:25`:

```odin
return box.emissive > 0 ? LAMP_INSTANCE_MASK : BOX_INSTANCE_MASK
```

The shadow ray tests mask `0x02`; a lamp instance has mask `0x01`. The intent is
"a lamp must not block its own light". The implementation says "any emissive box
is invisible to every shadow ray". Consequences:

- A non-lamp emissive prop (the spider's eyes and abdomen marks, or a future
  glowing crate) casts no shadow.
- A lamp housing never occludes another lamp's light.
- Emission and opacity are conflated, so a future emissive material change
  silently changes visibility.

Fix: carry an explicit lamp identity (the prefab already has one) or a per-light
self-instance test. If the only goal is self-shadow avoidance, exclude the
emitting instance, not every emissive instance. The current `Lamp_Kind` is the
right source of truth; `emissive > 0` is not.

### 4.6 Medium: the probe representation is oversized for diffuse light

The probe field stores 64 directional texels per probe plus depth moments:
8000 probes x 64 x 4 channels x 2 bytes = 4.1 MB of irradiance, plus 2.0 MB of
moments. The artifact is 14.6 MB (13.9 MiB), of which 8 MiB (8.4 MB) is the
lightmap.

The angular resolution is defensible. DDGI uses the same 8 x 8 irradiance map,
and its own study finds probe count matters more than angular resolution. The
waste is the format: the fourth channel is always 1.0, so the map is 512 bytes
per probe where an 8 x 8 `R11G11B10F` map is 256 bytes. Dropping the unused
channel is the cheapest win in the system and changes no image.

SH9 is the stronger simplification, but not an automatic quality win. A
9-coefficient SH probe at f16 RGB is 54 bytes per probe; with the current 8 x 8
moments and state, the total falls from about 6.2 MB to 2.5 MB, not 10x, because
the moments dominate. It removes the gamma-5 decode, the octahedral seam, and
the nonlinear interpolation in 4.1. Unity's Adaptive Probe Volumes store SH L2
per probe (`SphericalHarmonicsL2` in `ProbeGIBaking.LightTransport.cs`);
Unreal's Volumetric Lightmap stores a third-order SH per sample in 4 x 4 x 4
bricks, with a de-ringing control (Epic, "Volumetric Lightmaps").

The catch is that SH9 has a spurious back lobe of about 1/16 the peak: a bright
emitter behind a thin wall can add false light in the opposite direction, and a
depth test cannot remove a lobe that lives in the reconstruction. The octa map
is local and measured, so a lamp behind a wall simply does not contribute to the
directions that cannot see it. For a high-contrast, hard-edged arena, that local
support is valuable. Test SH9 against the octa map on the dark side of a bright
emitter and at a thin wall before switching; window the coefficients if it wins.

The bigger leak lever is the depth map, not the irradiance basis. This field
uses 8 x 8 moments where DDGI uses 16 x 16. A thin occluder can fall between the
narrow `cos^50` cones. Spending the irradiance-format savings on a 16 x 16
moment map is a better trade than adding more irradiance texels if leaks are the
measured problem. The spatial leak surface is the 1 m grid, the two-probe
dilation radius, and the normal-only bias; the production fixes are thicker
walls or layer masks.

So the order is: drop the unused alpha and use `R11G11B10F`; test SH9; if leaks
dominate, spend the savings on depth resolution. See `probe-volumes-and-sh.md`
for the full source-by-source analysis.

Production probe volumes are adaptive, not uniform. Unreal's Volumetric
Lightmap uses an adaptive grid with higher density near geometry; Unity's
Adaptive Probe Volumes use 4 x 4 x 4 bricks and stream them. The uniform 1 m
grid is simpler and deterministic, but it spends the same density in open air
and inside crates. If the grid changes, adaptive density is the next step, not a
uniformly finer grid.

### 4.7 Medium: one bounce only

The bake traces one diffuse bounce: a texel ray hits a surface, and that hit is
shaded by the static lights and emissive. It does not gather the light that
already bounced onto the hit surface. In a closed arena, that missing term is
concentrated in corners and under overhangs. The evidence measures the first
bounce against no indirect; it does not measure the residual against a
multi-bounce reference.

Three noise-free ways to add it:

1. Iterate the existing gather. After the first lightmap is built, trace the same
   rays and look up the previous lightmap at each hit instead of only the direct
   light. Two or three iterations converge the low-frequency term. The ray set
   is unchanged, so the added noise is the same set of samples, not a new
   stochastic estimate. The cost is not free: each per-texel bounce re-traces
   the full 21.2M rays, about 3.0 s, so two bounces take the lightmap stage to
   about 6 s and three to about 9 s. The total bake would be 8–11 s, not 5 s.
2. Solve radiosity on the box faces. The scene is a set of rectangles, which is
   the natural domain of the radiosity form factor. A coarse face-level solve
   (hundreds of patches, not 165k texels) gives all bounces deterministically,
   then interpolate to the lightmap. This is the classic Goral et al. 1984
   method (DOI 10.1145/800031.808601) and it is a better fit for a box arena
   than a Monte Carlo gather. It is also cheaper than a per-texel second bounce:
   a few thousand patches with progressive/hierarchical radiosity can solve in
   under a second, but it needs a patch hierarchy, visibility, and a transfer
   step.
3. Let id Tech's and Source's bakers be the reference: they run multiple-bounce
   radiosity and spend far more samples than 128 per texel. id Tech's final
   lightmap preset is `1-4096-50` (4096 hemisphere samples) and can take a day
   for a campaign map (id Studio, "Lightmaps"); the project's 5 s budget is a
   different regime, so the right comparison is quality per second, not absolute
   sample count.

Iteration (1) is the smallest change and preserves the current artifact format
if the extra bounces are folded into the same lightmap. Radiosity (2) is the
cleaner long-term model and would also give a static-fixture direct term for
4.4. Do not call (1) "cheap": it triples the bake time.

The production evidence is split on whether this is worth doing. Frostbite,
Guerrilla, and Source bake multiple bounces; the flat-box look may not need them.
Measure the corner residual against a two-bounce build before paying for it. If
the residual is below the look threshold, keep one bounce and say so.

### 4.8 Medium: the bake misses its target and bakes faces that cannot be seen

The default bake is about 5.1 s against a 2 s target. The lightmap stage is 3.0 s
for 165,334 valid texels x 128 rays, plus the shadow rays from each hit. The
probe stage is 1.9 s for 8000 probes x 1024 rays.

The lightmap layout allocates six charts for every static box
(`src/bake/atlas.odin:56`). The arena shell is six boxes; its outer faces (the
underside of the floor, the outside of the walls, the top of the ceiling) are
outside the playable volume and can never be sampled. They still get charts and
rays. `texel_buried` skips texels inside another box, but an outer shell face is
not buried; it is simply unreachable.

Culling charts whose outward side is outside the playable volume, or whose face
is fully covered by another box, would cut both atlas pressure and ray count.
The exact saving needs a count from the bake report; the current report does not
separate visible from hidden charts.

The 2 s target is aggressive, not the bake. Five seconds is faster than every
AAA reference in the production note except Godot's quick presets; the issue is
the 5 s wait on a static edit, not the number. If the target is a promise, the
first levers are hidden-face culling, a 1-texel gutter, a 4-texel minimum chart,
and a better packer (4.9); if it is not, change the target and keep the quality.

Other options: a GPU bake (compute or rasterization, not ray tracing), an
incremental rebake of only changed charts, a lower ray count with a better
filter, or the radiosity solve in 4.7.

### 4.9 Low–medium: the fixed atlas and uniform texel density limit growth

The atlas is one 1024² `RGBA16F` image, 4 texels/m, shelf-packed, with a 4-texel
gutter and an 8-texel minimum chart. The raw valid-texel count is 165k of 1.05M
(about 16%), which suggests 6.3x headroom, but that number is misleading. The
4-texel gutter and 8-texel minimum chart turn a 1 m face into a 16 x 16
allocation for 8 x 8 valid texels (25% chart efficiency), a 4 m face into 24 x 24
for 16 x 16 (44%), and an 8 m face into 40 x 40 for 32 x 32 (64%). The current
content already occupies roughly 35–63% of the atlas.

At the current padding, a 2x linear arena (4x surface area) needs about
1.5–2.6M atlas texels and does not fit. Better packing alone can carry the 2x
case: a 1-texel gutter is enough for the bilinear footprint, a 4-texel minimum
chart is enough for the 3 x 3 filter, and a chart-mask packer reaches about 96%.
That takes the 2x content to roughly 689k texels and fits. A 2.5x arena is about
1.07M and just over the 1024² capacity; the next step is a second 1024² page or
a 4-byte HDR encoding. A single 2048² `RGBA16F` atlas is exactly 32 MiB
(33.55 MB) — the entire budget before the probes, so it does not fit with them.
Two 1024² pages (16 MiB of lightmap, about 22 MiB total) fit. `RGBE` at 2048² is
16 MiB (16.8 MB); BC6H at 8 bpp is 4 MiB (4.2 MB) if the format is available. (`src/bake/atlas.odin:74` for `Atlas_Full`; the bake tool
exposes only probe spacing and threads, `cmd/harbagsa-bake/main.odin:102`.)

So the first limit is the padding, not the atlas size. The order is: reduce the
gutter/min chart and pack better; add a second page or a 4-byte format; only
then raise the atlas or lower the density. `texlod`-style variable density is
the option after that, when a specific surface reads flat.

### 4.10 Medium: a static transform is an authoring change

The bake key and the runtime slot key both hash the static box transforms. A
mismatch between an authored box and the loaded artifact misses the chart and
falls back to direct light, so the box never carries a lightmap from its previous
position. The runtime editor refuses a bake-input edit; a transform change is
authored in the scene source or through `scene`/`place`, then rebaked. See ADR
0048 and `docs/evidence/bake-atlas.md`.

The old indirect for an authored fixture change is a world-space stale field
until the publish: the receivers did not move, so the old bounce remains. The
status says `stale`, so the state is visible.

### 4.11 Low for the current target, high if portability changes: ray-query-only shadows

The renderer requires `VK_KHR_acceleration_structure`, `VK_KHR_ray_query`, and
`VK_KHR_deferred_host_operations`, and has no fallback
(`docs/adr/0040-hard-point-light-shadows.md`). On the RX 9060 XT this is a good
trade: one hard ray per light per pixel, no shadow-map bias, no cube seams, and
a 1.50–1.52 ms GPU total at 1080p/96 lights. On a device without ray queries the game does
not start.

If the target ever widens, the portable path is a cube shadow map or a 2D shadow
atlas with PCF/PCSS. The bias ledger is different: cube seams, depth bias,
peter-panning, and a per-light render pass. The current ADR already considered
and rejected this for the measured target; the finding is not "change it", it is
"know that this is the hard portability boundary".

### 4.12 Low: the falloff is not inverse-square

`(1 - (d/r)²)²` reaches zero at the range with a smooth derivative, but it does
not fall as `1/d²`. Within range, moving a lamp closer does not brighten the
surface. For a game whose core verb is placing light in darkness, distance is a
depth cue; this falloff removes it. The finite range is a legitimate
performance/clustering choice; the missing inverse-square is a look choice.

If the look is intentional, document it next to the formula so it is not
"fixed" by a future contributor. If it is not, use a range-windowed
inverse-square (`1/d² * saturate(1 - (d/r)⁴)²` or the Frostbite/UE4 style) and
re-measure the 96-light scene. The bake and the direct path must use the same
falloff or the static/dynamic seam will grow.

### 4.13 Low: hard point lights have no radius

The shadow edge is hard because the light is a point. That is internally
consistent and fits the flat box look. If a lamp ever gets a radius, the
noise-free options are PCSS (Fernando 2005,
DOI 10.1145/1187112.1187153), which estimates the penumbra from a blocker search,
or a fixed multi-ray pattern with a deterministic kernel. LTC
(Heitz et al. 2016, DOI 10.1145/2897824.2925895) solves the area-light shading
integral analytically but says nothing about visibility; it is a shading term,
not a shadow term.

This is a future decision, not a defect.

### 4.14 Process: the evidence has gaps

The existing evidence is strong on the first bounce, lightmap noise, seams,
leaks, and perf. It does not answer:

- Probe noise and probe decode error. The noise evidence is lightmap-only.
- Static/dynamic contact: a crate on a static floor, comparing the crate's probe
  term with the floor's lightmap term.
- Dynamic occluders: crate present vs removed, measuring the wall/floor indirect.
- A thin-wall probe leak at 0.1–0.2 m. The sealed-cell test uses the arena's
  0.5 m walls; production probe leaks show at thinner geometry.
- A long coplanar wall seam. One chart per face means two wall boxes that share
  an edge get two charts; the current seam test covers stairs and a floor-wall
  junction, not a long coplanar run.
- Colour bleed: a saturated box beside a white wall, checking the corner hue.
- Multi-bounce: one-bounce vs two/three-bounce or a radiosity reference.
- 4K and a weaker GPU: the 1.50–1.52 ms GPU-total figure is 1080p on an RX 9060 XT.
- A non-ray-query device: there is no fallback to test.
- The perf conflict: ADR 0040 records 4.29 ms for the 96-light shadow term and a
  5.94 ms frame; `docs/evidence/mixed-lighting.md` records 1.50–1.52 ms GPU total
  (1.83–1.85 ms frame interval) at 96 lights. The scenarios and dates differ, but a reader cannot
  tell which number is current from the ADRs alone.

Add one scenario per gap before the next lighting decision. The harness is part
of the feature (`AGENTS.md`), and these are cheap captures compared with the
cost of guessing.

### 4.15 Nits

- `LIGHTMAP_ATLAS_SIZE = 1024.0` in `src/renderer/shaders/terms.glsl:27` is a
  compile-time constant, while the artifact header carries `atlas_size`. The
  `lightmap_grid` view would mislabel a non-1024 atlas.
- The probe grid is hard-coded to the arena: `PROBE_MIN`, `PROBE_COUNTS`,
  `PROBE_MIN_FALLBACK`, and `PROBE_COUNTS_FALLBACK`
  (`src/bake/bake.odin:135`). A larger arena needs a code change, not a quality
  setting.
- `publish_bake` calls `vk.DeviceWaitIdle` (`src/renderer/bake_publish.odin:49`).
  Fine for an explicit publish; it would stall a frame if a future in-game bake
  publishes during play.
- The bake report counts valid/invalid/dilated texels but not visible/hidden
  charts, so 4.8 cannot be sized from the current report.
- There is no maximum chart size or face subdivision. A very large face can
  dominate the atlas and force `Atlas_Full` even when the total surface area
  fits.
- The lightmap has no mip chain; minification is left to TAA. The impact is not
  measured. On a 25 cm texel and a 1080p view, the aliasing may be hidden by the
  flat shading, but a distant wall could shimmer.
- The 256-light cluster cap is first-in-buffer order, and the overflow counter is
  one aggregate, not per cluster (`src/renderer/shaders/cluster.comp`). At 96
  lights this is dormant; at 257+ it can drop a bright light with only a total
  count to show for it.
- The cluster pass runs before the depth prepass, so it uses the full depth slice
  rather than the tile's actual min/max depth. At 1080p a tile is 120 x 120; at
  4K it is 240 x 240. The fixed 16 x 9 grid is tuned for one aspect. This is a
  scale risk, not a current defect.
- The TLAS is built every frame with `PREFER_FAST_TRACE`. At 0.11 ms this is not
  urgent; a stable instance topology could use `MODE_UPDATE` or
  `PREFER_FAST_BUILD` if the box count grows.
- There is no tone map or exposure. Overlapping bright lamps clip to white. The
  flat look tolerates it, but it is a colour-management choice, not a lighting
  fix.

## 5. Comparison to noise-free families

The table compares families, not products. "Dynamic lights" means a moving light
changes the indirect term; "dynamic objects" means a moving object changes the
transport (occludes or emits), not merely receives it.

| Family | Noise | Dynamic lights | Dynamic objects | Bounce | Runtime cost | Main bias | Shipped analogue |
| -- | -- | -- | -- | -- | -- | -- | -- |
| Baked radiosity / lightmap | None | No | No | Multi | ~0 | Texel density, seams, leaks | Quake/Source, id Tech, Unity Baked, Unreal Static |
| Baked indirect + real-time direct | None | Direct only | No (probes receive) | Baked 1+ | Direct shading | Static/dynamic mismatch, stale bake | Unreal Stationary, Unity Mixed, **this project** |
| Lightmap + SH probe volume | None | No | No (probes receive) | Baked | Cheap | Probe spacing, leaks | Unreal Volumetric Lightmap, Unity APV |
| Precomputed radiosity + runtime update | None | Yes (low frequency) | Receives; limited occlusion | Multi | CPU/GPU update | Update rate, low-res lightmaps | Enlighten |
| Light propagation volumes | None (deterministic propagation) | Yes | Yes | 1+ | A few ms | Light bleeding, anisotropy | CryEngine 3 |
| Reflective shadow maps / VPL | Stochastic | Yes | Yes | 1 | High | Noise, sample count | Research, some engines |
| SSDO / SSGI | Stochastic or patterned | Yes | Yes | 1 | Cheap | Off-screen, thickness | Many games |
| DDGI (ray-traced irradiance fields) | Stochastic + temporal | Yes | Yes | Multi | High | Noise, leaks, RT hardware | NVIDIA RTX GI |
| Voxel cone tracing | Stochastic | Yes | Yes | Multi | High | Noise, voxel leaks | Research |
| SDFGI | Temporal | Yes | No dynamic occluders | Multi | High | Convergence, SDF memory | Godot 4 |
| Radiance cascades | None | Yes | Yes (3D split) | Multi | High | SDF memory, complexity | Research, 2D/3D prototypes |
| PRT | None | Low-frequency lighting | Static object | Multi | Cheap | Static transfer, SH ringing | Research, some games |
| Shadow maps + PCF/PCSS | None | Yes | Yes | n/a | Cheap | Bias, aliasing, cube seams | Most engines |
| Hard ray-query shadows | None | Yes | Yes | n/a | Per-pixel rays | Hard edge, RT hardware | **this project** |
| LTC area lights | None | Yes | Yes | n/a | Cheap | No visibility | Unity/Unreal area lights |

The row that matters: **this project is the second row, with a probe volume for
movable receivers.** It is not a weird design; it is a known design with known
tradeoffs. The comparison should be against the same row plus the mitigations
that fit the rule: a contact AO term and a higher-quality probe representation.
Dynamic GI for movable lights is out of scope.

## 6. Alternative architectures

Sections C and D are out of scope under the static/direct rule. They are kept as
the research record for the case where the rule changes to let movable lamps
bounce.

### A. Refine the current hybrid

Keep the split. Fix the probe decode and the emissive mask. Move the probes to
SH9 plus a coarse moment map. Add two or three iterative bounces to the
lightmap. Add GTAO for crate contact.

This is the lowest-risk path and preserves the look, the artifact contract, and
the evidence. It does not give movable lamps a bounce, which is the rule.

### B. Deterministic radiosity bake

Replace the one-bounce Monte Carlo gather with a face-level radiosity solve:
patches are box faces (or a coarse subdivision), form factors are computed
deterministically, the system is solved to convergence, and the result is
interpolated to the lightmap and probe grid.

What it fixes: multi-bounce, no denoise, no per-texel random rotation, a natural
static-fixture direct term, and a physically consistent energy budget. What it
costs: a form-factor solver, visibility between patches, and a patch/texel
mapping. For a box arena with a few hundred faces, this is tractable. It is the
classic method (Goral et al. 1984) and the one Source/id Tech/Enlighten all
descend from.

This is the best long-term fit for a static box scene, and it is not ray tracing
in the path-tracing sense; the form factors can be computed analytically or by
rasterization. If the intent is to remove ray tracing from the bake entirely, a
hemicube/hemisphere rasterization gives the same form factors without a ray
query.

### C. Enlighten-style precomputed radiosity with runtime update

Precompute the visibility and form factors between clusters; at runtime, sum the
cluster colours for the current lights and write a low-resolution indirect
lightmap and probe set. Enlighten reports 10–15 updates per second on the CPU,
asynchronously, with low-resolution lightmaps and SH probes
(Unity Enlighten guide; Geomerics/ARM).

What it fixes: dynamic lamps bounce, without a rebake and without noise. What it
costs: a precompute pipeline, a runtime solver, and a low-resolution indirect
term. Enlighten updates the indirect at 10–15 Hz on the CPU, asynchronously, and
keeps the lightmaps low-resolution because indirect is low-frequency (ARM /
Geomerics, "Enlighten: Real-Time Global Illumination in Unreal Engine 4"). For this
project, the precompute is exactly the kind of work the bake already does; the
missing piece is the runtime update and the cluster/form-factor representation.

This is the strongest answer only if the rule changes to let movable lamps
bounce. Under the current rule, it is out of scope.

### D. Light propagation volumes

A coarse 3D lattice of SH radiance, seeded by the current lights and occluders,
propagated iteratively. No precomputation, dynamic lights and geometry, a few
milliseconds. CryEngine 3 shipped it (Kaplanyan & Dachsbacher 2010,
DOI 10.1145/1730804.1730821).

What it fixes: both dynamic lamps and dynamic occluders. What it costs: light
bleeding, anisotropy, and a grid that has to be tuned to the arena. It is a
plausible middle tier: keep the baked lightmap for static surfaces, use LPV only
for the dynamic-lamp contribution and the dynamic-object occlusion. The risk is
that the two terms disagree at the seam; the bake's probe field and the LPV
would need a blend rule.

A concrete version for this arena: a 0.5 m grid (80 x 10 x 80 = 64k cells, four
SH coefficients per cell, about 1.5 MB) with six axial propagation directions
and eight fixed iterations; inject a movable lamp through a 128² or 256² cube
map of albedo, normal, and flux, and a moving crate through its exact box
surface samples. Mask the static-fixture-to-static-surface and
static-emissive-to-static-surface paths because the bake already contains them.
The estimated cost is 1–2 ms at 0.5 m and 2–4 ms at 0.25 m; these are estimates,
not measurements. Under the current rule, movable lamps are direct-only, so this
is out of scope.

This project already had a dynamic DDGI field and removed it because it leaked
through thin walls and needed a per-frame probe pass (ADR 0042, ADR 0045). Any
dynamic tier must beat that outcome, not repeat it.

### E. Probe-only (APV-style) with SH9 and dynamic AO

Drop the lightmap, use a dense SH probe volume for both static and dynamic
surfaces, and add GTAO for contact. This is simpler in one dimension (one
representation) and worse in another (surface detail is limited by probe
spacing). Unity's APV uses bricks and per-pixel SH; it is a mature version of
this idea. For a 25 cm lightmap on a flat box, the lightmap is the better static
representation; probe-only is a downgrade for static surfaces.

Not recommended as a replacement. Recommended as the representation for dynamic
objects, which is already the case.

### F. Fully baked

Bake direct + indirect for everything static, keep dynamic objects on probes, and
use shadow maps only for dynamic lamps. This is the highest static quality and
the lowest runtime cost. It gives up the "direct light follows every object"
property that ADR 0037 wanted, but only for static fixtures that never move.

This is a legitimate end state if the game becomes more authored and less
sandbox. It is not the right first move for a game about moving lamps and crates.

## 7. Recommended path

Ordered by value per unit of risk:

0. Do not add a dynamic-GI system just because the player can move a lamp. The
   production evidence says a static arena does not need one; the player-facing
   gap is the missing bake workflow. Fix the workflow before adding LPV or
   Enlighten.
1. Fix the probe decode (4.1) and the emissive mask (4.5). These are defects, not
   design changes. Add the paired captures that prove the fix.
2. Add the missing evidence in 4.14, especially probe noise, movable-object
   contact, thin-wall leak, coplanar seam, and colour bleed. Do not choose a
   representation before these numbers exist.
3. Change the probe storage (4.6). Drop the unused alpha and use `R11G11B10F`
   first; that is free. Then test SH9 on a thin-wall/back-lobe A/B. If leaks
   dominate, spend the savings on a 16 x 16 moment map.
4. Measure the corner residual against a two-bounce build (4.7). If it reads, add
   a second bounce with the iterative gather or a patch-level radiosity solve; if
   it does not, keep one bounce and document the choice.
5. Add GTAO for movable-object contact (4.3). Keep it as a multiplier on the
   indirect term, not as a new light.
6. Fix the stale-transform slot key (4.10).
7. Only then consider the atlas packing, a second page or a 4-byte format, and a
   non-ray-query shadow fallback.

What not to do:

- Do not add a path-traced or ray-traced GI pass with a denoiser. It contradicts
  the request and duplicates the bake's job at a worse quality per millisecond.
- Do not add a constant ambient fill to hide the dynamic-lamp gap. It would undo
  the absolute-darkness rule, which is the strongest part of the look.
- Do not "fix" the hard shadows with a noisy soft-shadow pass. If soft shadows
  are wanted, use PCSS or a deterministic multi-ray kernel.

## 8. How these systems are built: the short version

A lighting system is a chain of four decisions, and every shipped engine is a
point in that space:

1. **What moves?** If neither the light nor the receiver moves, bake it. If the
   light moves but the receiver does not, bake the transport and update the
   light (Enlighten) or accept direct-only (Unreal Movable). If the receiver
   moves, it needs a volume representation (irradiance volume, SH probes) or a
   screen-space/dynamic method.
2. **What frequency?** Diffuse transport is low-frequency; nine SH coefficients
   are enough for irradiance (Ramamoorthi & Hanrahan 2001). Specular and sharp
   shadows are high-frequency and need a different representation.
3. **What visibility?** A lightmap carries visibility per texel; a probe carries
   it per direction; a shadow map carries it per light; a ray query carries it
   per pixel. The choice determines the leak, bias, and cost profile.
4. **What budget?** Bake time, runtime ms, memory, and platform features. The
   same look can be built with a 5 s bake and 14 MB, or a 1-day bake and a
   different memory bill. The right answer depends on how often the scene
   changes and who is waiting.

The static/dynamic matrix makes the trade explicit:

```text
                     receiver static              receiver dynamic
light static         bake both                    bake transport, probe receiver
light dynamic        bake transport, update       dynamic method (LPV, Enlighten,
                     at runtime (Enlighten)       DDGI) or direct-only
```

The project is in the top-left and top-right cells: static light is baked into
the lightmap and the probe field; movable light is direct-only. The bottom-left
cell is Enlighten's job. The bottom-right cell is out of scope by the rule. The
project does not have it, and does not need it.

The project's answers are coherent: static transport, low-frequency diffuse,
texel/probe visibility, a 5 s bake, 14 MB, 1.50–1.52 ms GPU total at 1080p. The
critique is about implementation details, not the split.

## 9. Evidence and open questions

Answered by this review: the architecture, the code-level defects, the bias
profile, and the alternative families.

Not answered, and deliberately not guessed:

- The exact probe-decode error on the current scenes. The math predicts it; a
  capture should measure it.
- The static/movable contact step. No scenario exists.
- The movable-object contact error. No scenario exists.
- The multi-bounce residual. No reference bake exists.
- The 4K and weaker-GPU numbers. The current evidence is 1080p on one GPU.
- The cost of a non-ray-query fallback. It is not implemented.

These are the next captures, not reasons to stop.

## 10. Conflicts and corrections

These are the places where the sources disagree, or where this review had to
change its first reading. They are findings, not footnotes.

- **The probe blend may be intentional.** The first reading called the
  sqrt-space average a bug. DDGI-Production uses the same gamma-5 storage and
  the same `pow(encoded, 2.5)` decode to leave a gamma-2 curve for perceptual
  convergence and firefly reduction. The arithmetic is the same; the intent is
  different. A static bake has no temporal firefly problem, so the reason does
  not transfer, but the look may have been tuned around it. The capture decides.
  If it is intentional, the finding should say "test the contact darkening", not
  "fix the math".
- **The brief misattributed two 2004 papers.** "An Irradiance Atlas for Global
  Illumination in Complex Production Scenes" is Christensen and Batali;
  "An Approximate Global Illumination System for Computer Generated Films" is
  Tabellion and Lamorlette. This review cites the correct pairing.
- **The 96-light shadow cost is contradictory across the docs.** ADR 0040
  records 4.29 ms for the shadow term and 5.94 ms for the frame;
  `docs/evidence/mixed-lighting.md` records 1.50–1.52 ms GPU total (1.83–1.85 ms
  frame interval) at 96 lights. The scenarios and dates differ, but a reader
  cannot tell which is current from the ADRs alone. The current baseline is
  1.50–1.52 ms GPU total; ADR 0040 should say what its 4.29 ms measured.
- **SH9 is not an unconditional upgrade.** It is smaller and linear, but it has
  a 1/16 spurious back lobe. The 8 x 8 octa map is local, so a lamp behind a
  wall does not contribute to directions that cannot see it. In a high-contrast
  box arena, that local support is a real advantage. Test before switching.
- **8 x 8 octa is not overkill in angular resolution.** DDGI uses the same 8 x 8
  map and finds probe count matters more than angular resolution. The waste is
  the RGBA16F format with an unused alpha, not the 64 directions.
- **One bounce is a look decision, not a proven defect.** Production bakers
  spend more bounces; the flat-box look may hide the difference. Measure the
  corner residual before paying for a second bounce. The production case studies
  argue for keeping one bounce unless a specific corner reads wrong.
- **"Third order SH" means 9 coefficients, not 27.** Unreal, Unity, and Sloan
  use "third order" / "L2" for the 3-band, 9-coefficient basis. Oat's slides use
  "3rd order" for 9 coefficients per channel (27 floats for RGB). Do not compare
  the 8 x 8 map's 64 texels with 9 coefficients as if they were the same unit.
- **DDGI does not mathematically require temporal accumulation.** With fixed
  rays and a fixed scene, the update is deterministic. The 2019 paper uses 64
  rays per probe per frame plus hysteresis as a budget choice, not as a
  requirement of ray tracing. This is why "DDGI is noisy" is a statement about
  the shipping configuration, not the algorithm.

## 11. References

Primary sources for the claims above. Repository files are cited inline.

- Goral, Torrance, Greenberg, Battaile. "Modeling the Interaction of Light
  Between Diffuse Surfaces." SIGGRAPH 1984. DOI 10.1145/800031.808601.
  https://dl.acm.org/doi/10.1145/800031.808601
- Greger, Shirley, Hubbard, Greenberg. "The Irradiance Volume." IEEE Computer
  Graphics and Applications 18(2), 1998. DOI 10.1109/38.656788.
  https://dl.acm.org/doi/10.1109/38.656788
- Ramamoorthi, Hanrahan. "An Efficient Representation for Irradiance Environment
  Maps." SIGGRAPH 2001. DOI 10.1145/383259.383317.
  https://graphics.stanford.edu/papers/envmap
- Sloan, Kautz, Snyder. "Precomputed Radiance Transfer for Real-Time Rendering
  in Dynamic, Low-Frequency Lighting Environments." SIGGRAPH 2002.
  DOI 10.1145/566654.566612. https://dl.acm.org/doi/10.1145/566654.566612
- Dachsbacher, Stamminger. "Reflective Shadow Maps." I3D 2005.
  DOI 10.1145/1053427.1053460. https://dl.acm.org/doi/10.1145/1053427.1053460
- Ritschel, Grosch, Seidel. "Approximating Dynamic Global Illumination in Image
  Space." I3D 2009. DOI 10.1145/1507149.1507161.
  https://dl.acm.org/doi/10.1145/1507149.1507161
- Kaplanyan, Dachsbacher. "Cascaded Light Propagation Volumes for Real-Time
  Indirect Illumination." I3D 2010. DOI 10.1145/1730804.1730821.
  https://dl.acm.org/doi/10.1145/1730804.1730821
- Majercik, Guertin, Nowrouzezahrai, McGuire. "Dynamic Diffuse Global
  Illumination with Ray-Traced Irradiance Fields." JCGT 8(2), 2019.
  https://jcgt.org/published/0008/02/01
- Heitz, Dupuy, Hill, Neubelt. "Real-Time Polygonal-Light Shading with Linearly
  Transformed Cosines." SIGGRAPH 2016. DOI 10.1145/2897824.2925895.
  https://eheitzresearch.wordpress.com/415-2
- Fernando. "Percentage-Closer Soft Shadows." SIGGRAPH 2005 Sketches.
  DOI 10.1145/1187112.1187153.
  https://dl.acm.org/doi/10.1145/1187112.1187153
- Christensen, Batali. "An Irradiance Atlas for Global Illumination in Complex
  Production Scenes." EGSR 2004.
  https://research.pixar.com/docs/2004.Others.CB.pdf
- Tabellion, Lamorlette. "An Approximate Global Illumination System for Computer
  Generated Films." SIGGRAPH 2004.
  https://www.tabellion.org/et/paper/siggraph_2004_gi_for_films.pdf
- id Software. "Lightmaps." idStudio: DOOM Eternal.
  https://idstudio.idsoftware.com/lighting-and-rendering/lightmaps
- Epic Games. "Volumetric Lightmaps." Unreal Engine documentation.
  https://dev.epicgames.com/documentation/unreal-engine/volumetric-lightmaps-in-unreal-engine
- Unity. "Introduction to Adaptive Probe Volumes."
  https://docs.unity.com/en-us/engine/6000.6/manual/lighting-overview/lighting/probevolumes/concept
- Unity. "Using Enlighten with Unity."
  https://docs.unity3d.com/kr/2019.4/uploads/ExpertGuides/Using_Enlighten_with_Unity.pdf
- Geomerics/ARM. "Enlighten: Real-Time Global Illumination in Unreal Engine 4."
  2016. https://www.unrealengine.com/en-US/blog/enlighten-real-time-global-illumination-in-unreal-engine-4
- Godot. "Signed distance field global illumination (SDFGI)."
  https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_sdfgi.html
- Osborne, Sannikov. "Radiance Cascades: A Novel High-Resolution Formal Solution
  for Multidimensional Non-LTE Radiative Transfer." RAS Techniques and
  Instruments 4, 2025. DOI 10.1093/rasti/rzae062.
  https://arxiv.org/abs/2408.14425
- Freeman, Sannikov, Pitt-Francis. "Split Radiance Cascades: Real-Time Global
  Illumination via Sparse Radiance Probes." arXiv 2607.20384, 2026.
  https://arxiv.org/abs/2607.20384
- Valve. "Half-Life 2 / Valve Source Shading" (radiosity normal mapping).
  GDC 2004. https://cdn.fastly.steamstatic.com/apps/valve/2004/GDC2004_Half-Life2_Shading.pdf
