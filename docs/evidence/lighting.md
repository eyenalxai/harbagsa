# Direct lighting evidence

Captured on 2026-10-26 with AMD Radeon RX 9060 XT (RADV GFX1200). All runs are offscreen through `bin/harbagsa-agent`. The rendering decision is [ADR 0037](../adr/0037-direct-dynamic-point-lights.md).

## Ambient and lamp response

`scenarios/lighting.json` captures the stairs area with no lamp, adds one warm Lamp, then removes it. Values below are 8-bit channel means at 1280x720.

| Capture | Red | Green | Blue |
| --- | ---: | ---: | ---: |
| Ambient only | 40.22 | 50.99 | 54.21 |
| Lamp on | 135.57 | 140.66 | 115.17 |
| Lamp removed | 40.22 | 50.99 | 54.21 |

The ambient captures are not black. The lamp raises every channel, and removal restores the original mean. A depth capture also proves that the chamber contains geometry rather than an empty background.

## Moving light

`scenarios/light-move.json` holds the camera and wall, then moves one lamp away from the wall.

| Capture | Red | Green | Blue |
| --- | ---: | ---: | ---: |
| Near lamp | 122.30 | 93.39 | 71.32 |
| Far lamp | 48.51 | 39.23 | 36.71 |

The near capture is brighter, the far capture remains readable, and the two render digests differ. This checks the current transform through the public editor and capture seams.

## Reproduce

```sh
tools/make.sh build
./bin/harbagsa-agent suite lighting --out runs/lighting
./bin/harbagsa-agent checks runs/lighting/lighting
./bin/harbagsa-agent checks runs/lighting/light-move
```

The run directories hold the PNGs. The repository does not commit images.
