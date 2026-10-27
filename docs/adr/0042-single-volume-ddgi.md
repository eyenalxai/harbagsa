# Single-volume DDGI indirect light

The renderer adds one diffuse bounce from the current point lights. A single probe volume covers the arena. Each probe traces 64 rays, stores an 8 x 8 octahedral irradiance and depth atlas, and surfaces blend the eight surrounding probes. The direct term and the probe term both use the same lamps. There is still no ambient floor.

## Why

- The owner wants to know how games light surfaces that direct light misses. A dark corner beside a lamp is the gap.
- A constant ambient fill is a default light. It is not transport and it hides missing lamp coverage. ADR 0041 removed it.
- Screen-space GI needs a depth and normal prepass, fails at screen edges, and cannot see a light behind the camera. Reflected light from a nearby wall is exactly the case that fails.
- One bounce is enough for the flat box look. Two or more bounces add cost and a long settling tail for little visual gain.
- The renderer already had a multi-volume DDGI implementation. This change reuses its octahedral maps, depth moments, and sampling math, but keeps one volume and one bounce.

## Decisions

- Add one arena volume: `min = [-20, -0.5, -20]`, spacing 2 m, counts 20 x 3 x 20. The 1200 probes sit at y = 0.5, 2.5, and 4.5.
- Trace 64 rays per probe. Use a fixed spherical Fibonacci set, so the result is stable and needs no per-frame noise.
- Store 8 x 8 irradiance and depth per probe. Encode irradiance with gamma 5.0 and store first and second depth moments.
- Shade a probe ray hit with the current point lights and the box emissive term. Use the same hard shadow test as the lit pass.
- A miss returns zero. There is no sky, sun, or environment term.
- Blend all 64 rays into every octahedral texel. The old hysteresis is retained for a light change.
- Mark a probe inside any box invalid. Skip it in the ray, blend, and gather passes.
- Reject a probe behind the shaded surface in the gather. The depth test alone lets a probe on the far side of a thin wall agree on distance and carry light across the wall. The facing weight removes that leak.
- Add a `Probe` compute pass after the TLAS and cluster passes. Add descriptor bindings 6 to 10.
- Add `camera.probe`: volume count, probe count, and GI flag. The camera uniform grows to 256 bytes.
- Add a gated `gi` debug override, default true.
- Add `probe_indirect` to the lit formula:
  `albedo * (direct_point_lights + probe_indirect) + albedo * emissive`.
- Keep the current 96-light target. The probe pass loops all current lights; measure it, do not assume the old light count.

## Considered Options

- **Keep the ambient floor.** Rejected by the owner. It is a constant fill and not transport.
- **Screen-space one-bounce GI.** Rejected. It fails at screen edges and cannot use off-screen lamps.
- **Per-pixel ray-traced GI.** Rejected. A path per pixel plus a denoiser costs more than a probe update and does not fit the 96-light budget.
- **Multi-volume DDGI.** Deferred. The arena is one closed box. One volume is enough now; a room transition will need a volume per room or a portal decision.
- **Baked probes or a lightmap.** Rejected. Lamps move and the arena is editable.
- **Two or more bounces.** Deferred. One bounce covers the visible corner and wall cases. More bounces need a quality budget first.
- **A sky or sun term.** Rejected. The arena is closed and the direct model has no sun.

## Consequences

- The probe pass costs about 0.76 ms at 96 lights and 1080p. The gather adds about 0.58 ms to the scene pass. The paired full-frame cost is about 1.29 ms.
- Probe memory is about 6 MB for the two in-flight buffers.
- A 2 m probe grid cannot resolve a detail smaller than 2 m. The flat box scale hides most of it.
- A thin wall still has probes on both sides. The facing weight and the depth test stop the large leak; a very thin wall remains the case to watch.
- The probe field follows a moving lamp after a light hash reset. A moved crate changes the field on the next frame without a full reset.
- The 2 m spacing and 64 rays are the current quality budget. A denser grid or more rays is a new decision with a new measurement.
- This changes the "no GI or probe" sentence in ADR 0041. The no-ambient-floor decision stays in force.

## Evidence

`scenarios/gi.json` pairs GI on and off on a lamp around a corner. The green-channel mean moves from 98.66 to 123.80, and the zero-pixel fraction from 0.239 to 0.000. `scenarios/gi-dark.json` proves the lamp-free view stays at 0.165. `scenarios/gi-move.json` moves the lamp and changes the image. `scenarios/gi-sealed.json` encloses the camera and checks that GI adds no light through the wall. `scenarios/perf-gi.json` measures the paired 96-light cost.

## Test plan

- Renderer tests: the digest covers the volume and the `gi` flag; the pass list includes `Probe`; the debug table includes `gi`.
- Lighting suite: `gi`, `gi-dark`, `gi-move`, and `gi-sealed`.
- Performance: three paired runs of `perf-gi.json` at 1080p with 96 lights.
