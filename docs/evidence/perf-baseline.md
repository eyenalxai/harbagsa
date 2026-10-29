# Performance baseline

> Historical note: the first baseline predates the TLAS pass, point-light
> shadows, and absolute darkness. It records an old measurement, not a current
> gate. The current baseline follows it.

## Current baseline

Measured on 2026-10-29 on AMD Ryzen 7 5700X (8 cores, 16 threads) with an AMD
Radeon RX 9060 XT (RADV GFX1200), Mesa 26.2.5-arch1.1, Vulkan 1.4.354. The build
is `f2bc300` plus the perf-readback fix described below. The lighting is the
mixed static baked indirect and dynamic direct system from
[ADR 0045](../adr/0045-mixed-static-baked-indirect.md); the quality evidence is
in [mixed-lighting.md](mixed-lighting.md).

The GPU passes are TLAS, cluster, depth, scene, TAA, and overlay. There is no
probe pass. The report carries `p50`, `p95`, and `mean` for each CPU phase and
GPU pass. GPU values belong to the last completed frame. A device without
timestamp support reports CPU data only.

Each scenario runs one priming phase, 60 warmup frames, and 120 measured frames
offscreen. The GPU total is the sum of the six passes. Three runs for the 720p
scenarios, two for the 96-light run:

| Scenario | Extent | GPU total p50 | GPU total p95 | Scene pass p50 | TLAS p50 | Interval p50 |
| -- | -- | --: | --: | --: | --: | --: |
| `scenarios/perf.json` | 1280x720 | 0.427 ms | 0.434 ms | 0.120 ms | 0.198 ms | 0.700 ms |
| `scenarios/perf-arena.json` | 1280x720 | 0.383 ms | 0.389 ms | 0.089 ms | 0.198 ms | 0.657 ms |
| `scenarios/perf-mixed.json` (96 lights) | 1920x1080 | 1.516 ms | 1.576 ms | 1.103 ms | 0.108 ms | 1.839 ms |

The spread across the three runs was under 0.005 ms at 720p and under 0.012 ms
at 1080p, so the table lists the median run. The 96-light row quotes `mixed-2`,
the last mixed window in the scenario; `scenarios/perf-mixed.json` brackets each
term with direct windows so the term costs are measurable at all. The interval is the GPU total plus the
submit and present cost; it is not display pacing.

```sh
tools/make.sh build
./bin/harbagsa-agent run scenarios/perf.json --out runs/perf
./bin/harbagsa-agent run scenarios/perf-arena.json --out runs/perf-arena
./bin/harbagsa-agent run scenarios/perf-mixed.json --out runs/perf-mixed
```

`scenarios/perf-mixed.json` measures both indirect terms, each alone, and
neither in one device. Run it twice before quoting a delta: the first window is
the clock ramp and the per-term differences are at the 0.01–0.02 ms noise floor.

### Readback fix

Before this change a perf frame passed a zeroed capture request to the draw
path, so every measured frame read the colour target back and ran the per-pixel
delta. `scenarios/perf.json` at 1280x720 reported an interval `p50` of 173.1 ms
against a 0.68 ms GPU total and wrote 193 empty capture entries
(`runs/perf-baseline`). After the fix the same scenario reports 0.692–0.700 ms
`p50` and no capture entries (`runs/perf-720-1` to `runs/perf-720-3`). Do not compare
an interval measured before this fix with one measured after it.

### Rules for a new baseline

- Record the machine, driver, extent, scenario, and run directory.
- Compare `p50` for the frame interval and inspect pass means for ownership.
- Use several runs for a performance claim. One run is a smoke check, not a
  stable budget.
- Do not compare present intervals with offscreen intervals.
- Do not commit traces or images.

## First baseline (historical)

The first baseline was the direct-light renderer measured on 2026-10-26 with the
same GPU. At 1280x720 the starting scene's GPU mean was 0.2672 ms. The report
separated five GPU passes: cluster, depth, scene, TAA, and overlay. It is kept
only as history; the pass list, the shadow pass, and the indirect terms have all
changed since.
