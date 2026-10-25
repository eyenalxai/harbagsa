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
divides by `pi` for the diffuse BRDF. The reference 5 percent Chebyshev floor
stays; a fully occluded probe still contributes a small fallback. The sealed
pair uses one volume per room, so a probe across the shared wall is never in the
surface's eight-probe cage. A light or sun change resets the blend; a texel delta
above 0.25 also replaces the texel.

## Scenario

`scenarios/ddgi.json` puts the camera in the chamber, moves the sun below the
horizon, and places one lamp. It captures the same view with the probe indirect
term on and off. The off frame still shows the direct lamp, so the difference is
the bounce. It then captures the same view with ambient occlusion on and off
while GI stays on.

```sh
make shot SCENARIO=ddgi OUT=runs/ddgi
```

The room volume is 10 x 3 x 10 probes at 1.04 m spacing. The two sealed-pair
volumes come next: 4 x 3 x 4 probes per room at 1 m spacing. Five arena volumes
follow them: a roof volume and four perimeter strips at a 4 m cell, with a
2.775 m cell for the north strip. Probes inside a box are pushed out
along the shallowest local axis before the rays run. The layout and the leak
argument are in `docs/adr/0034-ddgi-arena-coverage.md`.

## Result

| Capture | Mean green |
| --- | ---: |
| `gi-on` | 183.12 |
| `gi-off` | 123.78 |
| `ao-on` | 183.11 |
| `ao-off` | 186.26 |

The scenario checks `probe_count`, `probe_volume_count`, `probe_energy`, the
GI on/off order, and the AO on/off order: 10 checks, 0 failed. The probe energy
is 0.127 over the whole atlas with the lamp on. The arena sky fill is dimmer than
the lamp-lit room. The four captures are deterministic: a repeat run produces
the same PNG hashes.

The room gate is `scenarios/room-lighting.json`: 19 checks, 0 failed. The first
lane is 39.75 mean green under the west sun and 8.08 under the east sun. The
east value is transport through the connected four-turn light lock, not a wall
leak. The chamber is 0.18 to 0.26 under the sun alone, 183.10 with the lamp, and
0.26 after the lamp is removed. A backface ray no longer leaks into the sealed
end of the lock.

## Sealed pair

`scenarios/ddgi-sealed.json` builds the pair from eight static placed Walls and
two Platform roofs at (-10, -8). Room A holds a warm lamp at intensity 4 and
range 12. The camera sits in room B behind the solid shared wall. The same run
captures the wall before and after the lamp, then removes the placed door
segment from the shared wall and captures the doorway and the far wall.

The pair has one 4 x 3 x 4 probe grid per room at 1 m spacing. The shared wall
sits between the two grids, so a room B surface samples only room B probes.
Before the split, one cross-room grid put a bright room A probe in the room B
cage; the reference 5 percent Chebyshev floor kept part of it:

| Capture | One cross-room grid | One volume per room |
| --- | ---: | ---: |
| `sealed-wall` mean green | 0.168 | 0.168 |
| `sealed-wall` max green | 1 | 1 |
| `sealed-lamp` mean green | 0.415 | 0.165 |
| `sealed-lamp` max green | 84 | 1 |
| `sealed-depth` max depth | 0.9827 | 0.9827 |
| `sealed-far` mean green | 0.165 | 0.165 |

With one volume per room the lamp adds nothing to room B: the sealed wall and
far wall both sit at the dither floor, and the depth target stays below 0.999.
The lamp changes the room A probes, not room B. The 5 percent floor stays in the
gather.

Removing the door segment is transport, and the same run gates it:

| Capture | Mean green |
| --- | ---: |
| `sealed-far` | 0.165 |
| `door-far` | 85.20 |
| `door-near` | 155.14 |

The far wall is in the shadow of the remaining shared wall: the direct lamp line
crosses the solid part, so the far-wall lift comes through the opening and the
probe field. It is brighter than the sealed baseline and dimmer than the doorway.
That ordering is the doorway gate, not a wall leak. The scenario has 17 checks,
0 failed.

The old `ddgi-leak` scenario is retired. Its camera looked out of the room door,
and the chamber and lane are connected by the four-turn light lock, so it never
tested a solid wall.

## Doorway and moving lamp

`scenarios/ddgi-door.json` looks through the room's west door with the sun below
the horizon. The doorway admits the lamp: mean green rises from 96.08 to 142.81.
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
not the old black. The chamber stays at the dither floor because the room volume
comes first and the arena bounds stop at the room's outer wall; the arena probes
add no light to a room or a lane through a wall.

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
with 64 rays, 0.413 ms with 256 rays and 300 room probes, 0.672 ms with 256 rays
and 537 probes after arena coverage, and 0.735 ms with 256 rays and 633 probes
after the sealed pair. The 633-probe full GPU pass set is:

| Pass | ms |
| --- | ---: |
| TLAS | 0.277 |
| Cluster | 0.033 |
| Probe | 0.735 |
| Depth | 0.014 |
| Scene | 2.729 |
| Sky | 0.004 |
| TAA | 0.144 |
| Overlay | 0.002 |
| Total | 3.937 |

## Limits

The room, its lane network, and the chamber share one grid, and that grid does
not classify probes into disconnected rooms. The sealed pair uses two 1 m grids,
one per room, so a room B surface never samples a room A probe. A larger
building still needs a volume authoring and classification scheme. The arena grid
is coarse, so the perimeter walls show soft 4 m blotches.

The probe atlas stores encoded irradiance and depth moments. Moving geometry
relocates probe centres but does not reset the irradiance blend; a crate that
moves inside a lit room keeps its old indirect until the blend converges.

The path-traced reference is [`docs/evidence/ddgi-reference.md`](ddgi-reference.md).
It measures the probe field against a 3-bounce CPU estimator and fails the
current tree: the probe ray omits the hit surface albedo, and the room volume's
high z bound sits one ULP below the north wall, so that face reads zero. The
probe field is one diffuse bounce; it is not a path-traced renderer and does not
claim modern-game parity.
