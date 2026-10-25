# Sky and ambient occlusion evidence

Captured on 2026-10-25 from the direct-light branch. GPU: AMD Radeon RX 9060 XT
(RADV GFX1200). All runs are offscreen through `bin/harbagsa-agent`.

## What changed

The scene has no ambient term. The sky is an analytic background, not a light.
The flat `AMBIENT_COLOR` and the sky ambient ramp are gone. A surface that the
sun and the point lights do not reach is black.

The eight ambient-occlusion rays stay. They now scale the sun and the point
lights instead of an ambient term, so a lit corner keeps a contact darkening.
The strength is 0.5. The decision is in
[ADR 0028](../adr/0028-direct-light-with-surface-occlusion.md), which supersedes
[ADR 0017](../adr/0017-sky-ambient-and-ray-traced-ambient-occlusion.md).

## Sky gates

`scenarios/sky.json` at 1280x720 declares `requires.renderer_debug` because it
sets the `sky` override. The horizon capture reads the top half of the frame, so
the black walls below the horizon do not enter the mean.

| Capture | Mean green | Gate | Passes |
| --- | ---: | --- | --- |
| `sky-zenith` | 135.83 | at most 138 | yes |
| `sky-horizon` | 144.70 | at least 140 | yes |
| `sky-horizon` against `sky-zenith` | +8.87 | greater | yes |
| `flat-zenith` | 178.83 | at least 170 | yes |

The gates have teeth: with `sky: false` from the start, the zenith mean is
178.83 and the 138 gate fails. The absolute values are lower than the old
`sky-ao` run because the walls in the horizon view are no longer lit by an
ambient term.

Reproduce:

```sh
./bin/harbagsa-agent run scenarios/sky.json --out runs/sky
```

## Ambient occlusion on direct light

`scenarios/stairs-ao.json` at 800x600, sun at 25°. The sunlit region is
`{300, 400, 120, 60}` and the shaded wall region is `{700, 140, 40, 40}`. The
scenario captures the same views with `ao` on and off.

| Region | AO on | AO off | Gate | Passes |
| --- | ---: | ---: | --- | --- |
| Sunlit floor | 116.02 | 117.00 | on below off | yes |
| Shaded wall | 45.91 | 49.71 | on below off | yes |

The sunlit floor loses 0.98 levels, and the shade loses 3.80. The occlusion is
local: it reaches 1.5 m and is scaled by 0.5, so it darkens a contact band
rather than the whole wall.

Reproduce:

```sh
./bin/harbagsa-agent run scenarios/stairs-ao.json --out runs/stairs-ao
```

## TAA stability

`scenarios/taa-motion.json` at 1280x720, after the post-motion hold:

| Check | Measured | Gate |
| --- | ---: | ---: |
| `capture.worst_mean_delta` | 0.0412 of 255 | at most 0.07 |
| `capture.worst_over_16_fraction` | 3.25e-06 | at most 5e-06 |

At `AO_STRENGTH` 1.0 the over-16 fraction measures 5.10e-05 and fails. A full
occlusion step on a sunlit pixel is up to 16 levels, and the stochastic term
moves those pixels across the gate. Half strength halves the visible step and
brings the fraction below the limit. The mean gate stays at 0.07; the ray count
stays at eight.

## Visibility banding

The sun count is 16 and the occlusion count is 8, so the lighting steps by 1/16
and 1/8. The visibility-count dither in
[ADR 0024](../adr/0024-visibility-count-dither.md) offsets a partial count
inside its own step. `scenarios/ramp-shadow.json` at 1280x720 reads the 550x280
stats region at `(150, 420)` after 600 settle frames.

| Region | Steps | Max jump | Gate |
| --- | ---: | ---: | --- |
| `ramp-steps` | 0 | 0.086 | at most 50 steps, max below 2 |
| `ramp-crouch-steps` | 0 | 0.086 | at most 25 steps, max below 2 |

The shade is black now, so the ramp-foot region has no lit gradient to band.
The gate still proves that the sun penumbra and the occlusion dither do not add
a contour band.

## Room proof

`scenarios/room-lighting.json` at 1280x720 proves the four-turn light lock:

| Check | Measured | Gate |
| --- | ---: | --- |
| First lane, west sun | 6.33 mean green | at least 2 |
| First lane, east sun | 0.17 mean green | below 0.5 |
| Chamber, west sun | 0.17 mean green | below 0.5 |
| Chamber, east sun | 0.17 mean green | below 0.5 |
| Chamber depth maximum | 0.9947 | below 0.999 |
| Lamp on | 123.75 mean green | at least 80 |
| Lamp off | 0.17 mean green | below 0.5 |

The 0.17 floor is the output dither on black. The chamber does not change with
the sun azimuth. The lamp and its occlusion are the only light inside. The room
geometry and the camera views are in
[room-lighting.md](room-lighting.md).

## What passes

`make check`, `make test`, `make validate-offscreen`, `make lighting`, and the
renderer suite pass. The renderer suite includes `sky`, `stairs-ao`,
`taa-static`, `taa-motion`, `banding`, `capture-targets`, and the shadow
scenarios.

## What remains

- No global illumination or bounce. A dark tunnel stays dark.
- The occlusion is a visibility term on direct light. It is not a physical
  ambient integral, and a lit corner is darker than a path tracer would make it.
- Half-resolution occlusion, if the frame budget tightens.
- Specular and bent normals. The rays could accumulate an average unoccluded
  direction for free.

## Run directories

All are under `runs/` and are not committed:

- `runs/sky` and the `sky: false` negative control
- `runs/stairs-ao`
- `runs/taa-motion`
- `runs/ramp-shadow` and `runs/ramp-shadow-crouch`
- `runs/room-lighting`
