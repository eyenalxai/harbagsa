# Point light performance

Measured on 2026-10-26 with AMD Radeon RX 9060 XT (RADV GFX1200). `scenarios/perf-lamps.json` injects eight synthetic lights through the renderer debug override. The baseline is `scenarios/perf.json` at the same 1280x720 extent.

## Results

All values are mean milliseconds over 120 measured frames after 60 warmup frames.

| Pass | No lights | Eight direct lights |
| --- | ---: | ---: |
| Cluster | 0.0083 | 0.0147 |
| Depth | 0.0181 | 0.0177 |
| Scene | 0.0611 | 0.0859 |
| TAA | 0.1736 | 0.2712 |
| Overlay | 0.0017 | 0.0016 |
| GPU total | 0.2628 | 0.3911 |

The scene pass rises by 0.0248 ms with eight lights. The cluster assignment also rises because it has work to do. The TAA difference belongs to the changed input and run variance, not a second lighting pass. There are no other lighting passes in the report.

## Reproduce

```sh
tools/make.sh build
./bin/harbagsa-agent run scenarios/perf.json --out runs/perf
./bin/harbagsa-agent run scenarios/perf-lamps.json --out runs/perf-lamps
jq '.perf[0].gpu' runs/perf/report.json
jq '.perf[0].gpu' runs/perf-lamps/report.json
```

`trace-direct.jsonl` holds the lamp run's per-frame samples in its run directory. Do not use these numbers as a cross-machine budget.
