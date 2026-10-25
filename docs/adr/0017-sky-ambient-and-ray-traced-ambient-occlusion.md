# Analytic sky and ray-traced ambient occlusion

> 0015 until 2026-10-24. The ground-speed ADR claimed 0015 first, so this one
> moved to 0017.

The renderer replaces the flat clear color with an analytic sky gradient. The
sky draws after the lit pass into the scene color and velocity targets, with a
depth test of `EQUAL` at the far plane, so it shades only the pixels that no box
covers. It writes the velocity of the direction at infinity, so TAA reprojects
the sky when the camera turns. The lit pass uses `sky_ambient(normal)` as the
ambient term: a two-colour hemisphere ramp on the surface normal, scaled to the
scene exposure. The same pass traces 8 cosine-weighted ambient occlusion rays
per fragment against the scene TLAS, out to 1.5 m, at strength 1.0. The visible
fraction scales the ambient term only where the sun does not reach the point.
The ray pattern rotates per pixel and per frame, and TAA accumulates the result.
Both features are on by default. The gated overrides `sky` and `ao` turn them
off for diagnosis.

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
- A sunlit surface in life is dominated by the direct sun, so the sky it loses
  is invisible. Our ambient is a fixed exposure at about a quarter of the sun,
  so the same occlusion reads as a dirty band on a sunlit floor. Gate the
  occlusion by the sun shadow fraction: the shade keeps the contact term and
  the sun keeps the full ambient. The gate reuses the sun visibility, so it
  adds no ray.
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
- The scene pass grew from 1.26 ms to 2.17 ms at 1440p, so it now owns most of
  the frame. Whole-GPU totals are 1.597 ms at 1080p, 2.611 ms at 1440p, 2.991 ms
  for the arena view at 1440p, and 1.438 ms for the backface view at 1080p. The
  same views cost 1.060, 1.697, 2.152, and 0.882 ms on the current base, so the
  feature adds 0.54, 0.91, 0.84, and 0.56 ms.
- AO costs about 0.91 ms extra at 1440p. That is 0.11 ms per ray at eight rays.
  The marginal ray cost falls as the count drops: four rays save 0.42 ms. The
  first rays carry a fixed traversal cost. Hemisphere rays are incoherent: each
  ray leaves the pixel in a new direction across the hemisphere. The 16 sun
  rays stay inside the 0.53° disk, so they stay coherent.
- A pixel that faces the sun still traces 24 rays: 16 sun rays and 8 AO rays,
  but the AO term is discarded in full sun. The AO pattern is stochastic. TAA
  averages it. With TAA off, the ambient term is noisy in shade.
- AO scales the ambient term only, and only in shade. It never dims the sun. A
  sunlit face keeps its full ambient; a corner in shade darkens. The gate uses
  the fraction of sun rays that reach the point, so a penumbra fades the
  occlusion in with the shadow. The sky pixels take no AO. A partial count is
  dithered inside its own step per
  `docs/adr/0024-visibility-count-dither.md`, so the 8-ray count no longer
  leaves contour bands in the shade.
- One diffuse bounce is still absent. AO is visibility, not transport, and the
  sun gate does not add bounce. A deep tunnel gets darker as it gets deeper.
  That is deliberate, not a bug.
- The sky ambient is scaled to the scene exposure, not to the visible sky
  radiance. The visible gradient is zenith (0.10, 0.20, 0.42) and horizon
  (0.52, 0.62, 0.74), with a sun disk and a glow at the sun's angular
  diameter. The
  ambient palette is (0.20, 0.24, 0.32) up and (0.10, 0.11, 0.13) down. One is
  not the integral of the other, so a change to the sky color does not move the
  ambient by itself.
- The sky writes velocity from the direction at infinity, so TAA reprojects the
  sky under camera rotation instead of blending unrelated pixels. The depth
  matches the clear value of the velocity target, so the resolve sees no depth
  jump at the skyline.
- The AO pattern changes the converged frame-to-frame mean.
  `scenarios/taa-motion.json` moves `capture.worst_mean_delta` from 0.03 to
  0.07. The measured value is 0.0433 of 255, or 0.017 percent. The
  `capture.worst_over_16_fraction` gate stays at 5e-06 and measures 2.17e-06
  at 1280x720. The mean gate is wider because the AO samples are stochastic;
  the shade-only gate removes the AO noise from the sunlit part.
- `scenarios/sky-ao.json` gates the image. Mean green: zenith 135.8 against a
  gate of at most 140, horizon 156.2 against a gate of at least 150, corner with
  AO off 69.9 against a gate of at least 64, and corner with AO on 53.5 against
  a gate of at most 58. With `sky: false` the zenith mean is 179. With the AO
  never re-enabled the corner mean stays 69.9. Either case makes the scenario
  exit 1. The scenario declares `requires.renderer_debug`.
- `scenarios/stairs-ao.json` gates the sun gate. At a 25° sun the sunlit floor
  is 144.5 with AO on and 144.5 with AO off, against a gate of at least 143 with
  AO on. The pre-fix value is 142.1, so the scenario fails on the old shader. The
  shaded wall is 75.2 with AO on and 109.4 with AO off, which proves the shade
  still gets the occlusion. The scenario declares `requires.renderer_debug`.
- `TAA_Debug` is now `Renderer_Debug`. The struct holds renderer inputs, not
  only TAA inputs.
- The render digest hashes `sky` and `ao`. A run that turns either off cannot
  share a digest with a run that leaves them on.
- `setup.renderer.ao_samples`, `setup.renderer.ao_radius`, and
  `setup.renderer.ao_strength` report the shader constants, so a change to any
  of them appears in `report.json` without a code read.
- The overrides are diagnostic only. `clear` restores both to true. With `sky`
  off, the lit pass uses the old flat ambient color and the background keeps
  the clear color.

The measurements are in `docs/evidence/sky-ao.md`. The literature behind the
choices, including GTAO, VBAO, SVGF, and the ray-traced shift, is in
`docs/research/ambient-occlusion.md`.
