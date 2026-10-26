# Path-traced DDGI reference

## Method

`src/reference` is a CPU path tracer for the renderer's diffuse term. It traces
coloured paths from a fixed grid of pixel centres and compares the indirect term
with the probe field. The `reference` harness command runs it against two
`scene_color` float captures of the same view that differ only in the gather
toggle. The difference cancels the direct term exactly.

Estimator, per camera-hit surface point:

```text
R(v) = emission + albedo * (E_direct + mean_cos(R(next)))
```

- `E_direct` is the sun (16 Vogel-disk samples at the camera hit, one centre ray
  after a bounce) and every active point light, with the lit pass falloff
  `(1 - (d / range)^2)^2` and a hard shadow ray.
- `mean_cos(R(next))` is one cosine-weighted hemisphere sample of the radiance
  that arrives from the next surface or the sky.
- A sky miss returns `sky.glsl`.
- The camera ray mirrors `box.vert`, `camera.glsl`, and `mat4_perspective`; the
  sample point is the pixel centre.

The reference uses the same scale as the renderer: the direct term is
`albedo * NdotL` with no `1/pi`, and `mean_cos` is the cosine-weighted mean
radiance. The comparison pairs `albedo * probe_indirect` with `albedo *
mean_cos`. Nothing is divided or multiplied to make the numbers meet.

The direct term validates the estimator: the median GPU/reference direct ratio
is 0.9997 in the chamber and 0.9998 in the lane, with a median error of 0.03
percent. The remaining difference is the probe field.

## Two references

The probe update shades one hit and stops. The hard gate uses **one bounce**,
the same transport the probe field resolves. A **three-bounce** run is reported
as an advisory quality metric; it measures the missing multi-bounce transport
and is not a parity gate.

`scenarios/ddgi-reference.json` runs both references for the chamber and the
lane. The one-bounce command must pass. The three-bounce command has
`"advisory": true`: it writes its report and image, but a tolerance miss does not
fail the run.

## Scene and budget

| Scene | Camera and light |
| --- | --- |
| chamber | camera (15.5, 1.7, 5.0) looking at (11, 1.5, 11), fov 90; sun azimuth 270, elevation -20, diameter 0.53; one warm Lamp at (14.5, 2.75, 7.0), intensity 2.5, range 10 |
| lane | camera (7.4, 1.7, 13.2), yaw -90, pitch -5; sun azimuth 270, elevation 20, diameter 0.53; no lamp |
| platform | camera (-8.1236, 1.655, -16.7168), yaw -115.2095, pitch 3.5065, fov 90; sun azimuth 67.2, elevation 18.5, diameter 0.53; the three spawn crates |

Renderer inputs: `taa`, `jitter`, and `ao` off. AO must be off because the
reference has no AO term; TAA and jitter are off so the two captures have
identical direct shading. The command rejects a run that leaves any of them on,
or that leaves the sky, point-light shadows, HUD, or menu in a state the
estimator does not model.

Budget: 48 paths per sample point, a 16-pixel stride, and 16 sun-disk samples at
the camera hit. The grid is 80 x 45 at 1280 x 720. The platform scene uses 32
paths and an 8-pixel stride at 640 x 360, because its reference runs in the
lighting suite. A point is excluded when the
sky is hit, when a half-pixel neighbour hits a different box or a distance more
than 2 percent away, or when the reference indirect is below 1e-5. The RNG is a
fixed LCG, so a repeat run gives the same metrics.

## Result

One-bounce gate:

| Metric | Chamber | Lane |
| --- | ---: | ---: |
| used points | 3556 | 3347 |
| median ratio | 1.025 | 0.963 |
| ratio p10 / p90 | 0.871 / 1.291 | 0.578 / 1.510 |
| median error | 0.092 | 0.248 |
| energy ratio r, g, b | 1.027 / 1.035 / 1.035 | 0.937 / 0.943 / 0.943 |
| colour spread | 0.008 | 0.006 |
| zero GPU, reference lit | 0 | 0 |

Three-bounce advisory:

| Metric | Chamber | Lane |
| --- | ---: | ---: |
| median ratio | 0.563 | 0.439 |
| median error | 0.437 | 0.562 |
| colour spread | 0.101 | 0.126 |
| zero GPU, reference lit | 0 | 0.00056 |

The one-bounce reference matches the probe field. The three-bounce reference is
about twice as bright in the chamber and the lane, which is the expected gap
between one diffuse bounce and full multi-bounce transport.

One-bounce platform gate:

| Metric | Old field | New field |
| --- | ---: | ---: |
| used points | 1842 | 1842 |
| median ratio | 1.094 | 1.014 |
| ratio p10 / p90 | 0.820 / 1.347 | 0.897 / 1.149 |
| median error | 0.139 | 0.059 |
| mean reference / GPU | 0.089 / 0.097 | 0.089 / 0.091 |
| colour spread | 0.058 | 0.015 |

With the sun below the horizon, the same field falls from mean GPU 0.086 to
0.079 against a 0.078 reference, and the error falls from 0.151 to 0.069. The
direct term is unchanged at 0.04 percent. The old field's dark lobe and dashed
tunnel edge are the visibility cut described in
[ADR 0036](../adr/0036-ddgi-probe-validity-and-contact.md); the new field
removes the lobe, the specks, and the missing contact.

## Bugs found and fixed

The reference exposed two real defects:

1. `probe_ray.comp` added the sun and point-light terms without multiplying by
   the hit surface albedo. The probe atlas kept the light source's colour
   instead of the bounced surface colour. Before the fix, the three-bounce
   colour spread was 0.566 in the chamber and 0.279 in the lane. The probe ray
   now multiplies both direct terms by `object.color.rgb`.
2. The room volume's high z bound was one ULP below the north wall's inner face.
   The gather rejected the whole face: 10.9 percent of the chamber points and
   35.3 percent of the lane points had zero GPU indirect where the reference saw
   light. The gather now expands each volume's high bound by 1e-3.

After both fixes, zero-coverage is 0 in both one-bounce scenes, and the
one-bounce gate passes. The full core evidence is re-baselined in
`docs/evidence/ddgi.md`.

The platform reference added in
[ADR 0036](../adr/0036-ddgi-probe-validity-and-contact.md) found a third class:
probes inside geometry kept their trilinear weight, skipped probe texels left
zero depth, and the arena grid was coarser than the contact. The probe pass now
skips invalid probes, ignores zero-depth texels, biases the Chebyshev test, and
uses a 2 m grid with a y=0.5 ground layer. The platform error falls from 0.139 to
0.059 and the crouched ramp-shadow reference from 3.15 to 0.31.

## Limits

- The renderer is one diffuse bounce. The three-bounce reference is the quality
  gap, not a gate.
- The reference is a diffuse estimator. It does not model specular GI, area
  lights, denoising, or the TAA resolve.
- The grid is 80 x 45 at 1280 x 720. A full-frame estimator was not worth the
  extra cost for a low-frequency field.
- The 2 m arena grid resolves the crate and platform contact. A sub-metre detail
  still needs a finer volume than the open arena warrants.
