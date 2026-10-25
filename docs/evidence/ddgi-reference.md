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

Renderer inputs: `taa`, `jitter`, and `ao` off. AO must be off because the
reference has no AO term; TAA and jitter are off so the two captures have
identical direct shading. The command rejects a run that leaves any of them on,
or that leaves the sky, point-light shadows, HUD, or menu in a state the
estimator does not model.

Budget: 48 paths per sample point, a 16-pixel stride, and 16 sun-disk samples at
the camera hit. The grid is 80 x 45 at 1280 x 720. A point is excluded when the
sky is hit, when a half-pixel neighbour hits a different box or a distance more
than 2 percent away, or when the reference indirect is below 1e-5. The RNG is a
fixed LCG, so a repeat run gives the same metrics.

## Result

One-bounce gate:

| Metric | Chamber | Lane |
| --- | ---: | ---: |
| used points | 3556 | 3347 |
| median ratio | 1.018 | 0.998 |
| ratio p10 / p90 | 0.860 / 1.287 | 0.550 / 1.627 |
| median error | 0.095 | 0.281 |
| energy ratio r, g, b | 1.024 / 1.031 / 1.032 | 0.976 / 0.992 / 1.010 |
| colour spread | 0.008 | 0.034 |
| zero GPU, reference lit | 0 | 0 |

Three-bounce advisory:

| Metric | Chamber | Lane |
| --- | ---: | ---: |
| median ratio | 0.559 | 0.447 |
| median error | 0.441 | 0.557 |
| colour spread | 0.100 | 0.118 |
| zero GPU, reference lit | 0 | 0.0003 |

The one-bounce reference matches the probe field. The three-bounce reference is
about twice as bright in the chamber and the lane, which is the expected gap
between one diffuse bounce and full multi-bounce transport.

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

After both fixes, zero-coverage is 0 in the chamber and 0.0003 in the lane, and
the one-bounce gate passes. The full core evidence is re-baselined in
`docs/evidence/ddgi.md`.

## Limits

- The renderer is one diffuse bounce. The three-bounce reference is the quality
  gap, not a gate.
- The reference is a diffuse estimator. It does not model specular GI, area
  lights, denoising, or the TAA resolve.
- The grid is 80 x 45 at 1280 x 720. A full-frame estimator was not worth the
  extra cost for a low-frequency field.
- The arena 4 m grid still shows soft perimeter blotches.
