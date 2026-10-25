# 0027 A 32-bit TAA history

## Context

The TAA resolve keeps a ping-pong history and a per-pixel sample count. Each
frame it blends the current sample with weight one over the count plus one, up
to 512. The scene, velocity, history, and count targets were all 16-bit floats.

The shaded floor below the 20 degree ramp still showed contour bands after the
visibility dither landed. The dither breaks a ray-count step in one frame, but
the smooth field comes from the time average. The 16-bit history cannot hold
that average: at 512 samples a new sample carries weight 1/513, and one fp16
step near the floor's linear value of 0.03 is about 3e-5. The update is below
the step, so rounding noise moves the history instead of the sample mean.

Measured on `scenarios/ramp-shadow-crouch.json` at 1280x720 after 600 frames,
in the 600x300 stats region:

| History | Steps | Max jump | Mean against a 32-phase reference |
| --- | ---: | ---: | ---: |
| R16G16B16A16_SFLOAT | 275 | 0.638 | -1.9 levels |
| R32G32B32A32_SFLOAT | 0 | 0.494 | +0.5 levels |

The reference is the mean of 32 frozen sun phases rendered with TAA off. The
16-bit field stayed 0.0022 luma away from its own value between frames 180 and
600; the 32-bit field moved 0.0001. The 16-bit field therefore never settles on
the phase average.

## Decision

`HISTORY_FORMAT` is `R32G32B32A32_SFLOAT`. The scene color, velocity, and count
targets stay 16-bit. The capture readback learns the format (name, 16 bytes per
texel, and float decode), and the readback buffer sizes for the largest target.

`scenarios/ramp-shadow-crouch.json` adds the crouched view under the 20 degree
ramp. It settles 600 frames and gates the `capture.stats.steps` count in a
600x300 region at `(450, 350)`.

## Options considered

- **Increase the ambient rays.** 64 rays removed the terraces in a diagnostic,
  at seven times the ambient ray cost, about 7 ms at 1440p. It also leaves the
  estimator quantized; it only moves the step below the visible scale.
- **Cap the sample count lower.** The update weight stays above one fp16 step,
  but the history loses the long average and the steady image becomes noisier.
- **Split the history into 16-bit color and 32-bit visibility.** The visibility
  already lives in the color; a second target and a composite add more than the
  precision costs.
- **Filter ambient occlusion in a separate pass.** The half-resolution pass with
  a bilateral upsample is the right shape for an AO denoiser, and it is still
  the next step if the AO budget tightens. It adds a G-buffer, a target, and a
  pass for a defect that is precision, not sampling.
- **Keep 16-bit and accept the bands.** The bands are the reported bug.

## Consequences

- `scenarios/ramp-shadow-crouch.json` measures 275 steps and a 0.638 level
  maximum on the old format, and 0 steps and 0.494 on the new one. The gate is
  25 steps and a maximum below 2.
- The converged field matches the 32-phase reference to -0.000015 linear luma
  with a 0.0014 standard deviation; the 16-bit field was -0.0031 with 0.0024.
- `scenarios/perf.json` at 2560x1440, median of three runs: the TAA resolve
  rises from 0.222 to 0.393 ms, and the GPU total from 1.530 to 1.705 ms. The
  scene pass is unchanged within the run spread.
- The two history images cost 59 MB more at 2560x1440, 118 MB against 59 MB.
  The capture readback buffer sizes for 16 bytes per texel, 59 MB at 1440p. The
  live game allocates it even though only the harness reads it back.
- The visibility dither stays. It breaks the step in a single frame and covers
  TAA off; the phase sequence and the 32-bit history make the time average
  continuous. The output dither still handles the 8-bit write per
  `docs/adr/0020-output-dither-for-the-8-bit-target.md`.
