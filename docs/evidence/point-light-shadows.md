# Point-light shadows evidence

Captured on 2026-10-27 with AMD Radeon RX 9060 XT (RADV GFX1200), Mesa 26.2.5.
The decision is [ADR 0040](../adr/0040-hard-point-light-shadows.md). The shadow scenarios set `gi: false` so the probe field does not enter these numbers.

## Blocked surface

`scenarios/shadows.json` removes the starting lamps, places one warm lamp behind
a pillar, and captures the same arena wall twice: once with shadows and once
without. Values are green-channel means at 1280x720.

| Capture | Mean | Change from previous |
| --- | ---: | ---: |
| Shadows on | 98.65 | -- |
| Shadows off | 113.63 | +19.78 |

The blocked wall is darker with shadows. The two captures have different render
digests. The render digest change is expected because the paired switch is a
render input.

## Moving lamp

`scenarios/shadow-move.json` starts from the same blocked wall and moves the lamp
from `x = -1, z = -15` to `x = -3, z = -16` through the editor.

| Capture | Mean | Change from previous |
| --- | ---: | ---: |
| Before move | 98.65 | -- |
| After move | 76.19 | +73.67 |

The shadow and the light field follow the lamp. The render digest also changes.

## Lamp on a wall

`scenarios/lamp-wall-plane.json` places a lamp on the wall plane. The on and off
captures must match, because the lamp housing is excluded and the shadow ray
stops short of the light.

| Comparison | Value |
| --- | ---: |
| On vs off delta | 0.0000065 |
| Wall region mean | 153.11 |

The wall gradient check stays below `1.0`. A fan of shadow lines would fail.

## 96-light cost

`scenarios/perf-shadows.json` injects 96 synthetic lights at 1920x1080 and runs
120 measured frames after 60 warmup frames. It runs shadows on, then off, in one
run. The table is the median of three runs.

| Pass or pair | Shadows on | Shadows off | Paired difference |
| --- | ---: | ---: | ---: |
| TLAS | 0.295 ms | 0.000 ms | +0.295 ms |
| Scene | 5.092 ms | 1.138 ms | +3.954 ms |
| GPU total | 5.935 ms | 1.649 ms | +4.286 ms |

The scenario sets `gi: false` so the probe field does not enter the shadow
budget. The paired difference includes the TLAS pass and the shadow rays. The
scene pass includes the depth prepass. The 96-light grid is a dense worst case
for overlap, not a typical room. The current renderer measures 4.29 ms of shadow
work at this scale. It still fits a 60 Hz frame on this GPU, but it is the budget
to watch.

Run it with:

```sh
tools/make.sh build
./bin/harbagsa-agent run scenarios/perf-shadows.json --debug-renderer \
  --out runs/shadows/perf-96
jq '.perf[].gpu' runs/shadows/perf-96/report.json
```

## Reproduce

```sh
tools/make.sh build
./bin/harbagsa-agent run scenarios/shadows.json --debug-renderer --out runs/shadows/blocked
./bin/harbagsa-agent run scenarios/shadow-move.json --debug-renderer --out runs/shadows/move
./bin/harbagsa-agent run scenarios/lamp-wall-plane.json --debug-renderer --out runs/shadows/wall
./bin/harbagsa-agent suite lighting --out runs/shadows/lighting
```

The run directories hold the PNGs. The repository does not commit images.
