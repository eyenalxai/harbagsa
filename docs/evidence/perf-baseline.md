# Performance baseline

> Historical note: this baseline predates the TLAS pass, point-light shadows,
> and absolute darkness. It records an old measurement, not a current gate.

The baseline is the direct-light renderer measured on 2026-10-26 with AMD
Radeon RX 9060 XT (RADV GFX1200). Use `scenarios/perf.json` for the default view
and `scenarios/perf-arena.json` for the arena from above. Keep the extent and
command sequence the same when comparing builds.

## Method

Each scenario runs one priming phase, 60 warmup frames, and 120 measured frames.
Every measured frame steps the simulation once and draws once. Offscreen
intervals measure throughput. A `--present` run measures display pacing instead.

At that time the report separated five GPU passes: cluster, depth, scene, TAA,
and overlay. The current pass list is TLAS, cluster, probe, depth, scene, TAA,
and overlay. It also reports CPU phases and frame intervals. GPU values belong
to the last completed frame. A device without timestamp support reports CPU data
only.

At 1280x720 on the baseline machine, the starting scene's GPU mean was
0.2672 ms.

## Rules for a new baseline

- Record the machine, driver, extent, scenario, and run directory.
- Compare `p50` for the frame interval and inspect pass means for ownership.
- Use several runs for a performance claim. One run is a smoke check, not a
  stable budget.
- Do not compare present intervals with offscreen intervals.
- Do not commit traces or images.

```sh
tools/make.sh build
./bin/harbagsa-agent run scenarios/perf.json --out runs/perf
./bin/harbagsa-agent run scenarios/perf-arena.json --out runs/perf-arena
```
