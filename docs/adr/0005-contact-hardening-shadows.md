# Contact-hardening shadows with PCSS

The sun shadow uses percentage-closer soft shadows. The shadow map is 4096 over
the fixed 60 m light volume. The lit pass runs a blocker search with a rotated
Vogel disk, estimates the penumbra from the receiver-to-blocker depth difference
and the sun angular diameter, then filters with a variable-radius PCF. The
compare sampler uses hardware linear filtering; a second sampler binds the same
depth image as raw depth for the blocker search. Contact shadows stay hard and
distant shadows soften.

## Why

- The old fixed 3x3 PCF gave every penumbra the same width, about 9 cm, and its
  nearest-filtered texel grid left stair-steps on the edges.
- A directional light with a finite angular size has a penumbra that grows with
  the blocker distance. PCSS computes that radius from the shadow map and needs
  no second light pass.
- Global illumination is not involved. GI adds indirect light. The penumbra is a
  direct-light visibility effect.
- The real sun is about 0.53 degrees. At arena scale that gives a sub-texel
  penumbra. The demo uses 3 degrees so the near-hard and far-soft cue is visible.

## Considered Options

- **Larger fixed PCF**: removes some stair-steps but keeps one penumbra width and
  increases noise.
- **Cascaded shadow maps**: raise near texel density, but the arena is one fixed
  40 m room and the 4096 map already gives about 1.5 cm texels. Cascades add
  passes and seams for no visible gain here.
- **Variance shadow maps or ESM**: give a blur but no contact hardening and add
  light bleeding.
- **Ray-traced or screen-space shadows**: better contact detail but a larger
  pipeline and a different fallback surface. Not worth it for one sun and a box
  arena.

## Consequences

- The shadow map is 4096x4096 D32, two frames in flight, about 134 MB.
- The scene descriptor set has two samplers for the same depth image: a linear
  compare sampler and a nearest raw-depth sampler.
- `camera.shadow_params.x` carries the penumbra UV radius per unit of normalized
  depth. The shader must not divide by the blocker depth; that term only applies
  to a perspective light.
- The sun angular diameter is an art constant. Raising it softens every shadow;
  lowering it sharpens them.
- The lit pass costs 24 blocker samples and 32 PCF samples per pixel. TAA hides
  the residual sampling noise.
- A moving crate can leave a short TAA shadow trail because the floor receiver
  has no motion. The existing velocity buffer covers the crate, not the floor
  under it.
