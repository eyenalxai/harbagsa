# 0017 Output dither for the 8-bit target

## Context

The scene colour is 16-bit and the TAA history is 32-bit. The sky gradient is
continuous there. The resolve writes the 8-bit sRGB target, and that write has
no dither. A gradient that crosses one level every 80 rows becomes a run of
identical rows. The AO gradient on a wall has the same defect.

The sky capture at 1280x720 had a longest identical run of 253 rows. A
contrast-stretched crop showed five hard bands. The history was not the cause:
TAA on and off differed in 23 pixels by one level.

## Decision

Dither at the resolve, after the history is updated. The resolve encodes the
linear colour to sRGB, adds a per-pixel offset of 1.5 levels peak-to-peak,
clamps, and decodes back to linear for the sRGB attachment. The hardware applies
the sRGB transfer and quantizes to the offset value. A linear (non-sRGB)
fallback target writes the encoded value directly.

The dither pattern is a hash of the pixel coordinate, not of the frame. It is
stable across frames, so a static scene keeps the same quantization and the TAA
static gate does not shimmer. The history and the scene colour never see the
noise.

The exact sRGB transfer is used for both directions. The old `pow(1/2.2)`
approximation would make the dither magnitude view-dependent.

## Options considered

- **10-bit target.** Four times the levels and no noise. It changes the offscreen
  format, the swapchain negotiation, every pipeline format, and every capture
  format. It is the right long-term target for an HDR pipeline, not for this fix.
- **Pre-compensate in linear space.** Add noise after a `pow(1/2.2)` encode and
  convert back. Smallest diff, but the approximation shifts the effective
  magnitude.
- **Steepen the sky mapping near the zenith.** Hides the worst sky bands and
  leaves the AO gradient banded. It treats one gradient, not the class.
- **No dither.** The status quo. A 16-bit pipeline that quantizes without a
  dither is the bug.

## Consequences

- A 1280x720 sky capture now has a longest identical run of 27 rows and a median
  of 1. The level count barely moves, because the dither splits a plateau into
  two adjacent levels.
- The noise is one to two levels on a smooth gradient. It is invisible at normal
  viewing distance and absent from the HUD, which draws after the resolve.
- The dither pattern is deterministic. Two runs of the same scenario produce the
  same PNG.
- `analysis.bands` gates the class. `scenarios/banding.json` checks the longest
  run and the median at 1280x720.
- The 8-bit sRGB swapchain stays. The game still presents 8 bits per channel.
- This dither handles the 8-bit write only. A ray-count step is larger and is
  offset in the lit pass per `docs/adr/0024-visibility-count-dither.md`.
