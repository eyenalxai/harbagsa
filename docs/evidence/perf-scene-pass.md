# Scene pass performance

Measured on 2026-10-24 from `ea769e1` on AMD Radeon RX 9060 XT (RADV GFX1200),
Mesa 26.2.5. Both sides are the same checkout and the same compiler; the scene
pass change was stashed for the baseline runs.

## Method

Each pair of binaries ran five times, alternating base and optimized in the
same session, so a clock change hits both sides. The table holds the median of
each side; the speedup is the median of the five per-pair scene-pass ratios.
All runs are offscreen, so the interval is throughput, not display pacing. The
harness window is not involved.

```sh
tools/make.sh build
./bin/harbagsa-agent run scenarios/perf.json --size 1920x1080 --out runs/perf-1080
./bin/harbagsa-agent run scenarios/perf.json --size 2560x1440 --out runs/perf-1440
./bin/harbagsa-agent run scenarios/perf-arena.json --size 2560x1440 --out runs/perf-arena
./bin/harbagsa-agent run scenarios/perf-backface.json --size 1920x1080 --out runs/perf-backface
```

`perf-arena` looks down at the arena from above, so every static box is in
view. `perf-backface` looks at the near wall, so every covered pixel faces away
from the sun. Both are regression probes for the problem report: the frame got
slower as more boxes entered the view.

## Results

All values are milliseconds. The arrow reads baseline → optimized.

| Scenario | Size | Interval p50 | GPU total | Scene pass | Scene speedup |
| --- | --- | ---: | ---: | ---: | ---: |
| `perf` | 1920x1080 | 1.37 → 0.95 | 1.18 → 0.77 | 0.96 → 0.53 | 1.8x |
| `perf` | 2560x1440 | 2.15 → 1.29 | 1.91 → 1.11 | 1.59 → 0.80 | 2.0x |
| `perf-arena` | 2560x1440 | 2.32 → 1.37 | 2.11 → 1.19 | 1.80 → 0.90 | 2.0x |
| `perf-backface` | 1920x1080 | 2.51 → 0.73 | 2.28 → 0.55 | 2.08 → 0.35 | 6.0x |

The TLAS build and the TAA resolve did not change between the two sides; the
scene pass owns the difference.

## What the numbers say

- The scene pass is 1.8x faster at 1080p and 2.0x at 1440p in the normal view.
- The backface view is 6.0x faster in the scene pass. The old shader traced 16
  rays per pixel for surfaces that face away from the sun and then multiplied
  the result by zero.
- The whole-arena view is 2.0x faster. The prepass removes the overdraw between
  boxes, but the rays on the visible floor still dominate. It is the remaining
  ceiling, and the half-resolution option is the next step if the target rises.
- At 1440p the optimized GPU total is 1.11 ms: about 8% of a 74.97 Hz frame and
  7% of a 60 Hz frame.

## Image quality

The smoke captures differ from the baseline at one to three edge pixels; the
rest of the image is byte-identical. Coplanar surfaces now resolve to the last
draw instead of the first, and the TAA analysis already names those edge pixels
as the unstable ones. The `taa-static`, `taa-motion`, `capture-targets`,
`renderer-state`, `renderer-reset`, `smoke`, and `settings-menu` scenarios pass.

## What changed

A depth-only prepass writes the nearest surface, the lit pass compares against
it and does not write depth, both passes cull back faces, and the lit shader
skips the sun rays when the face receives no direct sun. The reasoning and the
alternatives are in
[ADR 0014](../adr/0014-scene-pass-depth-prepass-and-culling.md).

## What remains

- **Half-resolution shadow mask**: traces a quarter of the rays and upsamples
  the visibility. It costs some contact-shadow crispness and adds a target and
  a pass. Not needed while the 1440p GPU total stays under 2 ms.
- **TLAS update instead of build**: the box transforms change only when a crate
  moves. An update pass could remove part of the 0.18 ms build.
- **Instanced draws**: the default scene draws 54 boxes as 108 indexed draws
  after the prepass. The record phase is not the bottleneck on this GPU.
