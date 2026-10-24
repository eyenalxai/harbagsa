# Analytic sky and ray-traced ambient occlusion

The renderer replaces the flat clear color with an analytic sky gradient. The
sky draws after the lit pass into the scene color and velocity targets, with a
depth test of `EQUAL` at the far plane, so it shades only the pixels that no box
covers. It writes the velocity of the direction at infinity, so TAA reprojects
the sky when the camera turns. The lit pass uses `sky_ambient(normal)` as the
ambient term: a two-colour hemisphere ramp on the surface normal, scaled to the
scene exposure. The same pass traces 8 cosine-weighted ambient occlusion rays
per fragment against the scene TLAS, out to 1.5 m, at strength 1.0. The ray
pattern rotates per pixel and per frame, and TAA accumulates the result. Both
features are on by default. The gated overrides `sky` and `ao` turn them off for
diagnosis.

## Why

- The background was one flat color, and the ambient term was one flat color.
  The sky gave no cue for the sun direction, and the ambient term had no shape
  for ambient occlusion to darken.
- A gradient costs one fragment shader and no texture. The arena is 40 m of
  boxes, so the visible sky is a smooth ramp with one small sun disk.
- A scalar ambient turns a corner uniformly grey. The sky ambient adds the blue
  from above and the darker ground tone from below, so a floor and a ceiling do
  not darken by the same amount.
- The ray-query path already exists for the sun. The TLAS, the `occluded()`
  helper, and the `VK_KHR_ray_query` device requirement are in place. AO adds no
  new acceleration structure, no new pass, and no new target.
- A screen-space estimator cannot see an occluder outside the view. A player who
  faces a corner has the other wall behind the camera, and that wall is the one
  that should darken the corner.
- The prepass leaves depth 1.0 where no box covers the pixel. A sky draw with
  `EQUAL` at 1.0 therefore costs only the background. Drawn before the lit pass,
  the sky would shade every pixel, and the boxes would overwrite most of that
  work.
- The sky needs velocity. A direction at infinity moves across the screen when
  the camera turns, so the history sample must follow it. Without that motion,
  TAA blends pixels that show different parts of the sky.

## Considered Options

- **Ray-traced AO only, no GTAO or SSAO fallback.** Device selection already
  rejects a device without `VK_KHR_ray_query`, so a second estimator would serve
  no device that can run the renderer.
- **Analytic gradient, not a cubemap.** A cubemap adds a texture, a load path,
  and filtering. The arena is 40 m of boxes, so it buys no detail that the
  camera can see.
- **AO in the lit shader at full resolution, 8 rays.** The lit pass already
  holds the world position, the normal, the TLAS, and the ray-query loop. A
  separate pass would write the same inputs to a target and read them back.
- **Half-resolution AO with a separate G-buffer pass.** It needs a normal target
  and a new pass. Deferred until the frame budget needs it.
- **Four rays.** The whole-GPU total is 2.19 ms at 1440p, against 2.62 ms for
  eight rays, but the temporal noise doubles, so TAA needs more frames to reach
  the same image.
- **GTAO.** It cannot see the occluder behind the camera, which is the common
  case in a corner.
- **One diffuse bounce.** Out of scope. A bounce is a transport term and needs a
  denoiser. Ambient occlusion is a visibility term.
- **Sky before the lit pass.** It shades every pixel, and the boxes overwrite
  all but the background. The `EQUAL` test after the lit pass does the same work
  on the pixels that need it and on no others.
- **A user-facing switch.** The sky and the AO are part of the look, not a
  preference. The debug overrides are gated by `ENABLE_RENDERER_DEBUG` or
  `--debug-renderer`, per `docs/adr/0012-gated-renderer-debug-overrides.md`.
- **Keep the flat ambient.** It needs no sky pass and no new shader, but it
  gives ambient occlusion nothing directional to darken. It survives only as
  the `sky: false` fallback.

## Consequences

- The scene pass is now three scopes, not the two in
  `docs/adr/0014-scene-pass-depth-prepass-and-culling.md`: the depth prepass,
  the lit pass, and the sky pass. The sky scope loads color and velocity and
  leaves depth in the layout the prepass set.
- The scene pass grew from 0.80 ms to 2.17 ms at 1440p, so it now owns most of
  the frame. Whole-GPU totals are 1.596 ms at 1080p, 2.619 ms at 1440p, 3.023 ms
  for the arena view at 1440p, and 1.440 ms for the backface view at 1080p. The
  same views cost 0.77, 1.11, 1.19, and 0.55 ms before this feature.
- AO costs about 1.37 ms extra at 1440p. That is 0.17 ms per ray at eight rays.
  The marginal ray cost falls as the count drops: four rays save 0.43 ms, so
  the first rays carry a fixed traversal cost. Hemisphere rays are incoherent:
  each ray leaves the pixel in a new direction across the hemisphere. The 16 sun
  rays stay inside the 3° disk, so they stay coherent.
- A pixel that faces the sun now traces 24 rays: 16 sun rays and 8 AO rays. The
  AO pattern is stochastic. TAA averages it. With TAA off, the ambient term is
  noisy.
- AO scales the ambient term only. It never dims the sun. A corner darkens while
  its sunlit face keeps the same value. The sky pixels take no AO.
- One diffuse bounce is still absent. AO is visibility, not transport. A deep
  tunnel gets darker as it gets deeper. That is deliberate, not a bug.
- The sky ambient is scaled to the scene exposure, not to the visible sky
  radiance. The visible gradient is zenith (0.10, 0.20, 0.42) and horizon
  (0.52, 0.62, 0.74), with a sun disk and a glow at the 3° angular diameter. The
  ambient palette is (0.20, 0.24, 0.32) up and (0.10, 0.11, 0.13) down. One is
  not the integral of the other, so a change to the sky color does not move the
  ambient by itself.
- The sky writes velocity from the direction at infinity, so TAA reprojects the
  sky under camera rotation instead of blending unrelated pixels. The depth
  matches the clear value of the velocity target, so the resolve sees no depth
  jump at the skyline.
- The AO pattern changes the converged frame-to-frame mean.
  `scenarios/taa-motion.json` moves `capture.worst_mean_delta` from 0.03 to
  0.07. The measured value is 0.057 of 255, or 0.022 percent. The
  `capture.worst_over_16_fraction` gate stays at 5e-06 and measures 2.17e-06
  at 1280x720. The mean gate is wider because the AO samples are stochastic.
- `scenarios/sky-ao.json` gates the image. Mean green: zenith 135.9 against a
  gate of at most 145, horizon 154.7 against a gate of at least 145, corner with
  AO off 69.8 against a gate of at least 60, and corner with AO on 53.4 against
  a gate of at most 60. With `sky: false` the zenith mean is 179. With the AO
  never re-enabled the corner mean stays 69.8. Either case makes the scenario
  exit 1. The scenario needs `--debug-renderer`.
- `TAA_Debug` is now `Renderer_Debug`. The struct holds renderer inputs, not
  only TAA inputs.
- The render digest hashes `sky` and `ao`. A run that turns either off cannot
  share a digest with a run that leaves them on.
- `setup.ao_samples` and `setup.ao_radius` report the shader constants, so a
  change to either appears in `report.json` without a code read.
- The overrides are diagnostic only. `clear` restores both to true. With `sky`
  off, the lit pass uses the old flat ambient color and the background keeps
  the clear color.

The measurements are in `docs/evidence/sky-ao.md`. The literature behind the
choices, including GTAO, VBAO, SVGF, and the ray-traced shift, is in
`docs/research/ambient-occlusion.md`.
