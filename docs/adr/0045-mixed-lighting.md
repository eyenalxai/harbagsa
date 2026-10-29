# Mixed static baked indirect and dynamic direct

The renderer keeps every point light, every hard shadow, and the emissive term
real-time. It bakes only the one-bounce indirect from static fixtures and static
emissive boxes. Static boxes read a lightmap atlas; dynamic boxes read a baked
probe volume. This supersedes the per-frame probe field of ADR 0042 and the
dynamic-only lamp rule of ADR 0039. ADR 0041's no-ambient-floor rule stays.

## Why

- The owner wants a clean flat-box look without dynamic-GI noise, ghost bounce,
  or probe leaks. A per-frame field changes when a crate moves and cannot be
  reviewed as a fixed image.
- Direct light and hard shadows must follow a moving lamp immediately. Baking
  them would either freeze a dynamic object or lose the shadow.
- The arena and most props are static. Their indirect changes only when a static
  box or fixture changes, so it is a build-time product.
- One diffuse bounce is the target look. More bounces add cost and a long tail
  for no visible gain on flat box faces.

## Decisions

- A lamp kind is part of the lamp settings: `Static_Fixture` or `Dynamic_Lamp`.
  The kind follows the body: a static body is a static fixture, a dynamic body
  is a dynamic lamp. The editor's body control switches both together.
- The direct path is unchanged: clustered forward+ over every active light and
  one hard ray-query shadow per light. Static fixtures and dynamic lamps both
  light and shadow in real time.
- A static box owns one lightmap slot and six center-to-center face rects. The
  face index and UV come from the local position and local normal, so there is
  no vertex UV channel.
- A dynamic box samples a tetrahedron of four baked probes. The gather applies
  the stored validity flag, a 0.1 x spacing normal bias, the facing weight, and
  the Chebyshev depth test. The bake stores octahedral irradiance as
  `(radiance / 2)^(1/5)` and halved depth moments; the gather restores radiance.
- The probe grid is 1 m by default and 2 m through the artifact quality block.
  The runtime reads the bounds, spacing, counts, and shelf-atlas layout from the
  artifact. Invalid probes are dilated from valid neighbours within two cells at
  load; a probe with no valid neighbour stays invalid and is skipped.
- The bake key hashes the static boxes, static fixtures, the quality block, and
  the tool version. Dynamic lamps, dynamic crates, the spider, the camera, TAA,
  and the UI never enter it. A key mismatch is `stale`, not an error and not a
  silent fill.
- The bake artifact is one versioned `.hbake` file. `make bake` writes it; the
  harness `bake reload` reads it again without a restart, and `bake publish`
  rebuilds it from the current static input and publishes it atomically. Both
  reset TAA history. A failed publish keeps the old artifact bound and reports
  `failed`.
- A static edit updates direct light immediately and leaves the old indirect
  bound until a publish. Dynamic edits never change the bake.
- The lightmap and probe samplers carry lighting data only. There is still no
  surface or material texture.

## Considered options

- **Keep per-frame DDGI.** Rejected. It changes with dynamic geometry, costs a
  probe pass every frame, and produces the noise and leaks the owner rejected.
- **Bake direct light and shadows too.** Rejected. A dynamic object would lose
  direct light and a moving lamp would not move its shadow.
- **No indirect at all.** Rejected. It returns the flat, uncolored crate and the
  dark corner the mixed model exists to fix.
- **L2 spherical harmonics for probes.** Deferred. It is smaller, but it loses
  the direction-dependent depth test and adds ringing.
- **A runtime rebake on every static edit.** Deferred. The publish path exists;
  an automatic debounce and a worker are a later decision, not a hidden hitch.
- **Ambient fill.** Rejected by ADR 0041.

## Consequences

- A static fixture or static geometry edit marks the bake stale. The direct
  change is visible at once; the old indirect stays until a publish.
- Moving a crate, the spider, or a dynamic lamp never rebuilds the bake and
  never changes the lightmap or probe values.
- A lamp-free scene with a current bake is black. The headless bake still needs
  at least one static box, so the arena shell remains in an empty-light bake.
- The default 1 m bake is about 5 s at 16 threads and 37 s at one thread for the
  default sample counts. The tool reports the measured time; the artifact stores
  zero so identical inputs produce byte-identical files.
