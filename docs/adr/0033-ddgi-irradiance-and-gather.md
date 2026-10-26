# DDGI irradiance update and gather

Supersedes the update and gather details in
[ADR 0031](0031-ddgi-probe-volumes.md). The probe volume and the pass order stay.
[ADR 0036](0036-ddgi-probe-validity-and-contact.md) supersedes the relocation
rule, the backface gate, the gather bias, the zero-texel rule, and the crush.

## Context

The shipped atlas was a radiance map. The update traced one ray per octahedral
texel and stored the radiance that the ray hit. The gather then sampled the
atlas with `oct(world - probe)`, the direction from the probe to the surface.

DDGI stores irradiance, not radiance. The update traces a ray set per probe and
accumulates every ray into every octahedral texel with a cosine kernel. The
gather reads the texel that faces the surface normal. A wall that faces away
from the light otherwise reads its own dark outgoing radiance and stays black.

## Decision

- Add one probe ray buffer per frame. Each ray holds radiance in `.rgb` and the
  hit distance in `.a`. The frame holds 256 rays per probe.
- The ray directions are a fixed spherical Fibonacci set. Both the ray pass and
  the blend pass derive a direction from the ray index, so the buffer stores no
  directions.
- The probe pass records two compute dispatches. The ray pass traces every ray
  and stores its radiance and hit distance. A compute-to-compute barrier
  publishes the buffer.
- The blend pass runs one thread per probe texel. For texel normal `n` and ray
  direction `d`:
  - irradiance is `sum(radiance * max(dot(n, d), 0)) / (2 * sum(max(dot(n, d), 0)))`,
    then encoded with `pow(value, 1 / 5)`;
  - depth is `sum(distance * w) / (2 * sum(w))` for the mean and
    `sum(distance^2 * w) / (2 * sum(w))` for the second moment, with
    `w = pow(max(dot(n, d), 0), 50)`.
- The gather reads irradiance with `oct(surface_normal)` and depth with
  `oct(world - probe)`. It uses bilinear octahedral sampling, the reference wrap
  backface weight `(dot(to_probe, normal) + 1)^2 / 4 + 0.2`, Chebyshev
  visibility, decodes the gamma, multiplies the hemisphere factor `2 * pi`, and
  divides by `pi` for the diffuse BRDF so the term shares the lit pass scale.
- The Chebyshev visibility weight keeps the reference 5 percent floor. The
  sealed pair uses one probe volume per room, so a probe across the shared wall
  is not in the surface cage; the floor is only a fallback inside the room.
- The probe ray multiplies the sun and point-light terms by the hit surface
  albedo. The atlas stores the bounced surface colour, not the light source
  colour.
- The ray stores a negative hit distance on a backface. The blend ignores that
  ray's radiance and skips a probe when more than a quarter of its rays hit
  backfaces. The depth blend uses the absolute distance.
- The gather adds a 1 mm containment epsilon to each volume high bound, so a
  wall face one ULP outside the computed bound still selects its volume.
- Hysteresis stays at `0.75`. A light or sun hash change, a volume change, or a
  texel delta above `0.25` replaces the texel instead of blending it.
- The probe volume stays the room, its lanes, and the chamber. The CPU still
  relocates a probe out of a box before the rays run. Arena and roof coverage are
  in [ADR 0034](0034-ddgi-arena-coverage.md).
- `scenarios/ddgi-reference.json` and `src/reference` are the acceptance
  reference for the field. The scenario captures two `scene_color` float frames
  that differ only in the gather toggle. The **one-bounce** reference gates the
  probe field: 48 paths, an 80 x 45 grid, and the median luminance ratio, error,
  colour spread, and zero-coverage fraction. A **three-bounce** run is marked
  advisory and reports the missing multi-bounce transport.

## Why

- Irradiance is an integral over the hemisphere. A radiance sample answers a
  different question.
- The normal direction is the quantity a surface needs. The probe direction is
  the quantity the depth test needs. Using one direction for both coupled the
  lookups and made a back-facing wall read its own radiance.
- The `1/(2 * sum(cos))` and `2 * pi` pair follows the RTXGI Monte Carlo
  estimator. The `1/pi` factor is this renderer's convention: the sun term is
  `albedo * NdotL`, not `albedo * NdotL / pi`.
- 256 rays give each 8 x 8 texel 256 candidates. A 64-ray set leaves about 16
  samples per texel at the cosine peak and shows more shape in a smooth wall.
  The measured pass cost is 0.232 ms at 64 rays and 0.413 ms at 256 rays with 64
  synthetic lights at 1280 x 720.

## Consequences

- The atlas stores gamma-encoded irradiance. `renderer.probe_energy` decodes the
  gamma before it reports the mean, so it stays a linear diagnostic.
- A probe texel that no ray reaches stays zero and the gather may return zero.
  That is correct for a sealed room with no light; the coverage ticket owns the
  open arena.
- Coverage is in [ADR 0034](0034-ddgi-arena-coverage.md). The sealed pair is
  `scenarios/ddgi-sealed.json`; probe classification is still out of scope.
- The reference is measured. The gather scale above is correct: the reference
  reproduces the renderer's direct term to 0.03 percent, and the one-bounce
  gate passes. The three-bounce advisory is about half the probe field's
  luminance in this scene; that is the documented one-bounce limit. See
  **Reference** below.

## Reference

The estimator, the scene, the sample count, the tolerance, and the numbers are
in [`docs/evidence/ddgi-reference.md`](../evidence/ddgi-reference.md). The
reference reproduces the renderer's direct term to 0.03 percent, so the indirect
gap is the probe field.

The reference found two defects that are fixed here:

- `hit_radiance` in `probe_ray.comp` added the sun and point-light terms without
  the hit surface's albedo. The atlas kept the light source's colour instead of
  the colour of the surface that bounced it. It is now multiplied by
  `object.color.rgb`.
- The room volume's high z bound was `14.1999998` and the north wall's inner face
  was `14.2000008`, one ULP above it. The gather rejected the whole face: 10.9
  percent of the chamber sample points and 35.3 percent of the lane points read
  zero probe indirect while the reference saw light. The 1 mm high-bound margin
  fixes it; current zero-coverage is 0 and 0.0003.

The comparison runs with TAA, jitter, and AO off because the reference has no
temporal filter and no AO term. The scene captures the chamber and the room lane
at 1280 x 720. The estimator is deterministic: a repeat run gives the same
metrics. The target is `make reference`; the one-bounce gate is the run exit code
plus `report.json.failures`. The three-bounce advisory is in
`report.json.references` and is not a failure.
