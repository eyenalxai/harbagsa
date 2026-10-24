# Point light performance

Measured on 2026-10-24 from the `feat(renderer): add point lights with hard
shadows` commit on AMD Radeon RX 9060 XT (RADV GFX1200), Mesa 26.2.5. The scene
has no lamp prefabs yet, so the measurement uses the synthetic lights in the
renderer debug override.

## Method

`scenarios/perf-lamps.json` injects eight synthetic lights at fixed positions.
It runs one `perf` command with the point-light shadows on, disables them with
the gated `renderer_debug` override, then runs a second `perf` command. Both
traces stay in the run directory, so the shadow cost is a paired comparison
inside one run.

`scenarios/perf.json` is the no-light baseline at the same size and camera. The
comparison ran five times per size, alternating baseline and lamps in the same
session, and the table holds the median of the five per-run scene-pass means.
All runs are offscreen, so the interval is throughput, not display pacing.

```sh
tools/make.sh build
./bin/harbagsa-agent run scenarios/perf.json --size 1920x1080 --out runs/perf-base-1080
./bin/harbagsa-agent run scenarios/perf-lamps.json --debug-renderer --size 1920x1080 --out runs/perf-lamps-1080
./bin/harbagsa-agent run scenarios/perf.json --size 2560x1440 --out runs/perf-base-1440
./bin/harbagsa-agent run scenarios/perf-lamps.json --debug-renderer --size 2560x1440 --out runs/perf-lamps-1440
```

`trace-shadows-on.jsonl` and `trace-shadows-off.jsonl` hold one line per
measured frame. The evidence is the traces and this table; no image is
committed.

## Results

All values are milliseconds. The scene pass includes the depth prepass.

| Size | Frame | Interval | GPU total | Scene pass | Scene vs base |
| --- | --- | ---: | ---: | ---: | ---: |
| 1920x1080 | no lights | 1.264 | 1.063 | 0.735 | 1.00x |
| 1920x1080 | 8 lights, no shadows | 1.525 | 1.329 | 1.003 | 1.36x |
| 1920x1080 | 8 lights, shadows | 1.789 | 1.536 | 1.204 | 1.64x |
| 2560x1440 | no lights | 1.926 | 1.706 | 1.267 | 1.00x |
| 2560x1440 | 8 lights, no shadows | 2.257 | 2.012 | 1.592 | 1.26x |
| 2560x1440 | 8 lights, shadows | 2.715 | 2.480 | 2.037 | 1.61x |

The paired shadow cost is the difference between the two lamp rows:

| Size | Scene, shadows off | Scene, shadows on | Delta | Ratio |
| --- | ---: | ---: | ---: | ---: |
| 1920x1080 | 1.003 | 1.204 | +0.203 | 1.20x |
| 2560x1440 | 1.592 | 2.037 | +0.444 | 1.28x |

## What the numbers say

- Eight lights without shadows cost 0.27 ms at 1080p and 0.33 ms at 1440p. Most
  of that is the light loop over the covered pixels, not the buffer upload.
- The eight hard shadow rays cost another 0.20 ms at 1080p and 0.44 ms at
  1440p. The cost scales with the covered pixel count, as one ray per light per
  shaded fragment does.
- The full light budget takes the scene pass from 0.74 to 1.20 ms at 1080p and
  from 1.27 to 2.04 ms at 1440p. The GPU total rises by about 0.47 ms and
  0.77 ms.
- At 1440p the full light budget is 2.48 ms of GPU total, about 15% of a 60 Hz
  frame. It fits while the arena stays under 2 ms without lights.
- The paired runs show the shadow switch does only what it says: the light
  contribution stays in both sides, so the delta is the ray cost alone.

## What remains

- **Half-resolution light shadows**: trace one shared visibility mask and
  upsample it. The point light is small, so a soft edge would not show much,
  but the mask needs a target and a pass.
- **Fewer active lights**: the frame selects the eight nearest lights in the
  later lamp ticket. A narrower cap lowers the per-pixel loop and ray count
  together.
- **Per-light culling**: the shader currently runs the loop for every active
  light on every pixel. Bounding the light by screen tile would remove most of
  the loop for small pools.
- **Shadow ray early-out**: the point shadow ray already starts at the surface
  normal; a depth-aware bias would let the origin move further out and reduce
  self-intersection tuning.
