# DDGI irradiance update and gather

Supersedes the update and gather details in
[ADR 0031](0031-ddgi-probe-volumes.md). The probe volume, relocation, and the
pass order stay.

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
- The ray stores a negative hit distance on a backface. The blend ignores that
  ray's radiance and skips a probe when more than a quarter of its rays hit
  backfaces. The depth blend uses the absolute distance.
- Hysteresis stays at `0.75`. A light or sun hash change, a volume change, or a
  texel delta above `0.25` replaces the texel instead of blending it.
- The probe volume stays the room, its lanes, and the chamber. The CPU still
  relocates a probe out of a box before the rays run.

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
- Coverage, classification, and a sealed leak pair remain out of scope. They are
  issues #321 and #322.
- A path-traced reference for one room and one corridor needs a separate scene
  and tolerance design. It is not part of this change.
