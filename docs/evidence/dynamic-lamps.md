# Dynamic lamps evidence

Captured on 2026-10-27 with AMD Radeon RX 9060 XT (RADV GFX1200). The decision is in [ADR 0039](../adr/0039-dynamic-only-lamps.md).

## Starting scene

`scenarios/initial-lamps.json` checks the six starting objects and moves the warm lamp.

| Object | Prefab | Body | Light |
| --- | --- | --- | --- |
| 1-3 | Crate | dynamic | off |
| `initial-lamp` | Lamp | dynamic | warm |
| `initial-panel` | Light panel | dynamic | cool |
| `initial-beacon` | Beacon | dynamic | red |

The check run reports `objects.count = 6` and `debug.lights.active = 3`. The exact `place` command requests a static Beacon with name `static-request`; the resulting body is `dynamic`.

Moving `initial-lamp` from `(-6, 1.2, 6)` to `(-2, 0.25, 4)` changes the next capture's mean delta by 8.336 levels and changes the render digest. The unit test also compares the collected light position with the moved body centre.

## Before and after

The same smoke command ran on the closed arena with no starting lamps, then with the three lamps:

```sh
./bin/harbagsa-agent run scenarios/smoke.json --out runs/closed-arena/after-smoke
./bin/harbagsa-agent run scenarios/smoke.json --out runs/dynamic-lamps/after-smoke
./bin/harbagsa-agent compare runs/closed-arena/after-smoke runs/dynamic-lamps/after-smoke --delta
```

All three capture pairs changed. The labeled panel is `runs/dynamic-lamps/compare/compare.png`.

## Reproduce

```sh
tools/make.sh agent
./bin/harbagsa-agent run scenarios/initial-lamps.json --out runs/dynamic-lamps/initial
tools/make.sh test-simulation
tools/make.sh test-harness
```

The run directories hold the PNGs. The repository does not commit images.
