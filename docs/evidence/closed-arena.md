# Closed arena evidence

Captured on 2026-10-27 from the closed-arena branch with AMD Radeon RX 9060 XT (RADV GFX1200). The rendering context is in [ADR 0037](../adr/0037-direct-dynamic-point-lights.md); the shell decision is in [ADR 0038](../adr/0038-closed-arena-shell.md).

## Shell

`scenarios/closed-arena.json` looks up from the arena centre at 1280x720.

| Check | Measured | Gate |
| --- | ---: | --- |
| Static arena boxes | 52 | exactly 52 |
| Ceiling centre height | 5.75 m | exactly 5.75 m |
| Ceiling half extent | 20.5 m | above 20 m |
| Ceiling capture mean green | 31.23 | above 10 |

The ceiling capture fills the frame with a box surface. It has no clear-colour pixels. The arena wall height is 5.5 m and the ceiling adds 0.5 m, so the underside sits exactly at the wall top. The taller walls leave room for a standing jump from the 2.5 m dive platform.

`tests/simulation/ceiling.odin` places the player 0.2 m below the ceiling and launches the player upward. The peak feet position stays at the 3.70 m clearance bound, within the 0.02 m physics tolerance.

## Before and after

The same smoke command ran before and after the shell change:

```sh
./bin/harbagsa-agent run scenarios/smoke.json --out runs/closed-arena/before
./bin/harbagsa-agent run scenarios/smoke.json --out runs/closed-arena/after-smoke
./bin/harbagsa-agent compare runs/closed-arena/before runs/closed-arena/after-smoke --delta
```

All three capture pairs changed. The labeled panel is `runs/closed-arena/compare/compare.png`.

## Reproduce

```sh
tools/make.sh agent
./bin/harbagsa-agent run scenarios/closed-arena.json --out runs/closed-arena/after
./bin/harbagsa-agent suite fast --out runs/closed-arena/fast
tools/make.sh test-simulation
```

The run directory holds the PNG. The repository does not commit images.
