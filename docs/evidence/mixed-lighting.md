# Mixed-lighting evidence

Measurements for the mixed static baked indirect and dynamic direct system
described in [ADR 0045](../adr/0045-mixed-static-baked-indirect.md). The bake
data contract is [ADR 0044](../adr/0044-bake-data-contract.md); the work is
[HARB-305](https://linear.app/utbetdix/issue/HARB-305/measure-mixed-lighting-quality-and-performance).

## Machine

- AMD Ryzen 7 5700X, 8 cores and 16 hardware threads.
- AMD Radeon RX 9060 XT (RADV GFX1200), Mesa 26.2.5-arch1.1, Vulkan 1.4.354.
- Arch Linux.
- Measured 2026-10-29.

Every command runs offscreen with no window, compositor, or display pacing.
Capture extents are named per table. The perf command runs 120 measured frames
per window after 30 warmup frames and one 2 s prime, and discards its first
round. GPU values belong to the last completed frame, and the GPU total is the
sum of the TLAS, cluster, depth, scene, TAA, and overlay passes.

## Quality captures

Each scenario is one run under `runs/`. Capture entries carry statistics,
render digests, and the renderer bake status; images stay in the run directory
and are not committed.

```sh
./bin/harbagsa-agent run scenarios/lighting-quality.json --out runs/lighting-quality
./bin/harbagsa-agent run scenarios/lighting-wall.json --out runs/lighting-wall
./bin/harbagsa-agent run scenarios/lighting-seam.json --param indirect=true --out runs/lighting-seam-mixed
./bin/harbagsa-agent run scenarios/lighting-seam.json --param indirect=false --out runs/lighting-seam-direct
./bin/harbagsa-agent run scenarios/lighting-missing.json --bake build/bake/arena.hbake --out runs/lighting-bake-current
./bin/harbagsa-agent run scenarios/lighting-missing.json --bake build/bake/missing.hbake --out runs/lighting-bake-missing
./bin/harbagsa-agent compare runs/lighting-seam-mixed runs/lighting-seam-direct --delta
./bin/harbagsa-agent compare runs/lighting-bake-current runs/lighting-bake-missing --delta
./bin/harbagsa-agent run scenarios/bake-lifecycle.json --out runs/bake-lifecycle
./bin/harbagsa-agent run scenarios/bake-empty.json --out runs/bake-empty
```

`scenarios/lighting-quality.json` runs at 1280x720 with TAA and jitter off from
one fixed camera at `[-2, 2.4, 10]` looking at `[-3, 0.3, 6]`. The wall, seam,
missing, and bake-state runs are also 1280x720.

| Claim | Evidence | Result |
| -- | -- | -- |
| Hard real-time shadows | `bounce` then `no-shadow`, where every point-light shadow ray is off | The amber crate casts a hard shadow to its right. The floor region `760,350,240x150` inside that shadow is mean 54.62 with shadows on and 93.41 with them off; the whole frame goes 80.92 → 84.68. |
| Static fixtures keep those shadows while crates move | `bounce` then `crate-moved`; crate 2 moved from `[-3, 0.5, 6]` to `[-2, 0.5, 6.5]` | The crate shadow moves with the crate. Frame mean 80.92 → 81.42, delta mean 5.05. `state.bake.status` stays `current` on key `4759498390018400258`, so the shadow is real-time and the bake did not run. |
| The baked bounce is visible and separate from direct light | `bounce` against `direct`, where `lightmap` and `probe` are off | Frame mean 80.92 against 73.07, delta mean 11.23, max 64. The shadowed crate face and the wall corner are exactly black with the terms off: 23.06% of the frame is exactly zero against 1.17% with the terms on. Turning the terms back on returns the mean to 80.9221; the digest differs because the simulation advanced a few frames between the two captures and the crates settle. |
| Dynamic lamps do not change baked indirect | `dynamic-near` then `dynamic-far`, with one dynamic lamp moved from `[-1, 1.5, 4]` to `[2, 1.5, 6]` | The bake key and `current` status do not change. The corner region `0,0,300x150`, outside both lamp ranges, is mean 5.65588903 in both captures. Direct light and shadow change across the frame (frame mean 94.02 → 89.68). |
| A stale bake is visible | `lamp-removed` after removing the static `initial-lamp` | Status `stale` on the changed key `16127202276725259587`. The direct pool is gone but the old warm bounce is still on the floor (frame mean 38.78). |
| A republish replaces the stale indirect | `lamp-removed-republished` after `bake` | Status `current`; frame mean 38.78 → 21.23. The stale bounce is gone and only the panel and beacon remain. |
| A missing bake is visible | `lighting-missing.json` with `--bake build/bake/missing.hbake` against the same scenario with the default artifact | `state.bake.status` is `missing`, `artifact_key` 0, and the frame mean is 73.10 against 80.95. `compare` reports 907,943 differing pixels, mean 11.221, max 64. |
| No wall leak | A sealed four-wall 4x4 m cell, a static fixture inside, a dim static `cell-fill` outside that lights the measured face, and a dynamic crate outside; the inside fixture then moves to `[19, 1.2, 18]` and the bake republishes | The cell's outer face region `200,200,400x250` is mean 16.71099091 in both bakes, and its min, max, stddev, and gradient match exactly too. The crate face moves by 0.028, 0.045, and 0.080 code values out of 255 on red, green, and blue. Both frames report `current`. |
| No lightmap seam | Stair treads and the floor-wall contact, once with both indirect terms and once without either, then compared | The mixed and direct runs differ by mean 8.03 (stairs) and 12.70 (junction), max 25 and 23, with no outlier line. The stair band `400,250,640x210` has gradient 0.712 mixed against 0.650 direct, and the junction band `0,330,1280x90` 0.578 against 0.276: the term adds a smooth field, not a step. Both images show clean chart borders. |
| All lights off with an empty current bake is black | `bake-empty.json`, which removes all three static fixtures and publishes | `empty-scene` on `scene_color` is mean 0 with `zero_fraction` 1.0: every scene pixel is exactly zero. The final colour frame is black too, with a maximum of 1 code value out of 255 and 83.46% of pixels exactly zero; the rest is the one-step rounding of the resolve, not scene light. |

The crate-move and dynamic-lamp pairs are compared with the in-run capture
deltas, which compare each capture with the previous colour capture in the same
run. The seam and missing-bake pairs are separate runs compared with the harness
compare tool.

## Denoise

The lightmap gets one per-chart pass before the gutter. The chart repair is split
into a buried fill and a gutter, and the filter runs between them: a separable
3x3 binomial with the one-dimensional weights `[1 2 1]/4` over RGB, clamped at
the chart edge, with weights that sum to one. One chart is one planar face with
one normal, so the kernel cannot bleed across a surface, and the gutter still
isolates neighbouring charts. The texel seed follows `(source, id, face, x, y)`
instead of the atlas index, so a static edit that only moves charts does not
re-roll their noise. `TOOL_VERSION` is 2; the format version and the key version
stay 1.

```sh
./bin/harbagsa-agent run scenarios/lighting-noise.json --out runs/lighting-noise
```

The scenario looks at the unlit east wall (camera `[14, 1.2, 6]` at
`[20, 1.2, 6]`, 1280x720, TAA and jitter off) and captures two regions, once as
the coloured frame and once on `scene_color`: the whole wall band
`120,120,1000x400`, and a clean `250x160` window at `850,140` away from contacts
and edges. The before column is the same scenario against a tool version 1 bake,
which the loader binds as `stale` rather than rejecting.

| Capture | before | after | Change |
| --- | --: | --: | --- |
| `wall` mean | 10.61 | 10.75 | +1.3% |
| `wall` stddev | 3.568 | 3.320 | −7.0% |
| `wall-window` stddev | 2.003 | 0.928 | **−54%** |
| `wall-direct` stddev | 0.372 | 0.372 | control |

The whole-band stddev is not a noise measure: it is dominated by the wall's own
falloff across those 400 rows and by the bars and floor inside the region, which
the bake must keep. The clean window is the noise measure. The same two regions
on `scene_color`, before the resolve, carry no 8-bit encoding and show the
energy and the high frequency directly:

| `scene_color`, linear | before | after | Change |
| --- | --: | --: | --- |
| `wall-linear` mean | 0.0032745 | 0.0033093 | +1.1% |
| `wall-linear` stddev | 0.0011677 | 0.0010613 | −9.1% |
| `wall-linear` gradient | 0.00003826 | 0.00001581 | −59% |
| `wall-window-linear` mean | 0.0038227 | 0.0038631 | +1.1% |
| `wall-window-linear` stddev | 0.0006996 | 0.0002706 | **−61%** |
| `wall-window-linear` gradient | 0.00003166 | 0.00000762 | −76% |

The lightmap itself halves: decoded from the two artifacts, the mean absolute RGB
difference between 4-neighbour texels inside the chart interiors falls from
0.00055 to 0.00023 (2.4x), and from 0.00146 to 0.00065 on a 164x164 chart (2.2x).
The mean over the chart interiors is unchanged within 0.2% at
0.005332 / 0.004968 / 0.005318, and the linear band mean moves 1.1%, so the pass
neither adds nor loses energy. The window is only about five by four texels, so
its mean moves with the noise realization; the band and the chart interiors are
the energy checks, and the window stddev and gradient are the noise measures. The
sRGB band mean rises 1.3% because narrowing a distribution at a fixed linear mean
raises the encoded value; it is not added light.

A 5x5 Gaussian was measured on the same seed as the escalation and rejected: it
takes the clean window to 0.795 (−60%) and the whole band to 3.269, at two
texels (50 cm) of softening at contact corners instead of one. The 3x3 already
clears the −40% window floor at −54%, so the extra texel of softening buys six
points of a metric that is no longer the limit. The whole-band number stays far
from half either way.

The seed change is measurable on its own. Place a static crate 500 m away, place
another static crate near the arena, bake, remove the far crate, and bake again.
The far crate is beyond `RAY_MAX` and changes no light, but it shifts the second
crate's charts in the atlas. All 336 remaining faces are byte-identical across
the two bakes, 6 of them with a moved rect, worst difference 0. A tool version 1
bake reads the atlas index and re-rolls the moved chart.

## Performance

`scenarios/perf-mixed.json` runs at 1920x1080 with 96 synthetic point lights and
shadows on. One `perf` command measures four variants over three rounds:
`direct` is the baseline, and `lightmap`, `probe`, and `mixed` each sit between
two direct windows. The first round is discarded, so the two kept rounds bracket
every variant with a direct window on both sides.

```sh
./bin/harbagsa-agent run scenarios/perf-mixed.json --out runs/perf-mixed-1
./bin/harbagsa-agent run scenarios/perf-mixed.json --out runs/perf-mixed-2
./bin/harbagsa-agent run scenarios/perf-mixed.json --out runs/perf-mixed-3
```

| Variant | Run 1 | Run 2 | Run 3 | Interval delta, run 1 / 2 / 3 | GPU delta, run 1 / 2 / 3 | Budget |
| -- | --: | --: | --: | --: | --: | --: |
| `direct` | 1.8290 | 1.8309 | 1.8548 | — | — | — |
| `lightmap` | 1.8703 | 1.8824 | 1.9455 | +0.036 (0.003) / +0.026 (0.021) / +0.025 (0.009) | +0.029 (0.003) / +0.025 (0.004) / +0.035 (0.010) | 0.25 |
| `probe` | 1.8097 | 1.8177 | 1.8413 | −0.014 (0.013) / +0.001 (0.003) / +0.005 (0.004) | −0.003 (0.007) / −0.006 (0.000) / +0.000 (0.003) | 0.60 |
| `mixed` | 1.8562 | 1.8550 | 1.9071 | +0.021 (0.024) / +0.033 (0.002) / +0.039 (0.012) | +0.028 (0.003) / +0.029 (0.003) / +0.033 (0.010) | 1.00 |

The numbers are milliseconds. The variant column is the interval `p50`; each
paired delta is the mean of the per-round difference between the variant window
and the mean of the direct windows on either side, with the spread of those
rounds in brackets. The report also carries the minimum and maximum of each
delta. The GPU-total delta is the steadier instrument: `lightmap` costs
0.025–0.035 ms, `mixed` 0.028–0.033 ms, and `probe` stays within ±0.006 ms. The
interval delta is noisier because the CPU submits through one queue: `probe`
reads −0.014 to +0.005 ms there while its GPU delta is flat. Every per-round
spread is 0.024 ms or less. The full frame at 96 lights and 1080p is 1.50–1.52 ms
GPU total `p50` with `p95` 1.59–1.77 ms, and 1.83–1.85 ms frame interval `p50`
with `p95` 1.98–2.12 ms, against the 8.0 ms budget.

The report records `timestamp_period` 10 ns and the 1/5/15 minute load average
at the start and end of the command. This machine's `nvidia-smi` exits 9 with no
driver loaded and `rocm-smi` is absent, so the GPU clock is `known: false` and
the run warns. An unknown clock is stated, never filled with a guess.
`state.bake.gpu_bytes` is 14,608,096 bytes (13.9 MiB) against the 32 MiB budget,
and the artifact is 14,608,480 bytes against 32 MiB.

The term costs are whole-frame GPU-total deltas, not separate pass times: the
shader has no separate lightmap or probe pass, so the only honest instrument is
the same frame with the term switched. The denoise changes bake output only: the
frame path, the shader, and the 13.9 MiB of GPU lighting data are unchanged, so
the table stands.

## Bake

`bin/harbagsa-bake` on the default arena at 16 threads. `make bake` writes
`build/bake/arena.hbake` and the `.time` sidecar.

```sh
./bin/harbagsa-bake --out runs/bake-1m-1.hbake
./bin/harbagsa-bake --out runs/bake-2m.hbake --probe-spacing 2
tools/make.sh bake    # writes build/bake/arena.hbake for the runtime
```

| Measure | Run 1 | Run 2 | Run 3 | Budget | Result |
| -- | --: | --: | --: | --: | -- |
| Total | 4871 ms | 5114 ms | 5057 ms | default 2000 ms | **miss** |
| Lightmap stage | 3016 ms | 3101 ms | 3140 ms | — | — |
| Probe stage | 1854 ms | 2012 ms | 1916 ms | — | — |
| Encode stage | 33 ms | 33 ms | 31 ms | — | — |
| Peak RSS | 37.7 MB | 37.7 MB | 37.9 MB | — | — |
| Artifact | 14,608,480 B | 14,608,480 B | 14,608,480 B | 32 MiB | pass |

The three runs before the change were 5325, 4880, and 5076 ms total with the
lightmap at 3065, 3033, and 3169 ms, so the medians are 5076 → 5057 ms total and
3065 → 3101 ms on the lightmap stage, a rise of 36 ms or 1.2%. The stage spread
between runs on this machine is about ±100 ms, wider than the pass itself:
165,334 texels, six taps, three channels. Probe and encode work are unchanged.

The three 1 m runs write identical bytes: key `420d22919e172002`, payload
`038533c0ad8c9104`, md5 `eddbf9d487f6196c67c567f76406fc19`. The `.time`
sidecar carries the measured wall time, so a loaded artifact reports it without
changing the artifact bytes.

Thread scaling in one sweep on the same machine: 1 thread 37496 ms, 4 threads
9810 ms, 8 threads 6277 ms, 12 threads 5779 ms, 16 threads 4989 ms. The
16-thread default is the fastest measured setting.

**Failure.** The default bake misses the 2 s target by about 2.5x; the lightmap
stage alone is about 3.0 s. The 2 m probe fallback saves the probe stage but
still lands at 3.4 s. The shipped default is 1 m probes and 128 lightmap rays;
the only other accepted quality is the 2 m probe fallback, which changes the
probe cost only. There is no cheaper preset, so there is nothing to measure
against the 8 s high-quality row and that row is not claimed. Closing the gap
needs either a cheaper published preset or a faster traversal; neither is in
this change.

## Measurement fix

Before this change a perf frame passed a zeroed capture request to the draw
path, so every measured frame read the colour target back and ran the per-pixel
delta. `scenarios/perf.json` at 1280x720 then reported an interval `p50` of
173.1 ms against a 0.68 ms GPU total and wrote 193 empty capture entries
(`runs/perf-baseline`). The same scenario now reports 0.692–0.700 ms `p50` and no
capture entries (`runs/perf-720-1` to `runs/perf-720-3`).
[perf-baseline.md](perf-baseline.md) records the detail. Do not compare an
interval measured before the fix with one measured after it.

## Accepted limitations

- The bake is deterministic and now denoised. The per-chart 3x3 binomial filter
  halves the texel noise, so the wall's relative stddev narrows from 34% to 31%
  over the whole band and from 16% to 7% in a clean window. Some mottling is
  still measurable below the 8-bit output, and the one-texel filter softens
  contact corners by one texel. More rays reduce the rest linearly in time.
- The 2 s default bake target is missed; see above.
- The indirect is interpolation-only on the runtime side. A crevice narrower
  than the 1 m probe spacing can still carry a small probe error; the
  sealed-cell crate moved by at most 0.08 code values when a fixture was removed
  outside its view, which bounds that error.
- A missing bake draws direct light only. It is a visible state, not a fallback:
  `state.bake.status` is `missing` and every indirect weight is zero.
