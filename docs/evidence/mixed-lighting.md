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
Capture extents are named per table. The perf windows run 120 measured frames
after 30 warmup frames and a 1 s prime, except the ramp window. GPU values
belong to the last completed frame, and the GPU total is the sum of the TLAS,
cluster, depth, scene, TAA, and overlay passes.

## Quality captures

Each scenario is one run under `runs/`. Capture entries carry statistics,
render digests, and the renderer bake status; images stay in the run directory
and are not committed.

```sh
./bin/harbagsa-agent run scenarios/lighting-quality.json --out runs/lighting-quality
./bin/harbagsa-agent run scenarios/lighting-wall.json --out runs/lighting-wall
./bin/harbagsa-agent run scenarios/lighting-seam.json --param lightmap=true --out runs/lighting-seam-mixed
./bin/harbagsa-agent run scenarios/lighting-seam.json --param lightmap=false --out runs/lighting-seam-direct
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
| Hard real-time shadows | `bounce` then `no-shadow`, where every point-light shadow ray is off | The amber crate casts a hard shadow to its right. The floor region `760,350,240x150` inside that shadow is mean 54.55 with shadows on and 93.40 with them off; the whole frame goes 80.92 → 84.67. |
| Static fixtures keep those shadows while crates move | `bounce` then `crate-moved`; crate 2 moved from `[-3, 0.5, 6]` to `[-2, 0.5, 6.5]` | The crate shadow moves with the crate. Frame mean 80.92 → 81.41, delta mean 5.06. `state.bake.status` stays `current` on key `6920149317377461357`, so the shadow is real-time and the bake did not run. |
| The baked bounce is visible and separate from direct light | `bounce` against `direct`, where `lightmap` and `probe` are off | Frame mean 80.92 against 73.07, delta mean 15.77 against `no-shadow`. The shadowed crate face and the wall corner are exactly black with the terms off: 23.1% of the frame is exactly zero against 1.7% with the terms on. Turning the terms back on returns the mean to 80.9193; the digest differs because the simulation advanced a few frames between the two captures and the crates settle. |
| Dynamic lamps do not change baked indirect | `dynamic-near` then `dynamic-far`, with one dynamic lamp moved from `[-1, 1.5, 4]` to `[2, 1.5, 6]` | The bake key and `current` status do not change. The corner region `0,0,300x150`, outside both lamp ranges, is mean 5.80191088 in both captures. Direct light and shadow change across the frame (frame mean 94.01 → 89.67). |
| A stale bake is visible | `lamp-removed` after removing the static `initial-lamp` | Status `stale` on the changed key `9975754936429652796`. The direct pool is gone but the old warm bounce is still on the floor (frame mean 38.72). |
| A republish replaces the stale indirect | `lamp-removed-republished` after `bake` | Status `current`; frame mean 38.72 → 21.23. The stale bounce is gone and only the panel and beacon remain. |
| A missing bake is visible | `lighting-missing.json` with `--bake build/bake/missing.hbake` against the same scenario with the default artifact | `state.bake.status` is `missing`, `artifact_key` 0, and the frame mean is 73.10 against 80.94. `compare` reports 902,029 differing pixels, mean 11.217, max 64. |
| No wall leak | A sealed four-wall 4x4 m cell, a static fixture inside, a dim static `cell-fill` outside that lights the measured face, and a dynamic crate outside; the inside fixture then moves to `[19, 1.2, 18]` and the bake republishes | The cell's outer face region `200,200,400x250` is mean 16.52490997 in both bakes, and its min, max, stddev, and gradient match exactly too. The crate face moves 157.0363 → 157.0057, 0.031 code values out of 255. Both frames report `current`. |
| No lightmap seam | Stair treads and the floor-wall contact, once with the lightmap term and once without, then compared | The mixed and direct runs differ by mean 8.06 (stairs) and 12.64 (junction), max 29 and 31, with no outlier line. The stair band `400,250,640x210` has gradient 0.722 mixed against 0.650 direct, and the junction band `0,330,1280x90` 0.604 against 0.276: the term adds a smooth field, not a step. Both images show clean chart borders. |
| All lights off with an empty current bake is black | `bake-empty.json`, which removes all three static fixtures and publishes | `empty-scene` on `scene_color` is mean 0 with `zero_fraction` 1.0: every scene pixel is exactly zero. The final colour frame is black too, with a maximum of 1 code value out of 255 and 83.5% of pixels exactly zero; the rest is the one-step rounding of the resolve, not scene light. |

The crate-move and dynamic-lamp pairs are compared with the in-run capture
deltas, which compare each capture with the previous colour capture in the same
run. The seam and missing-bake pairs are separate runs compared with the harness
compare tool.

## Performance

`scenarios/perf-mixed.json` runs at 1920x1080 with 96 synthetic point lights and
shadows on. Direct and mixed windows alternate, and each single-term window sits
between two direct windows, so a clock drift cannot pose as an indirect term.
The ramp window and `direct-0` absorb the clock ramp and are not quoted.

```sh
./bin/harbagsa-agent run scenarios/perf-mixed.json --out runs/perf-mixed-1
./bin/harbagsa-agent run scenarios/perf-mixed.json --out runs/perf-mixed-2
./bin/harbagsa-agent run scenarios/perf-mixed.json --out runs/perf-mixed-3
```

| Window | Run 1 | Run 2 | Run 3 | Delta, median (max) | Budget | Result |
| -- | --: | --: | --: | --: | --: | -- |
| `direct-2` to `direct-5` | 1.474–1.484 | 1.473–1.474 | 1.474–1.498 | — | — | baseline |
| `lightmap-1` | 1.5160 | 1.5184 | 1.5101 | +0.037 (0.045) | 0.25 | pass |
| `probe-1` | 1.4800 | 1.4687 | 1.4791 | +0.003 (0.005) | 0.60 | pass |
| `mixed-1` | 1.5244 | 1.5345 | 1.5158 | +0.050 (0.062) | 1.00 | pass |
| `mixed-2` | 1.5205 | 1.5091 | 1.5162 | +0.036 (0.044) | 1.00 | pass |

Each delta is the window against the direct window that follows it, so a slow
drift cancels. `mixed-1` follows the ramp and is the noisiest window; `mixed-2`,
taken last, matches the single-term sum. The four direct windows in one run span
0.011 ms, which is the resolution of this method. The full frame at 96 lights
and 1080p is 1.51–1.53 ms `p50` with `p95` 1.56–1.58 ms against the 8.0 ms
budget, over five times under. The frame interval `p50` is 1.83–1.84 ms.

The term costs are whole-frame GPU-total deltas, not separate pass times: the
shader has no separate lightmap or probe pass, so the only honest instrument is
the same frame with the term switched.

## Bake

`bin/harbagsa-bake` on the default arena at 16 threads. `make bake` writes
`build/bake/arena.hbake` and the `.time` sidecar.

```sh
tools/make.sh bake
./bin/harbagsa-bake --out build/bake/arena-2m.hbake --probe-spacing 2
```

| Measure | Run 1 | Run 2 | Run 3 | Budget | Result |
| -- | --: | --: | --: | --: | -- |
| Total | 4879 ms | 5004 ms | 5130 ms | default 2000 ms | **miss** |
| Lightmap stage | 3004 ms | 3078 ms | 3194 ms | — | — |
| Probe stage | 1875 ms | 1925 ms | 1936 ms | — | — |
| Encode stage | 33 ms | 33 ms | 31 ms | — | — |
| Peak RSS | 36.3 MB | 34.9 MB | 39.8 MB | — | — |
| Artifact | 14,608,480 B | 14,608,480 B | 14,608,480 B | 32 MiB | pass |

The three 1 m runs write identical bytes: key `60094f23bef20c6d`, payload
`11ebf29058d3c291`, md5 `e99fb82b056a57fd696f9af5e8c868f2`. The `.time`
sidecar carries the measured wall time, so a loaded artifact reports it without
changing the artifact bytes.

Thread scaling on the same machine: 1 thread 37496 ms, 4 threads 9810 ms,
8 threads 6277 ms, 12 threads 5779 ms, 16 threads 4989 ms. The 16-thread default
is the fastest measured setting.

**Failure.** The default bake misses the 2 s target by about 2.5x; the lightmap
stage alone is about 3.0 s. The 2 m probe fallback saves the probe stage but
still lands at 3.3 s. The shipped 128-ray, 1024-probe quality is the only
quality the loader accepts, so there is no separate default preset to measure
against the 8 s high-quality row, and that row is not claimed. Closing the gap
needs either a cheaper published preset or a faster traversal; neither is in
this change.

## Measurement fix

Before this change a perf frame passed a zeroed capture request to the draw
path, so every measured frame read the colour target back and ran the per-pixel
delta. `scenarios/perf.json` at 1280x720 then reported an interval `p50` of
173.1 ms against a 0.68 ms GPU total and wrote 193 empty capture entries
(`runs/perf-baseline`). The same scenario now reports 0.695–0.750 ms and no
capture entries (`runs/perf-720-1` to `runs/perf-720-3`).
[perf-baseline.md](perf-baseline.md) records the detail. Do not compare an
interval measured before the fix with one measured after it.

## Accepted limitations

- The bake is deterministic but not noise-free. At 128 lightmap rays the
  indirect is visibly mottled on large dim walls; the seam captures show it.
  More rays reduce it linearly in time.
- The 2 s default bake target is missed; see above.
- The indirect is interpolation-only on the runtime side. A crevice narrower
  than the 1 m probe spacing can still carry a small probe error; the
  sealed-cell crate moved 0.031 code values when a fixture was removed outside
  its view, which bounds that error.
- A missing bake draws direct light only. It is a visible state, not a fallback:
  `state.bake.status` is `missing` and every indirect weight is zero.
