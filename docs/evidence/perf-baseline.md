# Performance baseline

The current baseline is the direct-light renderer measured on 2026-10-26 with AMD Radeon RX 9060 XT (RADV GFX1200). Use `scenarios/perf.json` for no lamps and `scenarios/perf-lamps.json` for eight synthetic lamps. Keep the extent and command sequence the same when comparing builds.

## Method

Each scenario runs one priming phase, 60 warmup frames, and 120 measured frames. Every measured frame steps the simulation once and draws once. Offscreen intervals measure throughput. A `--present` run measures display pacing instead.

The report separates five GPU passes: cluster, depth, scene, TAA, and overlay. It also reports CPU phases and frame intervals. GPU values belong to the last completed frame. A device without timestamp support reports CPU data only.

At 1280x720 on the baseline machine, the no-lamp GPU mean was 0.2628 ms. The eight-lamp GPU mean was 0.3911 ms. The detailed table and reproduction commands are in [point light performance](perf-lamps.md).

## Rules for a new baseline

- Record the machine, driver, extent, scenario, and run directory.
- Compare `p50` for the frame interval and inspect pass means for ownership.
- Use several runs for a performance claim. One run is a smoke check, not a stable budget.
- Do not compare present intervals with offscreen intervals.
- Do not commit traces or images unless the evidence guide explicitly needs them.

```sh
tools/make.sh build
./bin/harbagsa-agent run scenarios/perf.json --out runs/perf
./bin/harbagsa-agent run scenarios/perf-lamps.json --out runs/perf-lamps
```
