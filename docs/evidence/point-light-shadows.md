# Point-light shadows evidence

Captured on 2026-10-27 with AMD Radeon RX 9060 XT (RADV GFX1200), Mesa 26.2.5.
The decision is [ADR 0040](../adr/0040-hard-point-light-shadows.md).

## Blocked surface

`scenarios/shadows.json` removes the starting lamps, places one warm lamp behind
a pillar, and captures the same arena wall twice: once with shadows and once
without. Values are green-channel means at 1280x720.

| Capture | Mean | Change from previous |
| --- | ---: | ---: |
| Shadows on | 119.18 | -- |
| Shadows off | 131.02 | +15.79 |

The blocked wall is darker with shadows. The two captures have different render
digests. The render digest change is expected because the paired switch is a
render input.

## Moving lamp

`scenarios/shadow-move.json` starts from the same blocked wall and moves the lamp
from `x = -1, z = -15` to `x = -3, z = -16` through the editor.

| Capture | Mean | Change from previous |
| --- | ---: | ---: |
| Before move | 119.18 | -- |
| After move | 102.24 | +59.23 |

The shadow and the light field follow the lamp. The render digest also changes.

## Lamp on a wall

`scenarios/lamp-wall-plane.json` places a lamp on the wall plane. The on and off
captures must match, because the lamp housing is excluded and the shadow ray
stops short of the light.

| Comparison | Value |
| --- | ---: |
| On vs off delta | 0.000004 |
| Wall region mean | 157.87 |

The wall gradient check stays below `1.0`. A fan of shadow lines would fail.

## 96-light cost

`scenarios/perf-shadows.json` injects 96 synthetic lights at 1920x1080 and runs
120 measured frames after 60 warmup frames. It runs shadows on, then off, in one
run. The table is the median of three runs.

| Pass or pair | Shadows on | Shadows off | Paired difference |
| --- | ---: | ---: | ---: |
| TLAS | 0.260 ms | 0.000 ms | +0.260 ms |
| Scene | 5.655 ms | 1.080 ms | +4.567 ms |
| GPU total | 6.454 ms | 1.648 ms | +4.806 ms |

The paired difference includes the TLAS pass and the shadow rays. The scene pass
includes the depth prepass. The 96-light grid is a dense worst case for overlap,
not a typical room. The current result is higher than the older research build:
the current renderer measures 4.57 ms of shadow work at this scale. It still fits
a 60 Hz frame on this GPU, but it is the budget to watch.

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
