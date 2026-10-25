# Sky and ambient occlusion evidence

Captured on 2026-10-24 from `6e63513` on branch
`research-modern-ambient-occlusion`. GPU: AMD Radeon RX 9060 XT (RADV
GFX1200). All runs are offscreen through `bin/harbagsa-agent`.

## What changed

The flat clear colour became an analytic sky gradient. The constant ambient
became a sky ramp on the surface normal, and eight ray-traced ambient occlusion
rays per fragment scale it in shade. The design is in
`docs/adr/0017-sky-ambient-and-ray-traced-ambient-occlusion.md`.

## Performance

The before column is the current base, `d7c2e82`, built in a second worktree.
Each side ran three times, alternating base and feature at the same size. The
table reports the median. The table in `docs/evidence/perf-scene-pass.md` is not
comparable: it was measured from `0d74d57`, before the real sun angular diameter
changed the default sun angle and the number of sun-facing pixels.

| Scenario | Size | GPU base | GPU feature | Scene base | Scene feature |
| --- | --- | ---: | ---: | ---: | ---: |
| `perf` | 1920x1080 | 1.060 | 1.597 | 0.732 | 1.266 |
| `perf` | 2560x1440 | 1.697 | 2.611 | 1.259 | 2.165 |
| `perf-arena` | 2560x1440 | 2.152 | 2.991 | 1.717 | 2.563 |
| `perf-backface` | 1920x1080 | 0.882 | 1.438 | 0.558 | 1.113 |

The TLAS build stays at 0.176 ms and the resolve at 0.270 ms at 1440p. The scene
pass owns the difference. The feature adds 0.54, 0.91, 0.84, and 0.56 ms in the
four views.

AO costs about 0.91 ms extra at 1440p, or 0.11 ms per ray at eight rays.
Hemisphere rays are incoherent, while the 16 sun rays stay inside the 0.53°
disk. Four rays measure 2.187 ms of GPU total at 1440p, 0.49 ms over the base,
so the marginal cost is 0.106 ms per ray.

The 2 ms target in `docs/adr/0014-scene-pass-depth-prepass-and-culling.md` was
set against a 1.11 ms base from `0d74d57`. The current base is 1.70 ms at
1440p, so the target no longer describes the tree. The feature adds 0.91 ms to
it. Half-resolution AO with a normal target and a bilateral upsample is the next
step if the budget tightens; it was deferred because it needs a G-buffer pass
and a target.

Reproduce:

```sh
tools/make.sh build
./bin/harbagsa-agent run scenarios/perf.json --size 1920x1080 --out runs/perf-1080
./bin/harbagsa-agent run scenarios/perf.json --size 2560x1440 --out runs/perf-1440
./bin/harbagsa-agent run scenarios/perf-arena.json --size 2560x1440 --out runs/perf-arena
./bin/harbagsa-agent run scenarios/perf-backface.json --size 1920x1080 --out runs/perf-backface
```

## Image gates

`scenarios/sky-ao.json` at 1280x720. It declares `requires.renderer_debug`,
because it changes the `ao` and `sky` overrides. The sky captures look at the zenith and
the horizon. The corner captures look from `(18.8, 0.9, 18.8)` into the wall
corner. The last capture returns to the zenith with `sky: false`.

| Capture | Mean green | Gate | Passes |
| --- | ---: | --- | --- |
| `sky-zenith` | 135.83 | at most 140 | yes |
| `sky-horizon` | 156.25 | at least 150 | yes |
| `corner-off` | 69.88 | at least 64 | yes |
| `corner-on` | 53.45 | at most 58 | yes |
| `flat-zenith` | 178.83 | at least 170 | yes |

The gates have teeth. Two negative controls were built by copying the scenario:

- With `sky: false` from the start, the zenith mean is 179 and the 140 gate
  fails. Run: `runs/sky-ao-nosky`.
- With AO never re-enabled, the corner mean stays 69.84 and the 58 gate fails.
  Run: `runs/sky-ao-noao`.

The two corner gates are separated by six levels, so a zero delta at 60 cannot
pass both. The sky gates are separated by 39 levels, so a flat background at
the sky-on value cannot pass the flat gate.

Reproduce:

```sh
./bin/harbagsa-agent run scenarios/sky-ao.json
```

## Shade-only ambient occlusion

Captured on 2026-10-25 from `fix/ambient-occlusion-stairs`. The sunlit floor
was showing a soft dark band at the foot of the dive stairs. A path-traced
reference with the same boxes, palette, and sun confirmed that the sunlit floor
should keep one value and that the contact darkening belongs to the shade. The
shader now gates the AO by the sun visibility, so a fragment in sun keeps the
full ambient.

`scenarios/stairs-ao.json` at 800x600, sun at 25°. It declares
`requires.renderer_debug`. The sunlit region is `{300, 400, 120, 60}` and the shaded
wall region is `{700, 140, 40, 40}`.

| Region | AO on | AO off | Gate | Passes |
| --- | ---: | ---: | --- | --- |
| Sunlit floor | 144.5 | 144.5 | at least 143 | yes |
| Shaded wall | 75.2 | 109.4 | on at most 78, off at least 105 | yes |

The gate has teeth. The pre-fix shader measures 142.1 on the sunlit floor and
fails the 143 gate; the shaded wall is 72.9 and still passes the AO check. Run:
`runs/stairs-ao-before`.

Reproduce:

```sh
./bin/harbagsa-agent run scenarios/stairs-ao.json
```

## TAA stability

`scenarios/taa-motion.json` at 1280x720, after the post-motion hold:

| Check | Measured | Gate |
| --- | ---: | ---: |
| `capture.worst_mean_delta` | 0.0433 of 255 | at most 0.07 |
| `capture.worst_over_16_fraction` | 2.17e-06 | at most 5e-06 |

The mean gate moved from 0.03 to 0.07. The AO term is stochastic in shade, and
TAA averages it as a running mean: the frame-to-frame shift is the per-frame
noise amplitude divided by the sample count. The shade-only gate removes the
visible AO noise from the sunlit part, so the measured value fell from 0.0567 to
0.0433. Measured at the same point on the pre-gate build:

| AO rays | Worst mean delta |
| --- | ---: |
| 4 | 0.083 |
| 8 | 0.057 |
| 16 | 0.041 |

At 32 rays the value would approach 0.03, at four times the AO cost. The
`worst_over_16_fraction` gate is unchanged and stays far below its limit, so the
image does not flicker. The mean gate now sits above the noise floor of the
stochastic term instead of inside it. `docs/evidence/taa.md` records the old
value and points here.

## What passes

`make check`, `make test` (258 tests across seven packages), and `make validate`
(validation layers, offscreen and present) pass.

The harness suite passes at 1280x720:

```text
smoke, taa-static, taa-motion, capture-targets, renderer-state, renderer-reset,
renderer-debug, renderer-debug-converge, renderer-debug-jitter, settings-menu,
sky-ao, stairs-ao
```

`taa-motion`, `renderer-debug`, `renderer-debug-converge`, and
`renderer-debug-jitter` need `--debug-renderer`. `sky-ao` and `stairs-ao`
declare their gate.

## What remains

- One diffuse bounce. AO is visibility, not transport, so a deep tunnel darkens
  with depth and nothing fills it. The shade-only gate is a visibility rule, not
  a bounce.
- Half-resolution AO, if the frame budget tightens.
- A sky tint that follows a low sun. The sun disk and glow follow the sun now;
  the ambient palette does not.
- Specular and bent normals. The AO samples could accumulate the average
  unoccluded direction for free.

## Run directories

All are under `runs/` and are not committed:

- `runs/perf-1080`, `runs/perf-1440`, `runs/perf-arena`, `runs/perf-backface`
- `runs/sky-ao`, `runs/sky-ao-nosky`, `runs/sky-ao-noao`
- `runs/stairs-ao` and `runs/stairs-ao-before`
- `runs/taa-motion`, and the 4-ray and 16-ray calibration runs were temporary
  copies of the same scenario. The alternating base and feature perf runs are
  under `/tmp/opencode/ab-*`; the current runs are also in `runs/perf-*`.
