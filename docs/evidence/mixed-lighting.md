# Mixed-lighting evidence

Measurements for the mixed static baked indirect and dynamic direct system
described in [ADR 0045](../adr/0045-mixed-static-baked-indirect.md). The bake
data contract is [ADR 0044](../adr/0044-bake-data-contract.md); the run-through
is [HARB-305](https://linear.app/utbetdix/issue/HARB-305/measure-mixed-lighting-quality-and-performance).

## Machine

- AMD Ryzen 7 5700X, 8 cores and 16 hardware threads, 16 logical CPUs.
- AMD Radeon RX 9060 XT (RADV GFX1200), Mesa 26.2.5-arch1.1, Vulkan 1.4.354.
- Arch Linux, kernel reported by the machine at measurement time.
- Measured 2026-10-29 at `f2bc300` plus the perf-readback fix in this change.

Every command runs offscreen with no window, compositor, or display pacing. The
extent is named per table. `p50` is the median over 120 measured frames after
60 warmup frames and a 2 s prime; the GPU total is the sum of the TLAS, cluster,
depth, scene, TAA, and overlay passes.

## Quality captures

Each scenario is one run under `runs/`. The capture entries carry statistics,
render digests, and the renderer bake status; images stay in the run directory
and are not committed.

```sh
./bin/harbagsa-agent run scenarios/lighting-quality.json --out runs/lighting-quality
./bin/harbagsa-agent run scenarios/lighting-wall.json --out runs/lighting-wall
./bin/harbagsa-agent run scenarios/lighting-seam.json --out runs/lighting-seam
./bin/harbagsa-agent run scenarios/lighting-missing.json \
  --bake build/bake/arena.hbake --out runs/lighting-bake-current
./bin/harbagsa-agent run scenarios/lighting-missing.json \
  --bake build/bake/missing.hbake --out runs/lighting-bake-missing
./bin/harbagsa-agent run scenarios/bake-lifecycle.json --out runs/bake-lifecycle
./bin/harbagsa-agent run scenarios/bake-empty.json --out runs/bake-empty
```

`scenarios/lighting-quality.json` runs at 1280x720 with TAA and jitter off from
one fixed camera at `[-2, 2.4, 10]` looking at `[-3, 0.3, 6]`.

| Claim | Evidence | Result |
| -- | -- | -- |
| Static fixtures keep hard real-time shadows while crates move | `bounce` then `crate-moved`; crate 2 moved from `[-3, 0.5, 6]` to `[-2, 0.5, 6.5]` | The crate shadow moves with the crate. Frame mean 80.92 → 81.41, delta mean 5.06, max 98. `state.bake.status` stays `current` on the same key `6920149317377461357`, so the shadow is real-time and the bake did not run. |
| The baked bounce is visible and separate from direct light | `bounce` against `direct`, where `lightmap` and `probe` are off | Frame mean 80.92 against 73.07; delta mean 11.23, max 64. The shadowed crate face and the wall corner are exactly black with the terms off. Turning the terms back on reproduces the frame (mean 80.9193 both times). |
| Dynamic lamps do not change baked indirect | `dynamic-near` then `dynamic-far`, with the same dynamic lamp moved from `[-1, 1.5, 4]` to `[2, 1.5, 6]` | The bake key and `current` status do not change. The corner region `0,0,300x150`, outside both lamp ranges, is mean 5.80191088 in both captures. Direct light and shadow change across the frame (frame mean 94.01 → 89.67). |
| A stale bake is visible | `lamp-removed` after removing the static `initial-lamp` | Status `stale` on the changed key `9975754936429652796`. The direct pool is gone but the old warm bounce is still on the floor (frame mean 38.72). |
| A republish replaces the stale indirect | `lamp-removed-republished` after `bake` | Status `current`; frame mean 38.72 → 21.23. The stale bounce is gone and only the panel and beacon remain. |
| A missing bake is visible | `lighting-missing.json` with `--bake build/bake/missing.hbake` against the same scenario with the default artifact | `state.bake.status` is `missing`, `artifact_key` 0, and the frame mean is 73.10 against 80.94. `compare` reports 902,029 differing pixels, mean 11.217, max 64. |
| No wall leak | A sealed four-wall 4x4 m cell with a static fixture inside and a dynamic crate outside; the same fixture then moved to `[19, 1.2, 18]` and republished | The cell's outer face region `200,200,400x250` is mean 16.52490997 in both bakes, bit-identical. The crate face changes by 0.031/255 (157.0363 → 157.0057), inside the tetrahedral interpolation noise. |
| No lightmap seam | Stair treads and the floor-wall contact, each with the lightmap on and off | No line or brightness step appears at a chart border. Stairs frame mean 35.58 against 28.35 direct; the junction 8.92 against 0.29. The junction view is almost entirely indirect, so a seam would be visible there. |
| All lights off with an empty current bake is black | `bake-empty.json`, which removes all three static fixtures and publishes | `empty-scene` on `scene_color` is mean 0 with `zero_fraction` 1.0: every scene pixel is exactly zero. The final colour frame is 83.5% exact zero; the remainder is the TAA and overlay path, not scene light. |

The crate-move and dynamic-lamp pairs are compared with the capture deltas in
one run. The missing-bake pair is compared with the harness compare tool:

```sh
./bin/harbagsa-agent compare runs/lighting-bake-current runs/lighting-bake-missing --delta
```

## Performance

`scenarios/perf-mixed.json` runs at 1920x1080 with 96 synthetic point lights,
shadows on, and one device for every window. The first window is the clock ramp;
`mixed-b`, `direct`, `lightmap-only`, `probe-only`, and `mixed-c` are comparable.

```sh
./bin/harbagsa-agent run scenarios/perf-mixed.json --out runs/perf-mixed-1
./bin/harbagsa-agent run scenarios/perf-mixed.json --out runs/perf-mixed-2
```

Two runs, GPU total `p50` in milliseconds:

| Window | Run 1 | Run 2 | Budget | Result |
| -- | --: | --: | --: | -- |
| `direct` | 1.4788 | 1.4772 | — | baseline |
| `lightmap-only` | 1.5132 | 1.5213 | 0.25 added | +0.034 / +0.044, pass |
| `probe-only` | 1.4724 | 1.4782 | 0.60 added | -0.007 / +0.001, pass |
| `mixed-b` | 1.5108 | 1.5154 | 1.00 added | +0.032 / +0.038, pass |
| `mixed-c` | 1.5089 | 1.5310 | 1.00 added | +0.030 / +0.054, pass |

The frame interval `p50` is 1.83–1.86 ms, close to the GPU total plus submit
cost. The full frame at 96 lights and 1080p is 1.51–1.53 ms against the 8.0 ms
budget, about five times under. The per-term deltas are near the 0.01–0.02 ms
run-to-run noise floor, so they bound the cost rather than resolve it; the
lightmap term is the larger of the two.

GPU lighting data is 14,608,096 bytes (13.9 MiB) from `state.bake.gpu_bytes`,
against the 32 MiB budget. The artifact is 14,608,480 bytes.

The default view and the arena plan view are in
[perf-baseline.md](perf-baseline.md).

## Bake

`bin/harbagsa-bake` on the default arena, three runs at 16 threads:

| Measure | Run 1 | Run 2 | Run 3 | Budget | Result |
| -- | --: | --: | --: | --: | -- |
| Total | 5185 ms | 4896 ms | 5067 ms | default 2000 ms | **miss** |
| Lightmap stage | 3265 ms | 3026 ms | 3194 ms | — | — |
| Probe stage | 1920 ms | 1870 ms | 1873 ms | — | — |
| Encode stage | 33 ms | 30 ms | 31 ms | — | — |
| Peak RSS | 39.8 MB | 39.1 MB | 36.8 MB | — | — |
| Artifact | 14,608,480 B | 14,608,480 B | 14,608,480 B | 32 MiB | pass |

All three runs write the same bytes: key `60094f23bef20c6d`, payload
`11ebf29058d3c291`, identical md5. The `.time` sidecar carries 4896–5185 ms, so
a loaded artifact reports its measured bake time.

The 2 m probe fallback:

```sh
./bin/harbagsa-bake --out build/bake/arena-2m.hbake --probe-spacing 2
```

| Measure | Value |
| -- | --: |
| Total | 3379 ms |
| Probe stage | 281 ms |
| Probes | 1200, 4 invalid and dilated |
| Artifact | 9,331,680 bytes |
| Peak RSS | 36.8 MB |

Thread scaling on the same machine: 1 thread 37496 ms, 4 threads 9810 ms,
8 threads 6277 ms, 12 threads 5779 ms, 16 threads 4989 ms. The 16-thread default
is the fastest measured setting.

**Failure.** The default bake misses the 2 s target by about 2.5x. The lightmap
stage alone is about 3.0 s. The measured 4.9–5.2 s is inside the 8 s
high-quality target, and the shipped 128-ray, 1024-probe quality is the only
quality the loader accepts. The 2 m fallback saves the probe stage but still
lands at 3.4 s. Closing the gap needs either a cheaper published quality preset
or a faster traversal; neither is in this change.

## Measurement fix

Before this change, a perf frame asked the harness for a zeroed capture, so
every measured frame read the colour target back and ran the per-pixel delta.
At 1280x720 that cost about 172 ms of CPU per frame, inflated the interval
`p50` to 172.6 ms against a 0.68 ms GPU total, and wrote 193 empty capture
entries into `report.json`. The perf frame now draws without a capture request:
the same run reports a 0.68 ms interval and no capture entries.

## Accepted limitations

- The bake is deterministic but not noise-free. At 128 lightmap rays the
  indirect is visibly mottled on large dim walls; the stair and junction
  captures show it. More rays reduce it linearly in time.
- The 2 s default bake target is missed; see above.
- The dynamic-lamp and moving-crate probes are interpolation-only. A crevice
  narrower than the 1 m probe spacing can still carry a small probe error; the
  sealed-cell crate moved 0.03/255 when a fixture was removed outside its view,
  which is the size of that error.
- A missing bake draws direct light only. It is a visible state, not a fallback:
  `state.bake.status` is `missing` and every indirect weight is zero.
