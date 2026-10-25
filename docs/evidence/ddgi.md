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

The room volume is 10 x 3 x 10 probes at 1.04 m spacing. Five arena volumes
follow it: a roof volume and four perimeter strips at a 4 m cell, with a 2.775 m
cell for the north strip. Probes inside a box are pushed out along the shallowest
local axis before the rays run. The layout and the leak argument are in
`docs/adr/0034-ddgi-arena-coverage.md`.

## Result

| Capture | Mean green |
| --- | ---: |
| `gi-on` | 183.12 |
| `gi-off` | 123.78 |
| `ao-on` | 183.11 |
| `ao-off` | 186.26 |

The scenario checks `probe_count`, `probe_volume_count`, `probe_energy`, the
GI on/off order, and the AO on/off order: 10 checks, 0 failed. The probe energy
is 0.137 over the whole atlas with the lamp on, down from 0.177 for the room grid
alone; the arena sky fill is dimmer than the lamp-lit room. The four captures are
deterministic: a repeat run produces the same PNG hashes.

The room gate is `scenarios/room-lighting.json`: 19 checks, 0 failed. The first
lane is 39.75 mean green under the west sun and 8.08 under the east sun. The
east value is transport through the connected four-turn light lock, not a wall
leak. The chamber is 0.18 to 0.26 under the sun alone, 183.10 with the lamp, and
0.26 after the lamp is removed. A backface ray no longer leaks into the sealed
end of the lock.

## Leak pair

`scenarios/ddgi-leak.json` puts the camera in the first lane at the door,
looking out into the arena, with the sun below the horizon. It captures the view
before the lamp and after a lamp is placed in the chamber.

| Capture | Mean green |
| --- | ---: |
| `lane-dark` | 105.74 |
| `lane-lit` | 105.74 |
| `chamber-lit` | 183.11 |

The camera looks out of the room door, so the frame holds the sky-lit arena and
the mean rose with coverage from 49.38. The lane moves by 0.0035 when the lamp
turns on, inside the gate's 0.05 tolerance, and the chamber is bright. The gate
is now the lane delta rather than an absolute ceiling, because the outdoor part
of the frame is no longer black. The scenario has 3 checks, 0 failed.

This is not a sealed leak pair. The chamber and the lane are connected by the
four-turn light lock, so light through the lock is transport, not a bug. The
sealed two-room pair is issue #322.

## Doorway and moving lamp

`scenarios/ddgi-door.json` looks through the room's west door with the sun below
the horizon. The doorway admits the lamp: mean green rises from 43.28 to 85.38.
Five checks pass, including the placed lamp identity.

`scenarios/ddgi-move.json` places the lamp in the chamber, then moves it with the
editor. Both views stay above 120 mean green: 189.55 before and 173.72 after.
The object position checks and both light checks pass; 4 checks.

## Arena and roof

`scenarios/ddgi-arena.json` uses the `outside` camera from `room-lighting`. The
room's west face is in full shade, so the only term that can lift it is indirect.
The scenario measures a 140 x 80 pixel window inside that face with a pure-black
colour key, writes a 4x crop, and then repeats the chamber view from
`room-lighting`.

| Capture | Before | After |
| --- | ---: | ---: |
| `outside` pure-black pixels | 26.8% | 0.30% |
| shaded face pure-black pixels | 83.8% | 0.0% |
| shaded face mean green | 0.16 | 151.27 |
| chamber mean green | 0.26 | 0.26 |

The remaining 0.30% of the frame is the room doorway, which is the unlit
interior. The shaded face is a smooth sky gradient with soft 4 m probe blotches,
not the old black. The chamber keeps its value because the room volume comes
first and the arena bounds stop at the room's outer wall; the arena probes add
no light to a room or a lane through a wall.

The scenario has 7 checks, 0 failed:

```sh
make shot SCENARIO=ddgi-arena OUT=runs/ddgi-arena
```

```sh
./bin/harbagsa-agent checks runs/ddgi-arena
```

## Contact term

Ambient occlusion multiplies direct light only. The indirect term has its own
probe visibility, so multiplying it by AO would count the corner twice. In the
same chamber view, turning AO off raises mean green from 183.11 to 186.26 while
the probe atlas is unchanged. The decision is recorded in
`docs/adr/0032-direct-ao-and-probe-indirect.md`.

## Cost

`scenarios/perf-probes.json` uses 64 synthetic lights and the chamber camera at
1280 x 720. The probe pass covers the ray trace and the blend. It costs 0.232 ms
with 64 rays, 0.413 ms with 256 rays and 300 room probes, and 0.672 ms with 256
rays and 537 probes after arena coverage. The 537-probe full GPU pass set is:

| Pass | ms |
| --- | ---: |
| TLAS | 0.291 |
| Cluster | 0.034 |
| Probe | 0.672 |
| Depth | 0.016 |
| Scene | 2.767 |
| Sky | 0.004 |
| TAA | 0.231 |
| Overlay | 0.002 |
| Total | 4.017 |

## Limits

The room, its lane network, and the chamber share one grid, and that grid does
not classify probes into disconnected rooms. The arena grid is coarse, so the
perimeter walls show soft 4 m blotches. The sealed two-room leak pair is issue
#322.

The probe atlas stores encoded irradiance and depth moments. Moving geometry
relocates probe centres but does not reset the irradiance blend; a crate that
moves inside a lit room keeps its old indirect until the blend converges.

There is no path-traced reference in this change. It needs a scene and a
tolerance design that compares a multi-bounce reference with the one-bounce
probe field. It is a follow-up on issue #320.
