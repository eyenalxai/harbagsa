# Direct lighting evidence

Captured on 2026-10-26 with AMD Radeon RX 9060 XT (RADV GFX1200). All runs are offscreen through `bin/harbagsa-agent`. The rendering decision is [ADR 0037](../adr/0037-direct-dynamic-point-lights.md).

## Ambient and lamp response

`scenarios/lighting.json` removes the three starting lamps, captures the stairs area with only the ambient floor, adds one warm Lamp, then removes it. Values below are 8-bit channel means at 1280x720.

| Capture | Red | Green | Blue |
| --- | ---: | ---: | ---: |
| Ambient only | 37.75 | 40.75 | 44.71 |
| Lamp on | 59.63 | 59.60 | 57.52 |
| Lamp removed | 37.75 | 40.75 | 44.71 |

The ambient captures are not black. The lamp raises every channel, and removal restores the original mean. The captures also prove that no view depends on a background pass.

## Moving light

`scenarios/light-move.json` holds the camera and wall, then moves one lamp away from the wall.

| Capture | Red | Green | Blue |
| --- | ---: | ---: | ---: |
| Near lamp | 187.90 | 140.26 | 99.85 |
| Far lamp | 57.52 | 44.94 | 39.67 |

The near capture is brighter, the far capture remains readable, and the two render digests differ. This checks the current transform through the public editor and capture seams.

## Reproduce

```sh
tools/make.sh build
./bin/harbagsa-agent suite lighting --out runs/lighting
./bin/harbagsa-agent checks runs/lighting/lighting
./bin/harbagsa-agent checks runs/lighting/light-move
```

The run directories hold the PNGs. The repository does not commit images.
