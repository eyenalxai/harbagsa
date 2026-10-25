# Room lighting evidence

Captured on 2026-10-25 from the feature commit on
`feat/closed-room-lighting-test`. GPU: AMD Radeon RX 9060 XT (RADV GFX1200).
All runs are offscreen through `bin/harbagsa-agent`.

## The room

The arena has a closed room in its +x/+z corner. It is 7 m square with a
3 m clear height, a 0.3 m ceiling, and one 1.6 m by 2.2 m doorway in the west
wall. It is seven static arena boxes, so it collides and enters the TLAS. It is
not a placed object. The arena stays 40 m; the empty corner holds the room
without a resize. The colour is the new teal world hue
`0.38 0.60 0.56` linear, documented in
[world.md](../design/world.md).

The room exists to test the current interior lighting model. It is not a change
to that model. The scenario is `scenarios/room-lighting.json`; the design is
[ADR 0017](../adr/0017-sky-ambient-and-ray-traced-ambient-occlusion.md) and the
terms are in [GLOSSARY.md](../../GLOSSARY.md).

## What it checks

The scenario runs at 1280x720. The values are from
`./bin/harbagsa-agent run scenarios/room-lighting.json --out runs/room-lighting`.

| Check | Measured | Gate | Passes |
| --- | ---: | --- | --- |
| `sealed-depth` maximum depth | 0.9895 | below 0.999 | yes |
| `ceiling-depth` maximum depth | 0.9722 | below 0.999 | yes |
| Doorway sun patch mean green | 113.5 | above 100 | yes |
| Doorway shade patch mean green | 88.1 | below 95 | yes |
| Lamp-on mean green | 144.9 | above 120 | yes |
| Lamp-off mean green | 76.4 | below 90 | yes |

The depth gate is the closure proof. The depth target clears to 1.0, so a sky
pixel in a sealed view reaches 1.0. The far corner of the room reads 0.989 and
the ceiling reads 0.972.

The sun gate compares one 500 by 240 region at `(400, 460)`, which covers the
floor at the doorway. Moving the sun from the west (`azimuth_deg 270`) to the east
(`azimuth_deg 90`) drops the region mean by 25.4 levels. The doorway is the only
path for that light.

The lamp gate uses a warm `Lamp` at `(13.5, 2.75, 10.5)`, the prefab default of
1.5 intensity and 8 m range. The `place` command creates it without debug mode,
so the sun gizmo and editor lines stay out of the frame. The room-corner view
rises by 68.5 levels when the lamp is placed and falls back when `remove`
deletes it. The lamp sits at the ceiling and casts the hard point-light shadow.
The sun elevation, lamp intensity, lamp range, and patch region are scenario
parameters.

The colour captures are `outside`, `inside-door`, `sealed-corner`, `ceiling`,
`door-sun`, `door-shade`, `room-corner`, `lamp-on`, and `lamp-off`. The run
directory holds the PNGs; the repository does not commit images.

## What it does not prove

- The ambient term is a normal ramp, not an integral of the visible sky. A
  sealed room is not darker than an open surface with the same normal, except
  where ambient occlusion reaches.
- The AO radius is 1.5 m and the room is 6.4 m inside. Only the bands near the
  corners and the ceiling darken. The floor centre stays at full ambient.
- There is no bounce light. The doorway sun patch does not fill the room.
- There is one lamp. The light budget is the eight nearest lamps.

Those limits are the reason to keep the room as a test fixture rather than
treat its image as a physical interior.

## Reproduce

```sh
tools/make.sh build
./bin/harbagsa-agent run scenarios/room-lighting.json --out runs/room-lighting
jq -r '.checks[] | [.field, .ok, .actual] | @tsv' runs/room-lighting/report.json
```

The scenario is part of `make validate-offscreen` and `make lighting`, so the
Vulkan validation layers cover the room geometry and the lamp shadow ray.
