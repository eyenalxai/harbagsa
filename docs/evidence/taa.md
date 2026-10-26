# TAA evidence

> Historical note: the sun was removed after this capture. Current direct light
> is point lights.

Captured on 2026-10-23 from `main` at `363041e` (merge of #62). GPU: AMD Radeon
RX 9060 XT (RADV GFX1200). Window: 2536x1386. This is larger than the 1280x720
acceptance target.

Evidence is a run directory plus a scenario. `scenarios/taa-static.json` is the
still-camera record and `scenarios/taa-motion.json` is the motion record. Run
each into `runs/taa-static/` and `runs/taa-motion/`, then read `frames/` and
`analysis.json`.

## Still camera

The camera does not move between frames. `F3` toggles TAA. The HUD and the
crosshair are drawn after the resolve, so they stay crisp. The diagonal edges of
the green crate and the blue ramp are the edge check: TAA smooths them, and with
TAA off they show stair-steps.

## Walking, crate push, and reset

`scenarios/taa-motion.json` moves the camera into the green crate and pushes it,
then holds the view. `R` returns the player to spawn and clears the history. The
crate leaves no trail, and the reset does not smear.

## HUD and debug view

`F3` is in both control panels. `F1` draws exact outlines. `F2` enters debug mode
and keeps `F3` active. `scenarios/hud-debug.json` captures the debug readout into
`runs/hud-debug/`.

`scenarios/renderer-state.json` settles a static scene and gates
`renderer.taa_enabled`, `renderer.history_valid`, `renderer.convergence_frames`,
and the render digest. Run it into `runs/renderer-state/`.

## Performance

MangoHud reports 60 fps and 16.7 ms at 2536x1386. The GPU load is 8%. The
1280x720 target is smaller.

## Validation

`make validate` ran with `VK_LAYER_KHRONOS_validation` for 15 seconds. The log
had no `VUID` or `[ERROR]` lines. The target runs the demo until it closes, so
the run was stopped after the checks.

The validation layer found a pre-existing swapchain semaphore reuse error. #24
fixes it with one render-finished semaphore per acquired image.

## Temporal stability fix

Captured on 2026-10-24 from `fix/taa-unjittered-velocity`. The original run
predates the ray-query shadows and this fix.

At the time, `scenarios/taa-static.json` settled the camera for 8 frames and
captured 25 frames. The harness then rendered only capture frames, so those
frames measured the initial convergence, not the steady image. On the 16 pairs
from frames 8-23 the mean frame delta was 0.196/255 and 0.290% of pixels changed
by more than 16/255. The worst pair changed by 0.350/255 mean with 6,832 pixels
above 16/255.

After that fix, the worst pair in the same window changed by 0.053/255 mean. The
worst count above 16/255 was 972, or 0.105% of the frame. Those numbers are
historical; the accumulation fix below retargets the scenario at the steady
image.

The root cause was the velocity target. The box fragment shader mixed an
unjittered previous projection with the jittered current sample, so a still
camera stored the negative jitter. The resolve then sampled the history one
jitter offset away from the pixel. The fragment shader now projects both ends in
unjittered UV space. See #101.

## Accumulation fix

Captured on 2026-10-24 from `fix-taa-stairs-flicker`. The fix for #101 removed
the reprojection error, but a still image still rippled on stair silhouettes.
The ripple repeated every eight frames, the length of the jitter cycle.

The earlier scenario captured 25 frames and warmed up four captures. The harness
then rendered only capture frames, so those frames were the initial convergence,
not the steady image. That is why the gate passed while the flicker remained. The
new `settle` command renders frames without writing a PNG.

### Root cause

The resolve blended with a fixed weight of 0.9. Over one eight-phase jitter cycle
the weights were 0.1, 0.09, 0.081, and so on, so a still pixel settled into a
period-eight cycle instead of a fixed value. Longer fixed weights reduced the
ripple, but a global weight or count froze edge patterns after camera motion: a
300-frame global ramp left a hold image 95/255 away from a fresh still image on
1,619 pixels.

### Change

Each history image now has a per-pixel sample count. The resolve averages a new
sample with weight one over the count plus one, up to 512. The count follows the
reprojected surface, and a depth rejection resets it to one, so a disocclusion
reconverges in a few frames. The history clamp uses a 2σ variance box in YCoCg
instead of the min/max intersection; the min/max box collapses on flat
neighborhoods and causes phase-dependent pops.

### Still camera at 800x600

The camera is the stairs view from the reported repro: `[-12, 1.7, 6.0]`, yaw 0,
pitch -0.22. The comparison uses the last 200 frames after the accumulation
settles.

| Metric | Before | After |
| --- | --- | --- |
| worst mean frame delta | 0.0409/255 | 0.0013/255 |
| worst single-pixel delta | 41/255 | 4/255 |
| pixels above 16/255 in one pair | 51 | 0 |
| pixels with a 200-frame range above 16/255 | 144 | 0 |
| pixels with a 200-frame range above 4/255 | 5,660 | 220 |
| worst 200-frame per-pixel range | 42/255 | 12/255 |

The arena stairs region alone drops from a 30/255 range and 924 pixels above
8/255 to a 12/255 range and 2 pixels above 8/255.

The scenario settles 520 frames, so the accumulation count reaches the 512 cap.
The 800x600 worst pair is 0.0022/255 mean and the 1280x720 worst pair is
0.0031/255. The static scenario gates `capture.worst_mean_delta <= 0.02` and
`capture.worst_over_16_fraction <= 0.000005`.

The pre-fix renderer fails both new gates: the static worst pair is 0.058/255
with 51 pixels above 16/255, and the motion worst hold pair is 0.052/255 with 202
pixels above 16/255.

### After motion

Move the camera up the stairs, turn 180 degrees, hold, and compare the last hold
frame with a fresh still image of the same view at 800x600. The per-pixel count
reconverges after the disocclusions, so the hold image returns to the fresh image
instead of keeping a baked edge pattern.

| Variant | Pixels above 16/255 | Worst pixel | Mean |
| --- | --- | --- | --- |
| Before, fixed 0.9 weight | 202 | 19/255 | 0.054 |
| Global 256-frame ramp | 1,619 | 95/255 | 0.172 |
| Per-pixel count | 24 | 25/255 | 0.040 |

`scenarios/taa-motion.json` gates the hold deltas after 20 warmup captures at
`capture.worst_mean_delta <= 0.03` and `capture.worst_over_16_fraction <=
0.000005`.

Superseded by `docs/adr/0028-direct-light-with-surface-occlusion.md`: the occlusion term now scales the direct light at strength 0.5. The mean gate stays at 0.07 and the fraction gate at 0.000005. The direct-light run measures 0.0412 and 3.25e-06.

### Crate push

The moving crate shadow stays sharp. Against a no-TAA reference the count variant
differs by 0.39/255 mean; the count does not keep the stale shadow for the length
of the history.

## History precision

Captured on 2026-10-25 from `fix/shadow-banding-1`. The accumulation count caps
at 512, so each new sample carries weight 1/513. The shaded floor below a ramp
has a linear value near 0.03, where one fp16 step is about 3e-5; the update is
below that step. The 16-bit history therefore cannot hold the running average,
and the resolved field keeps the 1/8 occlusion steps.

The history is now `R32G32B32A32_SFLOAT`; the scene color, velocity, and count
targets stay 16-bit. `scenarios/ramp-shadow-crouch.json` is the image gate. At
1280x720 in its 600x300 region, after 600 frames:

| History | Steps | Max jump |
| --- | ---: | ---: |
| R16G16B16A16_SFLOAT | 275 | 0.638 |
| R32G32B32A32_SFLOAT | 0 | 0.494 |

After the direct-light change in ADR 0028 the same region measures 0 steps and a
0.086 level maximum jump. The 16-bit comparison above is from the old ambient
scene and is kept for the record.

Against the mean of 32 frozen sun phases rendered with TAA off, the 32-bit field
is -0.000015 linear luma away with a 0.0014 deviation; the 16-bit field is
-0.0031 with 0.0024. The shadow region moves 0.0022 luma between frames 180 and
600 with 16-bit, and 0.0001 with 32-bit.

`scenarios/perf.json` at 2560x1440, median of three runs: the TAA resolve rises
from 0.222 to 0.393 ms and the GPU total from 1.530 to 1.705 ms. The scene pass
is unchanged within the run spread. The two history images cost 59 MB more at
1440p, and the capture readback buffer sizes for 16 bytes per texel.

The decision and the options are in `docs/adr/0027-32-bit-taa-history.md`.
