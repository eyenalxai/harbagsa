# Second bounce and contact seams

The bake now accepts one or two diffuse bounces and traces two by default. The
second pass re-traces the same per-texel ray set and samples the denoised
first-bounce lightmap at each hit, so it is deterministic and adds no stochastic
noise. The artifact layout, atlas bytes, probe data, and runtime cost are
unchanged; only the lightmap values and the bake time change.

The corner capture supports the two-bounce default: the measured corner's
lightmap term rises 35-54%, the corner beauty mean rises 6.05 code values, and
the whole-frame beauty mean rises 4.73. The cost is 2.2 s on the lightmap stage
(3.2 s to 5.6 s) and 2.2 s on the total bake (5.3 s to 7.5 s) at 16 threads. The
2 s target was already missed; `bounces: 1` keeps the one-bounce build.

Images stay in the run directories and are not committed.

## What changed

- `Quality.bounces` accepts 1 or 2; the default is 2. `bounces_supported` is the
  one gate the tool, the harness, and the loader share.
- `lightmap_bake` finishes the first bounce (buried fill, 3x3 denoise, gutter),
  keeps it as the sample field, zeroes the working atlas, re-traces the same
  jobs, and adds `albedo(hit) * first_bounce(hit)` per ray. The second buffer is
  filled, denoised, and gutter-copied, then added to the first. The first-pass
  ray set, seed, and rotation are unchanged.
- A hit resolves its chart from the local face normal and bilinearly samples the
  first-bounce field at the hit point's local face coordinates.
- `harbagsa-bake --bounces 1|2` and the harness `bake` command's `bounces` field
  select the build. `state.bake.bounces` reports the loaded artifact's value.
- `TOOL_VERSION` is 5 because the default changed. A tool 4 artifact still loads
  and reports `stale`; rebuild it with `make bake`.
- The one-bounce atlas payload is unchanged: the tool 4 and tool 5 one-bounce
  builds both carry payload `3a680665ebcdd171`. Only the header tool version and
  the bake key differ.

## Corner, one bounce against two

`scenarios/lighting-bounce.json` places a static fixture behind the camera and
lights the south-west arena corner. The same scenario runs twice; the camera,
30 settling frames, 12 frames after the camera, TAA off, and jitter off are
identical. Both runs capture at frame 42 from camera `[-12.5, 2.2, -12.5]`,
yaw 45, pitch -5.687, fov 55. The render digests differ only because the bake key
differs.

```sh
./bin/harbagsa-agent run scenarios/lighting-bounce.json --param bounces=1 --out runs/lighting-bounce-1
./bin/harbagsa-agent run scenarios/lighting-bounce.json --param bounces=2 --out runs/lighting-bounce-2
./bin/harbagsa-agent compare runs/lighting-bounce-1 runs/lighting-bounce-2 --delta
```

The captures write `runs/lighting-bounce-1.hbake` and
`runs/lighting-bounce-2.hbake` (12,560,688 bytes each; bakes 5,337 ms and
7,461 ms).

| Measure | one bounce | two bounces | Delta |
| --- | --: | --: | --: |
| Corner beauty mean, RGB code values | 239.053 / 172.785 / 119.265 | 246.332 / 179.295 / 123.628 | +6.05 (+3.42%) |
| Whole-frame beauty mean | 243.382 / 194.559 / 139.304 | 247.446 / 200.484 / 143.505 | +4.73 (+2.46%) |
| Corner lightmap mean | 136.756 / 89.940 / 59.405 | 160.183 / 103.726 / 68.778 | +15.53 (+16.28%) |
| Whole-frame lightmap mean | 139.248 / 96.801 / 66.813 | 160.702 / 110.385 / 76.542 | +14.92 (+14.78%) |

The means above are the per-channel 8-bit sRGB means from the capture stats;
the deltas are the mean of the three channels. The `compare` tool over the two
full-frame beauty PNGs reports mean absolute difference 7.410, maximum 16, and
917,674 of 921,600 pixels different (99.6%). The lightmap term pair reports mean
absolute difference 21.455, maximum 27, and every pixel different.

The picked linear lightmap terms at the same three points:

| Point | one bounce (R, G, B) | two bounces (R, G, B) | Delta |
| --- | --- | --- | --- |
| Corner wall at `[-19.99, 1.66, -20.00]` | 0.229049, 0.086803, 0.035911 | 0.336390, 0.119351, 0.048569 | +46.9%, +37.5%, +35.2% |
| Corner floor at `[-19.99, 0.08, -20.00]` | 0.165800, 0.063944, 0.026760 | 0.255674, 0.092467, 0.038121 | +54.2%, +44.6%, +42.5% |
| Wall away at `[-19.30, 2.09, -20.00]` | 0.262978, 0.101178, 0.042249 | 0.371075, 0.135671, 0.056086 | +41.1%, +34.1%, +32.7% |

The decoded default-arena atlas adds 32.9% linear energy
(`runs/lighting-bounce-check/arena-1t16.hbake` against
`arena-2t16-a.hbake`). The second bounce is low-frequency and lifts the crease
and the floor contact; it does not add a new edge.

### Default decision

Two bounces is the default. The corner reads: a 46.9% red lift at the crease,
+3.42% on the corner beauty mean, +2.46% on the whole frame, and a 16.3% lift on
the corner lightmap term. The same lift is global: the whole-frame lightmap mean
rises 14.78%, and the wall-away control 70 cm from the corner rises 32.7-41.1%.
The second bounce is a physical indirect term, not a corner-specific fix. The
flat box look survives; the change fills the corner instead of moving a hard
edge. The cost is bake time only: the lightmap stage is 1.75x and the total bake
is 1.4x, and the artifact and GPU bytes do not move.

The 2 s bake target remains missed: 7.5 s against 5.3 s for the one-bounce
build. A caller that wants the old cost passes `bounces: 1`; the artifact
contract and the runtime make no assumption about which default built a loaded
artifact. A tool 4 artifact is `stale`, so a rebuild is explicit.

[ADR 0045](../adr/0045-mixed-static-baked-indirect.md) records the decision and
the tool version 5 change.

## Movable-crate contact

`scenarios/lighting-crate-contact.json` places a static fixture beside the
initial dynamic crate at `[-3, 0.5, 6]`. The crate face reads the probe term; the
floor reads the lightmap term. TAA and jitter are off; the bake is the default
two bounces. The run is `runs/lighting-crate-contact`, bake 6,989 ms. The same
scenario with `--param bounces=1` writes `runs/lighting-crate-contact-1`, bake
4,673 ms, for the one-bounce comparison below.

| Point | Term | R | G | B | Luminance |
| --- | --- | --: | --: | --: | --: |
| Crate front face, `[-2.999, 0.448, 6.500]` | probe | 0.215656 | 0.113656 | 0.024134 | 0.1289 |
| Crate front face, `[-2.999, 0.005, 6.500]` | probe | 0.215656 | 0.113656 | 0.024134 | 0.1289 |
| Floor one texel from the contact (27 cm), `[-2.999, 0.000, 6.772]` | lightmap | 0.043106 | 0.038233 | 0.031353 | 0.0388 |
| Floor 24 cm out, `[-2.999, 0.000, 7.017]` | lightmap | 0.042374 | 0.037734 | 0.031052 | 0.0384 |
| Floor 60 cm left, `[-3.398, 0.000, 6.772]` | lightmap | 0.045172 | 0.039584 | 0.031671 | 0.0407 |
| Floor 60 cm right, `[-2.599, 0.000, 6.772]` | lightmap | 0.037170 | 0.034348 | 0.030255 | 0.0351 |

The crate's probe term is constant over the face: `0.215656 / 0.113656 /
0.024134` at both the top and the bottom pick. The floor lightmap term varies
only 0.0372-0.0452 across the 80 cm pick span. The floor pick is 27 cm from the
crate face, one 25 cm lightmap texel, so the ratio is a one-texel-away
approximation rather than the exact contact line. At that point the crate's probe
term is 5.0x the floor's red term, 3.0x green, and 0.77x blue; by luminance it is
3.3x brighter. The step is the 1 m probe field against the 25 cm lightmap, not a
texture gradient: the crate's indirect is visibly brighter than the floor it
rests on in `frames/crate-contact-probe.png` and
`frames/crate-contact-lightmap.png`. The direct term at the floor contact is
0.678 red and the crate's is 1.103 red, so the beauty mismatch is the sum of the
direct and indirect steps, not the indirect alone.

The probe field is still the one-bounce probe gather; only the lightmap gets the
second bounce. That makes the comparison partly a bounce-count comparison. On
the same scene and picks the one-bounce build has a floor contact lightmap of
0.030180 red, 0.027328 green, 0.022020 blue (luminance 0.0276), so the crate's
probe term is 4.7x the floor by luminance against 3.3x with the two-bounce
lightmap. The second bounce narrows this static/dynamic contact step; it does not
close it, because the probe resolution and the one-bounce probe field remain.

## Thin-wall leak (0.5 m)

`scenarios/lighting-thin-wall-leak.json` extends the probe thin-wall scene: a
0.5 m wall (the Wall prefab, the thinnest wall the prefab provides) between a
4.0 intensity static fixture and a dynamic crate 1.5 m behind it. The wall is
4 m long and 3 m high. The run is `runs/lighting-thin-wall-leak`, bake 7,311 ms,
then the wall is removed and the bake republished in the same run.

| Point | With the wall | Wall removed | Change |
| --- | --: | --: | --: |
| Crate east face probe, R / G / B | 0.004449 / 0.008376 / 0.003067 | 0.034978 / 0.064182 / 0.021952 | 7.86x / 7.66x / 7.16x |
| Crate east face near the wall end, R | 0.000792 | 0.173776 | 219x |
| Wall far face lightmap, R / G / B | 0.008928 / 0.003671 / 0.001720 | — | — |

The wall's far face is the `-Z` face at `z = -6.25`; the three picked points span
`x = -16.49` to `-15.52` at `y = 1.51`. Its lightmap term is 0.00769-0.00961 red.
The dynamic crate's probe term with the wall is 0.00445 red, 0.00838 green, and
0.00307 blue (luminance 0.00716). The wall's far face is 0.00893 / 0.00367 /
0.00172 (luminance 0.00465). The crate is brighter than the wall by luminance,
so the red-only "darker than the wall" check does not rule out a through-wall
add. The wall-removal control raises the crate 7.9x, but it also removes the
wall's bounce and opens the around-end path; the far-side pick at the wall end
rises 219x. The capture does not separate through-wall transfer from around-end
transfer. The 0.5 m wall is the thinnest prefab; 0.1-0.2 m remains untested.

## Coplanar seam

`scenarios/lighting-coplanar-seam.json` places two 4 m Wall prefabs end to end at
`x = -2` and `x = 2`, yaw 0, so their `+Z` faces are coplanar and share a 3 m
vertical edge at `x = 0`. Each face owns one chart. A static fixture at
`[-1.5, 2.6, -1.5]` lights both. The run is
`runs/lighting-coplanar-seam`, bake 7,613 ms. The `lightmap_grid` view shows the
two red chart edges meeting at the seam.

| Height | West edge texel | East edge texel | Step |
| --- | --: | --: | --: |
| `y = 2.249` | 0.183415 | 0.168430 | -8.2% |
| `y = 1.782` | 0.194065 | 0.181701 | -6.4% |
| `y = 1.315` | 0.207649 | 0.185401 | -10.7% |

The picks at `[-0.016, y]` and `[+0.021, y]` clamp to the west chart's last texel
and the east chart's first texel; the texel centres are 0.25 m apart. The
in-chart gradient is 1.1% per texel on the west and 2.6% on the east, so the
6.4-10.7% shared-edge step is 2.5-6x the local gradient: the two charts do not
meet with one value. The same-width band `x = 560-720, y = 100-500` reports
lightmap gradient 0.518 against beauty gradient 0.346. The beauty step at the
seam is about one code value (columns 636 and 644 differ by 1.09 on the mean of
three channels at `y = 200-400`), so this is a term-view seam at the 25 cm texel
resolution, not a hard line in the composed frame.

## Colour bleed

`scenarios/lighting-colour-bleed.json` uses a `scene` command: a white
`[1, 1, 1]` wall at `z = -10`, a saturated green `[0.05, 0.95, 0.10]` static
crate in front of it, and a warm static fixture above and left. The white wall's
albedo is one, so its lightmap term is the raw bounce colour. The run is
`runs/lighting-colour-bleed`, bake 6,652 ms.

| Point on the white wall | R | G | B | G / R |
| --- | --: | --: | --: | --: |
| `[15.030, 1.323]`, at the box's right corner | 0.159404 | 0.508476 | 0.101437 | 3.19 |
| `[14.859, 1.327]`, over the box | 0.182718 | 0.539580 | 0.114331 | 2.95 |
| `[14.691, 1.331]`, over the box | 0.218736 | 0.552785 | 0.132595 | 2.53 |
| `[14.694, 1.052]`, low beside the box | 0.159265 | 0.500155 | 0.100111 | 3.14 |
| `[13.889, 1.349]`, away from the box | 0.373128 | 0.466840 | 0.203281 | 1.25 |
| `[13.635, 1.355]`, away from the box | 0.399891 | 0.446243 | 0.215472 | 1.12 |

The near-corner G/R is 2.9x the far-wall G/R. The blue term also drops at the
corner (`0.101` against `0.215`), so the hue shift is a green add and a warm-red
loss, not a uniform lift. `frames/colour-bleed-lightmap.png` shows the green
field on the white wall.

## Determinism

Tool 5, default arena, two 16-thread runs and one 8-thread run for two bounces,
and one 16-thread and one 8-thread run for one bounce:

```sh
./bin/harbagsa-bake --out runs/lighting-bounce-check/arena-2t16-a.hbake --bounces 2 --threads 16
./bin/harbagsa-bake --out runs/lighting-bounce-check/arena-2t16-b.hbake --bounces 2 --threads 16
./bin/harbagsa-bake --out runs/lighting-bounce-check/arena-2t8.hbake --bounces 2 --threads 8
./bin/harbagsa-bake --out runs/lighting-bounce-check/arena-1t16.hbake --bounces 1 --threads 16
./bin/harbagsa-bake --out runs/lighting-bounce-check/arena-1t8.hbake --bounces 1 --threads 8
sha256sum runs/lighting-bounce-check/*.hbake
```

The three two-bounce artifacts are byte-identical at
`2529d04bc507f64a1f95e1f392d48abaea0e6ca77af247419e4f73777b8bcbd6` (re-run
after the alpha-channel fix; the rendered pixels are unchanged). The two
one-bounce artifacts are byte-identical at
`b20cf70147262ce64ed924faae95d4764ecb5b6b57532291af6c1beb7a6e629c`. The
one-bounce payload hash is `3a680665ebcdd171`, the same as the tool 4
one-bounce build; the artifact hash differs only because the header carries tool
version 5 and the key carries it too.

## Check

`make check` passes with the new tool version, the new scenarios, and the
400-line limit.
