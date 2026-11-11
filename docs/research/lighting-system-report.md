# Lighting system report, revised

Date: 2026-11-11.

The design rule is: static objects are baked and immovable; every other object is
movable and direct-only. This report treats that rule as fixed. It critiques how
well the implementation delivers the rule, not whether the rule should change.

Path tracing and ray-traced GI are excluded. The existing offline bake and the
hard ray-query shadows are the baseline. "Lighting" is what this covers; the
repository has no lightning or weather system.

## Verdict

The architecture is correct for the rule. It is a conventional static-baked /
dynamic-direct system: Frostbite Battlefield 3, Unity Baked Indirect, and Unreal
Stationary all use the same split. The runtime is fast, the bake is deterministic,
and the bake states are explicit.

The remaining issues are implementation details: probe reconstruction, probe
storage, atlas padding, one-bounce measurement, and a few correctness traps. None
of them require a new lighting system, dynamic GI, or a change to the static /
direct rule.

## The rule

- A static object is baked and immovable. Its indirect light comes from the bake.
- A static fixture is a static object. Its indirect is baked. Its direct light is
  still real-time, because the direct path is always real-time.
- Every other object is movable and direct-only. A movable lamp is direct-only by
  definition. A movable crate receives direct light and the static probe field,
  but it does not contribute indirect.
- There is no ambient fill. A surface no lamp reaches, and no baked bounce
  reaches, is black.
- A static edit needs a rebake. A movable edit does not.

This is the design. The report does not propose changing it.

## What works

The bake is deterministic. The seed follows the surface, the result does not
depend on thread count, and three runs wrote identical bytes. It is not noise-free
in the estimator sense: the 128-ray gather still has spatial variance, and the
3 x 3 filter hides most of it. Determinism is what makes the stale key meaningful;
the filter is what makes the image usable.

The bake states are explicit. A missing or failed artifact binds placeholders and
reports the state. It does not quietly turn into black or into an old bake. Most
engines do not expose a stale key at all; this one does.

The term views and the render digest make a lighting question answerable with a
capture. `direct`, `lightmap`, `probe`, `emissive`, `shadow`, `lightmap_grid`, and
`probe_cell` are the right set.

The look is coherent. Absolute darkness, hard shadows, flat boxes, and one texture
are decisions, not accidents. The lightmap stores one RGB value per texel, which
is the right amount for a face with one normal. Source's Radiosity Normal Mapping
triples memory to support normal maps; this scene has no normal maps, so adding
RNM would be waste.

The density is reasonable. 25 cm per texel matches Frostbite's Battlefront II
target. The 1 m probes are denser than The Division's 4 m grid. The architecture
is not the risk.

## What to improve

### The probe decode may be a look, not a bug

`probe.glsl:242` accumulates `pow(encoded, 2.5)`, which is `sqrt(radiance / 2)`.
Line 248 squares the weighted average and multiplies by two. That is an average in
square-root space, not a linear average of radiance.

For two equally weighted probes with values L and 0, the result is L/4. The linear
average is L/2. The effect is strongest at a lit/unlit boundary: contact, corners,
and the edge of a lamp's reach.

This may be deliberate. DDGI uses the same gamma-5 storage and the same decode to
leave a gamma-2 curve for perceptual convergence and firefly reduction. A static
bake has no temporal fireflies, so the reason does not transfer, but the look may
have been tuned around it. The comment calls the encoding "legacy", which suggests
the order was not re-examined when the field became static.

Capture it both ways. If the intent is linear irradiance, store linear radiance or
decode each tap before weighting. If the gamma-2 blend is the intended look,
document it and test whether the darkening at contact is acceptable. The capture
decides.

### The probe format is the waste, not the 8 x 8 map

The 8 x 8 angular resolution is fine. DDGI uses the same 8 x 8 irradiance map, and
its own study finds probe count matters more than angular resolution.

The waste is RGBA16F with a fourth channel that is always 1.0. That is 512 bytes
per probe; an 8 x 8 R11G11B10F map is 256 bytes. Dropping the unused channel is
the cheapest win in the system and changes no image.

SH9 is the stronger simplification, but it is not an unconditional upgrade. A
9-coefficient SH probe at f16 RGB is 54 bytes per probe. With the current 8 x 8
moments and state, total probe memory falls from about 6.2 MB to 2.5 MB, not 10x,
because the moments dominate. SH9 removes the decode, the octahedral seam, and the
nonlinear interpolation. It also has a spurious back lobe of about 1/16 the peak:
a bright emitter behind a thin wall can add false light in the opposite direction,
and a depth test cannot remove a lobe that lives in the reconstruction. The octa
map is local, so a lamp behind a wall does not contribute to directions that
cannot see it. In a high-contrast box arena, that local support is a real
advantage.

Test SH9 against the octa map on the dark side of a bright emitter and at a thin
wall. Window the coefficients if it wins. The bigger leak lever is the depth map:
this field uses 8 x 8 moments where DDGI uses 16 x 16. A thin occluder can fall
between the narrow `cos^50` cones. Spend the irradiance-format savings on a 16 x
16 moment map if leaks are the measured problem.

### The atlas limit is padding

The atlas is one 1024² RGBA16F image, 4 texels/m, shelf-packed, with a 4-texel
gutter and an 8-texel minimum chart. The raw valid-texel count is 165k of 1.05M,
about 16%. That number is misleading.

The 4-texel gutter and 8-texel minimum chart turn a 1 m face into a 16 x 16
allocation for 8 x 8 valid texels, 25% chart efficiency. A 4 m face is 24 x 24 for
16 x 16, 44%. An 8 m face is 40 x 40 for 32 x 32, 64%. The current content already
occupies roughly 35-63% of the atlas.

At the current padding, a 2x linear arena needs about 1.5-2.6M atlas texels and
does not fit. Better packing alone can carry it: a 1-texel gutter is enough for
the bilinear footprint, a 4-texel minimum chart is enough for the 3 x 3 filter, and
a chart-mask packer reaches about 96%. That takes the 2x content to roughly 689k
texels and fits.

A single 2048² RGBA16F atlas is exactly 32 MiB (33.55 MB), the entire budget
before the probes, so it does not fit with them. Two 1024² pages fit. RGBE at
2048² is 16 MiB; BC6H at 8 bpp is 4 MiB if the format is available.

The order is: reduce the gutter and minimum chart, pack better, add a second page
or a 4-byte format, and only then raise the atlas or lower the density.

### One bounce is unmeasured, not proven

The bake traces one diffuse bounce. A texel ray hits a surface, and that hit is
shaded by the static lights and emissive. It does not gather the light that already
bounced onto the hit surface.

The evidence measures the first bounce against no indirect. It does not measure the
residual against a two-bounce reference. In a closed arena, the missing term is
concentrated in corners and under overhangs.

A per-texel second bounce re-traces the full 21.2M rays, about 3.0 s. Two bounces
land near 8 s total and three near 11 s. A patch-level radiosity solve is cheaper
and gives all bounces, but it needs a patch hierarchy, visibility, and a transfer
step. Measure the corner residual before paying. If it is below the look threshold,
keep one bounce and say so.

### One ray is wasted on every back-facing light

`terms.glsl:118` computes `diffuse = max(dot(normal, direction), 0)`. Line 123
traces the shadow ray without testing `diffuse`. A light behind a box face
contributes zero, but the ray is still cast.

Gating the ray on `diffuse > 0` and `falloff > 0` is image-identical and roughly
halves the shadow rays on box faces. This is the first optimization to take. It
does not change the look and it does not need a new architecture.

### The shadow mask uses emission as lamp identity

`emissive > 0` is used as lamp identity in the shadow mask. Any emissive box is
invisible to every shadow ray. A non-lamp emissive prop casts no shadow, a lamp
housing never occludes another lamp, and emission is conflated with opacity. Use an
explicit lamp flag or a per-light self-instance test.

### A stale bake after a static transform is a texture-space error

The bake key hashes the transform, but the runtime slot key is `(source, id)`. The
old artifact still has a chart for that key, so the box samples the old lightmap
in its new position. The UV is local, so the old lighting travels with the box.
Invalidate the slot on a transform change, store the transform in the slot key, or
rebake the moved charts incrementally. Add a moved static box to the stale-state
scenario.

### Scale notes

The 256-light cluster cap is first-in-buffer order, and the overflow counter is one
aggregate, not per cluster. At 96 lights this is dormant. At 257+ it can drop a
bright light with only a total count to show for it.

The cluster pass runs before the depth prepass and uses a fixed 16 x 9 grid. At
1080p a tile is 120 x 120; at 4K it is 240 x 240. The grid is tuned for one aspect.
This is a scale risk, not a current defect.

There is no tone map or exposure. Overlapping bright lamps clip to white. The flat
look tolerates it, but it is a colour-management choice, not a lighting fix.

## What is correct by rule

### Static fixture direct shadows are a cost, not a defect

A static fixture has a static body, but its direct light and shadow are evaluated
per pixel per frame. That is correct for the rule: direct light is always real-time,
so movable objects can receive it. Baking the static fixture's direct shadow is an
optional cost reduction, not a requirement. If the light count or resolution grows,
measure it then. Do not change the rule for it.

### Movable objects are direct-only by rule

A movable crate receives direct light and the static probe field. It does not
occlude the baked field or contribute to it. That is consistent with the rule. The
only open question is visual: how large is the mismatch at the contact between a
movable crate and a static floor, where a 1 m probe meets a 25 cm lightmap? Add a
capture. If the seam reads, the fix is a contact term or a probe blend, not a
change to the rule.

## How it compares

The project's row is the intended design. The static-baked rows are the alternatives
if the bake is ever replaced. The dynamic-GI rows are out of scope because movable
lights are direct-only by rule.

| Family | Noise | Static indirect | Movable lights | Fit here |
| --- | --- | --- | --- | --- |
| Baked radiosity or lightmap | None | all bounces | no | static alternative |
| Baked indirect + real-time direct | None | baked | direct only | this project |
| Lightmap + SH probes | None | baked | no | static alternative |
| Enlighten | None | precomputed, updated | yes | out of scope by rule |
| LPV | None | dynamic | yes | out of scope by rule |
| SDFGI | temporal | dynamic | yes | out of scope by rule |
| Radiance cascades | None | dynamic | yes | research-grade in 3D |
| Shadow maps or PCSS | None | n/a | direct shadows | portable fallback |
| DDGI, RSM, SSGI, VCT | stochastic | dynamic | yes | excluded |

The bake is a one-bounce Monte Carlo gather with a deterministic seed and a
filter, not a radiosity solve. Radiosity is the true noise-free reference for the
static side, and a patch-level solve would give all bounces without a per-texel
pass. That is a static-bake improvement, not a dynamic-GI feature.

## What the deep dives changed

The first read called the probe blend a bug. DDGI uses the same gamma-2 order on
purpose, so the arithmetic is right but the intent may be a look. Capture decides.

The first read treated 8 x 8 as overkill. It is not overkill in angular resolution;
DDGI uses the same. The format is the waste. R11G11B10 first. SH9 is smaller but
has a back lobe. A 16 x 16 depth map is the better spend if leaks dominate.

The first read treated the 16% valid-texel fraction as packing efficiency. It is
not. The current content already occupies 35-63% because of the gutter and minimum
chart. The atlas limit is padding.

The first read mixed GPU total and frame interval. The current numbers are
1.50-1.52 ms GPU total and 1.83-1.85 ms frame interval. The 4.29 ms shadow term in
ADR 0040 is a historical, differently-scoped measurement.

## What to do, in order

1. Gate the shadow ray on `diffuse > 0` and fix the emissive mask. Both are small
   and image-safe.
2. Capture the probe blend both ways, the movable-crate contact, the thin-wall
   leak, the coplanar wall seam, and the colour bleed. Do not choose a
   representation before these numbers exist.
3. Change the probe format to R11G11B10F. Test SH9 on a thin wall. If leaks
   dominate, spend the savings on a 16 x 16 depth map.
4. Measure the corner residual against a two-bounce build. If it reads, add a
   second bounce with the iterative gather or a patch-level radiosity solve; if it
   does not, keep one bounce and document it.
5. Fix the stale-transform slot key.
6. Only then consider the atlas packing, a second page or a 4-byte format, and a
   non-ray-query shadow fallback.

## What not to do

Do not add dynamic GI. Movable lights are direct-only by rule. LPV, Enlighten,
SDFGI, and DDGI are out of scope.

Do not add a path-traced or ray-traced GI pass with a denoiser. It contradicts the
request and duplicates the bake at a worse quality per millisecond.

Do not add a constant ambient fill. It would undo the absolute-darkness rule.

Do not add a single 2048² RGBA16F atlas. It is the whole 32 MiB budget before
probes.

Do not add SH9 without a thin-wall test. The back lobe is real.

Do not use VSM, ESM, CSM, or PCSS for the whole 96-light loop. VSM and ESM bleed
light, CSM is directional-only, and PCSS is about 100 taps per light. If soft
shadows are requested, treat it as a new design decision for one or two hero lamps.

## Evidence gaps

The project has no probe-noise measurement, no thin-wall capture at 0.1-0.2 m, no
movable-crate contact test, no long coplanar wall seam, no colour-bleed test, no
multi-bounce reference, no 4K or weaker-GPU number, and no non-ray-query fallback.
ADR 0040's 4.29 ms and the current 1.50-1.52 ms GPU total are not reconciled in the
docs.

Add one scenario per gap before the next lighting decision. The harness is part of
the feature, and these are cheap captures compared with guessing.

## Files

`docs/research/lighting-system-review.md` is the long synthesis.

`docs/research/baked-gi-lightmaps.md`, `probe-volumes-and-sh.md`,
`realtime-gi-without-rays.md`, `direct-lighting-and-shadows.md`, and
`production-lighting-case-studies.md` are the source-level deep dives.

No code changed.
