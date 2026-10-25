# DDGI probe volume

## Scenario

`scenarios/ddgi.json` puts the camera in the chamber, moves the sun below the
horizon, and places one lamp. It captures the same view with the probe indirect
term on and off. The off frame still shows the direct lamp, so the difference is
the bounce.

```sh
make shot SCENARIO=ddgi OUT=runs/ddgi
```

The room has one probe volume: 10 x 3 x 10 probes at 1.04 m spacing. Each probe
traces 64 rays per frame, stores 8 x 8 octahedral irradiance and depth moments,
and blends with alpha 0.25. A light or sun change makes the next frame a full
replace.

## Result

| Capture | Mean green |
| --- | ---: |
| `gi-on` | 162.55 |
| `gi-off` | 123.78 |

The scenario checks `probe_count`, `probe_volume_count`, `probe_energy`, and that
the on frame is brighter: 8 checks, 0 failed. The two captures are deterministic:
a repeat run produces the same PNG hashes.

The room gate is still `scenarios/room-lighting.json`: the chamber is at the
output dither floor before the lamp, 162.61 with the lamp, and 0.19 after it is
removed. All 18 room checks pass.

## Cost

`scenarios/perf-probes.json` uses 64 synthetic lights and the chamber camera at
1280 x 720. The probe pass is 0.116 ms. The full GPU pass set is:

| Pass | ms |
| --- | ---: |
| TLAS | 0.288 |
| Cluster | 0.033 |
| Probe | 0.116 |
| Depth | 0.015 |
| Scene | 2.679 |
| Sky | 0.004 |
| TAA | 0.116 |
| Overlay | 0.001 |
| Total | 3.252 |

## Limits

The volume covers the room, its lane network, and the chamber as one grid. It
does not yet relocate probes out of geometry, classify probes by room, or reset
on moving boxes. A thin internal wall can leak a probe from the lit side to the
dark side. The leak pair, doorway gate, and contact-term decision are ticket
#312.
