# DDGI probe volumes

## Method

Each probe traces 256 deterministic rays every frame. The ray pass stores
radiance and hit distance in a per-frame ray buffer. A blend pass runs one thread
per 8 x 8 octahedral texel and accumulates every ray with a cosine kernel:
irradiance is `sum(radiance * cos) / (2 * sum(cos))` and the depth pair is
`sum(distance * cos^50) / (2 * sum(cos^50))` plus the squared-distance moment.
Irradiance is gamma encoded with a 5.0 exponent; the gather decodes it.

The gather reads irradiance with `oct(surface normal)` and depth with
`oct(world - probe)`, samples both bilinearly, applies the wrap backface weight
and the Chebyshev depth test, then multiplies the `2 pi` hemisphere factor and
divides by `pi` for the diffuse BRDF. A light or sun change resets the blend; a
texel delta above 0.25 also replaces the texel.

## Scenario

`scenarios/ddgi.json` puts the camera in the chamber, moves the sun below the
horizon, and places one lamp. It captures the same view with the probe indirect
term on and off. The off frame still shows the direct lamp, so the difference is
the bounce. It then captures the same view with ambient occlusion on and off
while GI stays on.

```sh
make shot SCENARIO=ddgi OUT=runs/ddgi
```

The room has one probe volume: 10 x 3 x 10 probes at 1.04 m spacing. Probes
inside a box are pushed out along the shallowest local axis before the rays run.

## Result

| Capture | Mean green |
| --- | ---: |
| `gi-on` | 181.25 |
| `gi-off` | 123.78 |
| `ao-on` | 181.24 |
| `ao-off` | 184.49 |

The scenario checks `probe_count`, `probe_volume_count`, `probe_energy`, the
GI on/off order, and the AO on/off order: 10 checks, 0 failed. The probe energy
is 0.179 in linear irradiance. The four captures are deterministic: a repeat run
produces the same PNG hashes.

The room gate is `scenarios/room-lighting.json`: 23 checks, 0 failed. The first
lane is 39.67 mean green under the west sun and 8.07 under the east sun. The
east value is transport through the connected four-turn light lock, not a wall
leak. The chamber is 0.94 to 0.99 under the sun alone, 181.52 with the lamp, and
0.94 after the lamp is removed. The chamber is dim but not black because the
indirect field carries the sun bounce through the lock.

## Leak pair

`scenarios/ddgi-leak.json` puts the camera in the first lane, with the sun below
the horizon. It captures the lane before the lamp and after a lamp is placed in
the chamber.

| Capture | Mean green |
| --- | ---: |
| `lane-dark` | 49.38 |
| `lane-lit` | 49.39 |
| `chamber-lit` | 181.24 |

The lane moves by 0.005, inside the gate's 50.0 absolute ceiling, and the
chamber is bright. The scenario has 3 checks, 0 failed.

This is not a sealed leak pair. The chamber and the lane are connected by the
four-turn light lock, so light through the lock is transport, not a bug. The
sealed two-room pair is issue #321.

## Doorway and moving lamp

`scenarios/ddgi-door.json` looks through the room's west door with the sun below
the horizon. The doorway admits the lamp: mean green rises from 43.28 to 85.37.
Five checks pass, including the placed lamp identity.

`scenarios/ddgi-move.json` places the lamp in the chamber, then moves it with the
editor. Both views stay above 120 mean green: 187.73 before and 172.23 after.
The object position checks and both light checks pass; 4 checks.

## Contact term

Ambient occlusion multiplies direct light only. The indirect term has its own
probe visibility, so multiplying it by AO would count the corner twice. In the
same chamber view, turning AO off raises mean green from 181.24 to 184.49 while
the probe atlas is unchanged. The decision is recorded in
`docs/adr/0032-direct-ao-and-probe-indirect.md`.

## Cost

`scenarios/perf-probes.json` uses 64 synthetic lights and the chamber camera at
1280 x 720. The probe pass covers the ray trace and the blend. It costs 0.232 ms
with 64 rays and 0.413 ms with 256 rays. The 256-ray full GPU pass set is:

| Pass | ms |
| --- | ---: |
| TLAS | 0.281 |
| Cluster | 0.033 |
| Probe | 0.413 |
| Depth | 0.016 |
| Scene | 2.874 |
| Sky | 0.004 |
| TAA | 0.232 |
| Overlay | 0.002 |
| Total | 3.855 |

## Limits

The volume covers the room, its lane network, and the chamber as one grid. It
does not classify probes into disconnected rooms. The open arena and the sky
have no probe volume, so the arena indirect term is still zero; that is issue
#321. The sealed two-room leak pair is issue #322.

The probe atlas stores encoded irradiance and depth moments. Moving geometry
relocates probe centres but does not reset the irradiance blend; a crate that
moves inside a lit room keeps its old indirect until the blend converges.

There is no path-traced reference in this change. It needs a scene and a
tolerance design that compares a multi-bounce reference with the one-bounce
probe field. It is a follow-up on issue #320.
