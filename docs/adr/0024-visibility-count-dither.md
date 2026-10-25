# 0024 Dither a partial visibility count

## Context

The lit shader traces 16 sun rays and 8 ambient-occlusion rays. The visible
fraction is a count over the sample count, so the sun term steps by 1/16 and the
ambient term by 1/8. The output dither on the TAA resolve removes the 8-bit
write band, not this larger lighting step. A smooth shadow gradient in shade,
most visible on the floor below a ramp, shows the step as a contour band.

The TAA history averages the sample pattern, but the resolved field keeps the
step. The color clamp is not the cause: a 600-frame run with `clamp: false` and
the default produced the same field. `scenarios/ramp-shadow.json` measures 298
steps in a 550x280 patch of the shadow floor on the old shader.

## Decision

Offset a partial count by a per-pixel, per-frame hash inside one step before
dividing by the sample count. A count of zero and a full count stay exact. The
hash takes the shadow phase, so the offset changes each frame and the TAA
history averages it. The history stays linear and never sees the output dither.
With TAA off, or with the phase frozen, the offset is a fixed per-pixel pattern.

The same rule applies to the sun and the ambient count. A fragment in full sun
or full umbra is exact, so the stable gates do not see a flicker.

## Options considered

- **More rays.** A 64-ray diagnostic removed the terraces on the ramp underside
  at seven times the AO ray cost. The estimator still quantizes; it only moves
  the step below the visible scale.
- **A separate AO pass and a denoiser.** That is the long-term shape for a real
  spatiotemporal filter, but it adds a target, a pass, and a filter. First stop
  the ray count from quantizing the lighting.
- **Disable the TAA color clamp.** Measured; it does not change the field. The
  clamp is not the cause.
- **Scale the ambient by a smooth function of the count.** It changes the value
  at a partial count and biases the term.
- **No dither.** The count remains a hard step. The output dither cannot hide a
  step that is many levels tall.

## Consequences

- `scenarios/ramp-shadow.json` measures 298 steps and a 0.642 level maximum jump
  on the old shader, and 3 steps and 0.514 with the rounding. The gate is 50
  steps, so the old shader fails and the new one passes with margin.
- `capture.stats.steps` gates the class. It box-filters the luma 9x9, which
  removes the output dither and the sample noise, then counts adjacent jumps
  between 0.5 and 8 levels. A soft gradient has none; a visibility step leaves a
  run. The 8 level cap leaves a geometry edge out. The metric needs a region,
  which must sit at least four pixels inside a flat boundary.
- `taa-static` worst mean delta is 0.0082 of 255 against a gate of 0.02. The
  exact full and empty counts keep the sunlit and umbral pixels stable.
- `shadow-angle` and `edge-profile` still pass. The sun penumbra takes the same
  offset, so its 1/16 steps also break.
- The full scene adds one hash per lit fragment. `scenarios/perf.json` at
  1280x720 measured about 0.63 ms of scene time with the offset; the run-to-run
  spread is larger than the hash next to the rays.
- The output dither stays the last step for the 8-bit write. The two dithers are
  separate: the visibility offset is in linear lighting, and the output dither
  is in encoded sRGB.
