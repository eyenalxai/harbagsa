# Path-traced DDGI reference

## Method

`src/reference` is a CPU path tracer for the renderer's diffuse term. It traces
coloured paths from a fixed grid of pixel centres and compares the indirect term
with the probe field. The `reference` harness command runs it against two
`scene_color` float captures of the same view.

Estimator, per camera-hit surface point:

```text
R(v) = emission + albedo * (E_direct + mean_cos(R(next)))
```

- `E_direct` is the sun (16 Vogel-disk samples at the camera hit, one centre ray
  after a bounce) and every active point light, with the lit pass falloff
  `(1 - (d / range)^2)^2` and a hard shadow ray. The point-light shadow skips a
  lamp box, so a lamp never blocks its own light.
- `mean_cos(R(next))` is one cosine-weighted hemisphere sample of the radiance
  that arrives from the next surface or the sky. `bounces` counts these diffuse
  bounces after the camera hit; the scenario uses 3, so the deepest vertex still
  receives direct light.
- A sky miss returns `sky.glsl`, including the art-directed sun disk, because a
  probe ray that escapes returns the same value.
- The camera ray mirrors `box.vert`, `camera.glsl`, and `mat4_perspective`; the
  sample point is the pixel centre.

Scale: the renderer's direct term is `albedo * NdotL` with no `1/pi`, and the
gather returns irradiance. The reference uses the same scale: `mean_cos` is the
cosine-weighted mean radiance, which is exactly what the gather's `2 pi` and
`1/pi` pair estimates from the atlas. Nothing is divided or multiplied to make
the numbers meet.

Comparison: the two captures differ only in the gather toggle, so the direct
term cancels and the difference is `albedo * probe_indirect`. The reference
value is `albedo * mean_cos`. The CSV pairs both per sample point. Emissive
faces are left out of the direct comparison because the lit pass adds the
emission to the same pixel.

`src/reference` reproduces the renderer exactly enough that the **direct** term
matches: the median GPU/reference direct ratio is 0.9997 in the chamber and
0.9998 in the lane, with a median error of 0.03 percent. The indirect gap below
is therefore the probe field, not the estimator.

## Scene and sample budget

`scenarios/ddgi-reference.json` at 1280x720:

| Scene | Camera and light | Source |
| --- | --- | --- |
| chamber | camera (15.5, 1.7, 5.0) looking at (11, 1.5, 11), fov 90; sun azimuth 270, elevation -20, diameter 0.53; one warm Lamp at (14.5, 2.75, 7.0), intensity 2.5, range 10 | `scenarios/ddgi.json` |
| lane | camera (7.4, 1.7, 13.2), yaw -90, pitch -5; sun azimuth 270, elevation 20, diameter 0.53; no lamp | `scenarios/room-lighting.json` |

Renderer inputs: `renderer_debug` sets `taa`, `jitter`, and `ao` off. AO must be
off because the reference has no AO term; TAA and jitter are off so each capture
is one deterministic frame and the two captures have identical direct shading.
The command rejects a run that leaves any of them on, or that leaves the sky,
the point-light shadows, the HUD, or the menu in a state the estimator does not
model.

Budget: 48 paths per sample point, 3 diffuse bounces, a 16-pixel stride, and 16
sun-disk samples at the camera hit. That is 80 x 45 grid points, 3556 usable
points in the chamber and 3591 in the lane. A point is excluded from the metrics
when the sky is hit, when a half-pixel neighbour hits a different box or a
distance more than 2 percent away, or when the reference indirect is below
1e-5. The excluded points still fill the headless image.

The RNG is a fixed LCG seeded by the grid index and the path index, so a repeat
run gives the same metrics. The run writes:

- `frames/<name>-reference.png`: the path-traced radiance at the grid, sRGB
  encoded. This is the headless target; it is not committed.
- `<name>-reference.json`: the scene, estimator, metrics, tolerance, and result.
- `<name>-reference.csv`: one row per used sample point with the reference and
  GPU indirect colour, the ratio, and the error.
- `report.json.references`: both scene reports, so `jq .references` reads the
  numbers without the side files.

## Tolerance

| Metric | Gate | Why |
| --- | --- | --- |
| `metrics.ratio` | in [0.80, 1.25] | median per-point luminance ratio. A one-bounce 8 x 8 probe field on a 1 m grid must stay within 25 percent of a multi-bounce reference. A missing or doubled energy factor is 2x or more and fails. |
| `metrics.error` | <= 0.30 | median per-point relative error. The probe field is low frequency; this bound admits the grid scatter but not a wrong surface. |
| `metrics.colour_spread` | <= 0.10 | the spread of the per-channel energy ratios. A field that keeps the light source's colour instead of the hit surface's colour fails. |
| `metrics.zero_fraction` | <= 0.01 | the fraction of used points with zero GPU indirect where the reference sees light. A whole unlit face fails. |

The tolerance lives in the scenario command, not in a tuning constant. The
gate is the run: a miss joins `report.json.failures` and the run exits 1. The
numbers below are the current tree, not a renumbered gate.

## Result

| Metric | Chamber | Lane |
| --- | ---: | ---: |
| used points | 3556 | 3591 |
| excluded: edge | 44 | 9 |
| excluded: sky | 0 | 0 |
| median ratio | 1.049 | 0.716 |
| ratio p10 / p90 | 0.000 / 1.464 | 0.000 / 1.906 |
| median error | 0.247 | 0.924 |
| energy ratio r, g, b | 1.563, 0.997, 1.032 | 0.933, 0.727, 0.655 |
| colour spread | 0.566 | 0.279 |
| mean reference / GPU | 0.2497 / 0.2697 | 0.0319 / 0.0238 |
| zero GPU, reference lit | 389 (10.9%) | 1269 (35.3%) |
| direct ratio (validation) | 0.9997 | 0.9998 |

Both scenes fail the gate: the chamber on colour and coverage, the lane on
ratio, error, colour, and coverage. The median luminance is close in the
chamber (5 percent high) because the colour error and the missing coverage
partly cancel in a luminance average.

Removing the zero-coverage points separates the two defects:

| Metric, zero points removed | Chamber | Lane |
| --- | ---: | ---: |
| points | 3167 | 2323 |
| median ratio | 1.096 | 1.044 |
| median error | 0.215 | 0.407 |
| energy ratio r, g, b | 1.674, 1.087, 1.123 | 1.494, 1.180, 1.065 |

The remaining bias is red-heavy: red is 49 to 67 percent high, green and blue
are within 18 percent.

## Findings

### 1. The probe ray drops the hit surface albedo

`src/renderer/shaders/probe_ray.comp`, `hit_radiance`:

```glsl
vec3 radiance = object.color.rgb * object.color.a;   // emission only
...
radiance += SUN_COLOR * diffuse;                     // no albedo
radiance += light.color.rgb * (...);                 // no albedo
```

The lit pass shades a surface as `albedo * (sun + point lights)`, and the
renderer's outgoing radiance of the hit surface is that same value. The probe
ray returns the direct irradiance without the hit albedo, so the atlas stores
the colour of the light source instead of the colour of the surface that
bounced it. In the teal room (albedo 0.38, 0.60, 0.56) lit by a warm lamp
(1.00, 0.78, 0.45) the probe field keeps the warm spectrum, which is the red
bias in the table above. It also makes the field brighter than the reference by
roughly `1 / albedo` per channel.

Fix: multiply the sun and point-light terms by `object.color.rgb` in
`hit_radiance`, exactly as the lit pass does. The emission term is already
correct. This changes every probe-lit image, so it needs its own re-baseline of
`ddgi.json`, `room-lighting.json`, `ddgi-arena.json`, `ddgi-sealed.json`,
`ddgi-door.json`, and `ddgi-move.json`; it is not part of this change.

### 2. The room volume's high z bound is one ULP below the north wall

`src/frame/probe_volumes.odin` sets the room volume to the inner room corners
with a 1.04 m spacing and 10 cells in x and z:

```text
min.z  = 3.8
high.z = 3.8 + 10 * 1.04 = 14.1999998
```

The north wall is box 52: center z 14.35, half 0.15, so its inner face is
`14.35 - 0.15 = 14.2000008`. The face is one ULP above the volume's high bound,
so the gather's `world_position <= high` test rejects every fragment on that
face and `probe_indirect` returns zero. The same test on the east wall happens
to land on the same ULP and keeps its term.

The reference sees 0.12 to 0.24 indirect in the chamber and 0.007 to 0.068 in
the lane there. The result is a black north wall in the chamber and a black 35
percent of the lane frame: `zero` 389 in the chamber and 1269 in the lane, all
on box 52, in `runs/ddgi-reference/`. That is a coverage hole, not a leak test.

Fix: give the room volume a small margin, for example `min = inner - 0.05` and
`spacing = (inner size + 0.10) / 10 = 1.05`, or compare the containment with a
1 mm epsilon in the gather. The margin changes the probe positions by 5 cm, so
it also needs the lighting gates re-run.

Neither fix is applied here. This change adds the reference and reports what it
measures; the reference gate stays red until the two defects are fixed.

## Limits

- The reference models the renderer, not a physical light transport: the sun is
  a directional irradiance, the point light uses the renderer's windowed
  falloff, and the sky is the art-directed gradient with its 12x sun disk. That
  is the point: it must answer the same question as the probe field.
- Ambient occlusion, TAA, jitter, the output dither, the HUD, and the overlay
  are outside the comparison. The scenario turns the first three off.
- Probe relocation is not modelled. The reference traces from the real surface;
  the probe field traces from relocated probe centres.
- The sun disk is sampled at a fixed phase. The lit pass rotates the pattern per
  pixel and TAA averages it, so a penumbra pixel can differ by one 1/16 step.
  The indirect comparison is unaffected because both captures share the direct
  term.
- The headless image is the 80 x 45 sample grid, not a full-resolution frame.
  A full frame at 48 paths and 3 bounces would take about 16 times longer.
- The comparison covers one room and one corridor, as the ticket asks. It does
  not cover the open arena, where the sky fill and the 4 m probes dominate.

## Cost

| Scene | Points | Paths per point | Wall clock |
| --- | ---: | ---: | ---: |
| chamber | 3556 | 48 x 3 bounces | 6.3 s |
| lane | 3591 | 48 x 3 bounces | 8.4 s |

The whole run is 18.8 s, including both GPU scene renders and the captures.

## Reproduce

```sh
make reference
jq '.references[] | {name, ok, metrics}' runs/ddgi-reference/report.json
jq -r '.failures[]' runs/ddgi-reference/report.json
```

The run exits 1 while the gate is red. The estimator unit tests run in
`make test` (`tests/reference`): the cosine furnace test, the sun and point
light terms, the lamp mask, the camera basis, the sky miss, and the comparison
math.
