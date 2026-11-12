# Compact probe irradiance and the chosen directional basis

Probe irradiance uses `R11G11B10F` without an alpha channel. The default
directional basis stays an 8 x 8 octahedral map, and the default depth block
stays 8 x 8 first/second moments. SH9 irradiance and 16 x 16 moments remain
selectable bake options for later A/B work.

## Why

- The old `RGBA16F` octa map spent four bytes per texel on three channels and
  wrote a constant one into alpha. `R11G11B10F` halves the irradiance bytes with
  no sampling algorithm change. The default-arena artifact falls from about
  14.6 MB to 12.6 MB.
- SH9 is smaller than the octa map and removes the gamma decode, but its
  nine-coefficient clamped-cosine reconstruction has a known 1/16 back lobe.
  A bright emitter behind a dynamic crate raised the away-side probe term by
  13.6% green in the A/B, and SH9 did not reduce the thin-wall case. That is a
  quality regression, not a win.
- A 16 x 16 depth block matches DDGI's depth resolution, but it changed no image
  beyond one 8-bit step in either A/B scene and raised the artifact to about
  18.7 MB. The extra precision did not buy a visible result.
- Gamma-2 versus linear reconstruction differed by at most one 8-bit step in
  the same-frame capture, so the existing gamma-5 storage and gamma-2 blend are
  kept.

## Decisions

- **Irradiance format.** The octa map is `VK_FORMAT_B10G11R11_UFLOAT_PACK32`.
  Channels are packed red in the low 11 bits, green in the next 11, and blue in
  the high 10. The shader still stores `(radiance/2)^(1/5)` and decodes with
  `pow(encoded, 2.5)`, so the default image matches the old one within one
  8-bit step.
- **Basis option.** `Quality.probe_basis` is `octa` or `sh9`. SH9 stores 27
  signed `R16F` values per probe (nine coefficients x three channels) in a
  27 x probe-count image, projected with the clamped-cosine band factors and a
  Lanczos window. There is no padding channel. The default is `octa`.
- **Depth option.** `Quality.probe_moment_texels` is 8 or 16. The moment atlas
  derives its own shelf extents from the tile size, so either resolution can
  pair with either basis. The default is 8.
- **Gamma-2 versus linear.** The default sampler weights the gamma-2 values and
  squares after the weights. The `probe_linear` diagnostic view decodes each
  octa tap with `2 * pow(encoded, 5)` before weighting. One capture writes both
  from the same frame. The default stays gamma-2.
- **Artifact.** The format version is 2. The header carries the basis and the
  moment resolution in addition to the octa texel size and atlas columns. The
  loader validates the derived irradiance and moment extents before it creates
  resources.
- **Static/direct rule.** This decision does not change the split: static boxes
  read the lightmap, dynamic boxes read the probe field, and dynamic lamps stay
  direct-only.

## Considered options

- **Make SH9 the default.** Rejected by the bright-emitter capture. The memory
  win is real, but the false back lobe is the failure the ticket asked the A/B
  to find.
- **Make 16 x 16 moments the default.** Rejected. It doubles the moment bytes
  for no visible change at 1 m probe spacing.
- **Keep `RGBA16F`.** Rejected. The alpha channel is unused and the packed
  unsigned format is enough for non-negative octa irradiance.
- **Use `RGB9E5`.** Not needed. `R11G11B10F` has a per-channel exponent and does
  not suffer the shared-exponent clamp. The A/B scenes show no visible green
  tint, but they use a warm lamp; a dedicated neutral-gray capture is a
  follow-up.
- **Store SH9 with an unsigned packed format.** Impossible, because SH
  coefficients are signed.

## Consequences

- The default artifact is about 12.6 MB for the default arena, SH9 8 x 8 is
  about 10.9 MB, and the worst A/B option is about 18.7 MB. All are under the
  32 MiB budget.
- The bake remains deterministic: the same input and quality produce
  byte-identical artifacts at one and sixteen threads.
- Existing version-1 artifacts are rejected and must be rebuilt.
- The `probe_linear` view and the `probe_basis` / `probe_moments` bake options
  are documented in `docs/agents/harness.md`. The measurements are in
  `docs/evidence/probe-format.md`.
