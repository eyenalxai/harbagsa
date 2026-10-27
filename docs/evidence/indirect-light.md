# Indirect-light evidence

Captured on 2026-10-27 with AMD Radeon RX 9060 XT (RADV GFX1200), Mesa 26.2.5.
The decision is [ADR 0042](../adr/0042-single-volume-ddgi.md). The field is one
2 m volume with 64 rays per probe and one diffuse bounce. Values are 8-bit
channel means at 1280x720 unless the section says otherwise.

## Bounce around a corner

`scenarios/gi.json` places one warm lamp beside a pillar and captures the same
frame with the probe field on and off. The zero fraction is the share of pixels
with no light at all; it is the direct-only black area that the bounce fills.

| Capture | Red | Green | Blue | Zero fraction |
| --- | ---: | ---: | ---: | ---: |
| GI on | 146.10 | 123.80 | 83.69 | 0.000 |
| GI off | 123.15 | 98.66 | 67.98 | 0.239 |

The bounce raises every channel and removes the black region. The two render
digests differ because `gi` is a render input. The same scenario repeats the
pair with shadows off, so the probe pass still builds and traces the TLAS when
only GI needs it.

## Lamp-free darkness

`scenarios/gi-dark.json` removes the three starting lamps and leaves GI on. The
mean is 0.165 on every channel and the zero fraction is 0.835. The value is the
same as the direct-only baseline. GI does not invent a light.

## Moving lamp

`scenarios/gi-move.json` moves one lamp from the left side of the pillar to the
right. Both positions pair GI on and off.

| Capture | Green mean | GI gain |
| --- | ---: | ---: |
| Left, GI on | 66.12 | -- |
| Left, direct | 49.42 | +16.70 |
| Right, GI on | 162.93 | -- |
| Right, direct | 147.80 | +15.13 |

The moved lamp changes the bounce and the render digest.

## Sealed wall

`scenarios/gi-sealed.json` builds a closed room from four walls and the arena
shell, places the lamp outside, and puts the camera inside. GI on and GI off
must match because no lamp reaches the room.

| Capture | Green mean | Zero fraction | Delta from GI on |
| --- | ---: | ---: | ---: |
| GI on | 0.165 | 0.834 | -- |
| GI off | 0.165 | 0.835 | 0.0004 |

The small delta is TAA noise, not a bounce. An earlier version leaked through the
thin wall because a probe on the far side agreed on depth; the gather now rejects
a probe behind the surface.

## 96-light cost

`scenarios/perf-gi.json` injects 96 synthetic lights at 1920x1080 and runs 120
measured frames after 60 warmup frames. It measures GI on, then GI off. The table
is the median of three paired runs.

| Pass or pair | GI on | GI off | Paired difference |
| --- | ---: | ---: | ---: |
| Probe | 0.759 ms | 0.000 ms | +0.759 ms |
| Scene | 6.577 ms | 6.001 ms | +0.576 ms |
| GPU total | 8.128 ms | 6.835 ms | +1.293 ms |

The probe pass is one compute dispatch pair: 1200 probes, 64 rays each. The scene
difference is the eight-probe gather in the lit pass. The paired full-frame cost
is about 1.29 ms at the 96-light target, and the full frame is 8.13 ms on this
GPU. The shadow and probe budgets fit one 60 Hz frame together.

## Reproduce

```sh
tools/make.sh build
./bin/harbagsa-agent suite lighting --out runs/lighting
./bin/harbagsa-agent run scenarios/perf-gi.json --debug-renderer \
  --out runs/gi/perf-96
jq '.perf[].gpu' runs/gi/perf-96/report.json
```

The run directories hold the PNGs. The repository does not commit images.
