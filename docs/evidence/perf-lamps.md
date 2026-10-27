# Point light performance

Measured on 2026-10-27 with AMD Radeon RX 9060 XT (RADV GFX1200). `scenarios/perf-lamps.json` injects eight synthetic lights through the renderer debug override. The baseline is the starting scene from `scenarios/perf.json`, with three dynamic lamps, at the same 1280x720 extent.

## Results

All values are mean milliseconds over 120 measured frames after 60 warmup frames.

| Pass | Starting scene | Eight direct lights |
| --- | ---: | ---: |
| Cluster | 0.0158 | 0.0147 |
| Depth | 0.0158 | 0.0177 |
| Scene | 0.0775 | 0.0859 |
| TAA | 0.1565 | 0.2712 |
| Overlay | 0.0015 | 0.0016 |
| GPU total | 0.2672 | 0.3911 |

The scene pass rises by 0.0084 ms with eight synthetic lights against the three starting lamps. The cluster assignment is within run variance. The TAA difference belongs to the changed input and run variance, not a second lighting pass. There are no other lighting passes in the report.

## Reproduce

```sh
tools/make.sh build
./bin/harbagsa-agent run scenarios/perf.json --out runs/perf
./bin/harbagsa-agent run scenarios/perf-lamps.json --out runs/perf-lamps
jq '.perf[0].gpu' runs/perf/report.json
jq '.perf[0].gpu' runs/perf-lamps/report.json
```

`trace-direct.jsonl` holds the lamp run's per-frame samples in its run directory. Do not use these numbers as a cross-machine budget.
