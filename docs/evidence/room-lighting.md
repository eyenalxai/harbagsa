# Room lighting evidence

Captured on 2026-10-25 from the DDGI gather branch. GPU: AMD Radeon RX 9060 XT
(RADV GFX1200). All runs are offscreen through `bin/harbagsa-agent`.

## The room

The arena has a closed room in its +x/+z corner. It is 11 m square with a 3 m
clear height, a 0.3 m ceiling, and one 1.6 m by 2.2 m door in the west wall. It
is twelve static arena boxes: seven shell boxes, four interior walls, and one
dropped tunnel ceiling. It collides and enters the TLAS. It is not a placed
object. The arena stays 40 m.

The door opens into a four-turn entry tunnel, a light lock. The path is east,
south, west, south, and east into the chamber. The clear tunnel width is 2.0 m
and the clear height is 2.4 m. The lanes are `z 12.2..14.2`, `z 9.9..11.9`, and
`z 7.6..9.6`; the east connector is `x 10.5..12.5` and the west connector is
`x 6.8..8.7`. The chamber is the east strip and the south strip, about 70 m2.
The colour is the teal world hue `0.38 0.60 0.56` linear, documented in
[world.md](../design/world.md).

The scene has no constant ambient term. The room is black unless direct or
probe indirect light reaches it. The direct-light decision is in
[ADR 0028](../adr/0028-direct-light-with-surface-occlusion.md); the probe
indirect term is in
[ADR 0033](../adr/0033-ddgi-irradiance-and-gather.md). The ambient occlusion
rays stay and scale the sun and point lights at strength 0.5.

## What it checks

`scenarios/room-lighting.json` at 1280x720. Values are from
`./bin/harbagsa-agent run scenarios/room-lighting.json --out runs/room-lighting`.

| Check | Measured | Gate | Passes |
| --- | ---: | --- | --- |
| First lane, west sun mean green | 39.67 | at least 2 | yes |
| First lane, east sun mean green | 8.07 | above 2, below 20, and below west | yes |
| Chamber, west sun mean green | 0.94 | above 0.5, below 2 | yes |
| Chamber, east sun mean green | 0.99 | above 0.5, below 2 | yes |
| Chamber, west against east | 0.06 | equal within 0.1 | yes |
| Chamber depth maximum | 0.9947 | below 0.999 | yes |
| First lane depth maximum | 0.9907 | below 0.999 | yes |
| Lamp on mean green | 181.52 | at least 80 | yes |
| Lamp off mean green | 0.94 | above 0.5, below 2 | yes |

The 0.17 floor is the output dither on black. The chamber does not receive a
straight sun ray: no sun ray passes the four turns. The first lane is lit when
the sun is west, because the sun shines through the west door. Under an east sun
it is dim but not black; the 8.07 is transport through the connected light lock,
not a wall leak. The chamber reads about 0.9 from the same transport. The door is
the only direct path for the sun.

The lamp is a warm `Lamp` at `(14.5, 2.75, 7.0)` with intensity 2.5 and range
10. It is placed with `place`, so no debug gizmo enters the frame. The lamp is
the only light in the chamber, and the occlusion term darkens the direct light
in the corners. Removing the lamp leaves the sun bounce, so the view returns to
0.94 instead of black.

The colour captures are `outside`, `door-out`, `lane1-west`, `lane1-east`,
`chamber-west`, `chamber-east`, `lamp-on`, and `lamp-off`. The run directory
holds the PNGs; the repository does not commit images.

## What it does not prove

- There is one diffuse bounce, not a full path trace. The probe field is
  low-frequency, so it fills a wall but does not reproduce a multi-bounce
  reference within a stated tolerance.
- The occlusion is a contact term on the direct light, not an ambient integral.
  A lamp-lit corner is darker than a path tracer would make it.
- The default sun comes from the +x/+z side, so the west facade is in shade and
  the door is a dark notch from outside. The `outside` capture shows the lit
  roof and north face; `door-out` looks out from inside the tunnel.
- There is one lamp in the test scene. The light budget holds every active lamp;
  clustered forward+ scales the per-pixel loop.

## Reproduce

```sh
tools/make.sh build
./bin/harbagsa-agent run scenarios/room-lighting.json --out runs/room-lighting
jq -r '.checks[] | [.field, .ok, .actual] | @tsv' runs/room-lighting/report.json
```

The scenario is part of `make validate-offscreen` and `make lighting`, so the
Vulkan validation layers cover the room geometry and the lamp shadow ray.
