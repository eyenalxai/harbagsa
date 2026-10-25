# DDGI probe volumes

## Scenario

`scenarios/ddgi.json` puts the camera in the chamber, moves the sun below the
horizon, and places one lamp. It captures the same view with the probe indirect
term on and off. The off frame still shows the direct lamp, so the difference is
the bounce. It then captures the same view with ambient occlusion on and off
while GI stays on.

```sh
make shot SCENARIO=ddgi OUT=runs/ddgi
```

The room has one probe volume: 10 x 3 x 10 probes at 1.04 m spacing. Each probe
traces 64 rays per frame, stores 8 x 8 octahedral irradiance and depth moments,
and blends with alpha 0.25. A light or sun change makes the next frame a full
replace. Probes inside a box are pushed out along the shallowest local axis
before the rays run.

## Result

| Capture | Mean green |
| --- | ---: |
| `gi-on` | 163.27 |
| `gi-off` | 123.78 |
| `ao-on` | 163.71 |
| `ao-off` | 166.87 |

The scenario checks `probe_count`, `probe_volume_count`, `probe_energy`, the
GI on/off order, and the AO on/off order: 10 checks, 0 failed. The four captures
are deterministic: a repeat run produces the same PNG hashes.

The room gate is still `scenarios/room-lighting.json`: the chamber is at the
output dither floor before the lamp, 163.30 with the lamp, and 0.19 after it is
removed. All 18 room checks pass.

## Leak pair

`scenarios/ddgi-leak.json` puts the camera in the first lane, with the sun below
the horizon. It captures the lane before the lamp and after a lamp is placed in
the chamber. The lane wall is solid; the only route is the four-turn light
lock, which one bounce does not cross.

| Capture | Mean green |
| --- | ---: |
| `lane-dark` | 49.38 |
| `lane-lit` | 49.39 |
| `chamber-lit` | 163.72 |

The lane moves by 0.005, inside the gate's 50.0 absolute ceiling. The chamber is
bright. The scenario has 3 checks, 0 failed.

## Doorway and moving lamp

`scenarios/ddgi-door.json` looks through the room's west door with the sun below
the horizon. The doorway admits the lamp: mean green rises from 41.25 to 85.27.
Five checks pass, including the placed lamp identity.

`scenarios/ddgi-move.json` places the lamp in the chamber, then moves it with the
editor. Both views stay above 120 mean green: 175.20 before and 136.74 after.
The object position checks and both light checks pass; 4 checks.

## Contact term

Ambient occlusion multiplies direct light only. The indirect term has its own
probe visibility, so multiplying it by AO would count the corner twice. In the
same chamber view, turning AO off raises mean green from 163.71 to 166.87 while
the probe atlas is unchanged. The decision is recorded in
`docs/adr/0032-direct-ao-and-probe-indirect.md`.

## Cost

`scenarios/perf-probes.json` uses 64 synthetic lights and the chamber camera at
1280 x 720. The probe pass is 0.154 ms. The full GPU pass set is:

| Pass | ms |
| --- | ---: |
| TLAS | 0.258 |
| Cluster | 0.033 |
| Probe | 0.154 |
| Depth | 0.014 |
| Scene | 2.332 |
| Sky | 0.004 |
| TAA | 0.123 |
| Overlay | 0.001 |
| Total | 2.919 |

## Limits

The volume covers the room, its lane network, and the chamber as one grid. It
does not classify probes into disconnected rooms; the current room network is
connected, and the solid-wall leak stays at the noise floor. A larger building
with several closed volumes will add one volume per room. Moving geometry
relocates probe centres but does not reset the radiance blend; a crate that moves
inside a lit room keeps its old indirect until the blend converges.
