# Direct lighting evidence

Captured on 2026-10-27 with AMD Radeon RX 9060 XT (RADV GFX1200). All runs are offscreen through `bin/harbagsa-agent`. The lighting decision is [ADR 0041](../adr/0041-absolute-darkness.md). Point-light shadows are separate evidence in [point-light shadows](point-light-shadows.md).

## Unlit and lamp response

`scenarios/lighting.json` removes the three starting lamps, captures the stairs area with no light, adds one warm Lamp, then removes it. Values below are 8-bit channel means at 1280x720.

| Capture | Red | Green | Blue |
| --- | ---: | ---: | ---: |
| Unlit | 0.17 | 0.17 | 0.17 |
| Lamp on | 19.46 | 21.23 | 15.42 |
| Lamp removed | 0.17 | 0.17 | 0.17 |

The unlit capture is black. The lamp raises every channel, and removal restores the unlit mean. The captures also prove that no view depends on a background pass.

## Moving light

`scenarios/light-move.json` holds the camera and wall, then moves one lamp away from the wall.

| Capture | Red | Green | Blue |
| --- | ---: | ---: | ---: |
| Near lamp | 182.84 | 134.72 | 92.17 |
| Far lamp | 21.18 | 13.78 | 7.95 |

The near capture is brighter, the far capture remains readable, and the two render digests differ. This checks the current transform through the public editor and capture seams.

## Reproduce

```sh
tools/make.sh build
./bin/harbagsa-agent suite lighting --out runs/lighting
./bin/harbagsa-agent checks runs/lighting/lighting
./bin/harbagsa-agent checks runs/lighting/light-move
```

The run directories hold the PNGs. The repository does not commit images.
