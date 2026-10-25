# DDGI probe volumes

## Context

The renderer had no indirect diffuse term. Sunlight and point lights were direct
only, and ambient occlusion scaled that direct light. A surface inside a room
that no lamp reached stayed black, and a lamp could not light around a corner.
The target is interiors with many local lights and no sun.

## Decision

- Probe volumes are scene data. A volume has a minimum corner, spacing, a 3D
  count, and a probe offset. The first volume covers the room, its lane network,
  and the chamber: 10 x 3 x 10 probes at 1.04 m spacing.
- Each probe stores an 8 x 8 octahedral irradiance map and an 8 x 8 depth-moment
  map. Irradiance is RGBA and depth is distance plus distance squared.
- A compute pass traces one ray per octahedral texel, 64 rays per probe. It
  shades the hit with the sun, the point lights, and the emissive surface. A miss
  returns the sky gradient. Point-light shadows use the same mask as the lit
  pass, so a lamp does not block its own light.
- Every probe updates every frame. A new value replaces the old one on the first
  frame and after a light or sun change; otherwise it blends with an alpha of
  0.25.
- The lit pass samples the eight probes around the surface. It weights them by
  trilinear position, surface facing, inverse square distance, and Chebyshev
  depth visibility.
- `camera.probe` carries the volume count, probe count, and the GI debug flag.
  The probe buffers and scene descriptor bindings live with the existing scene
  resources.

## Why

- One volume per room is the unit that keeps light inside a room. A single
  arena-wide grid would carry the arena into every room.
- One ray per texel gives the 64 rays per probe the design calls for without a
  second loop.
- Depth moments reject a probe behind a wall during sampling. They do not fix a
  probe grid that straddles a wall; that is the leak-control ticket.
- The probe pass is 0.116 ms with 300 probes and 64 synthetic lights at
  1280 x 720. Updating every probe is cheap enough to be the default.

## Considered Options

- **Baked lightmaps.** Better for static geometry, but the lamps move.
- **A single world grid.** Simpler to address, but it leaks across every wall and
  wastes probes outside the playable rooms.
- **Screen-space GI.** Cheap, but it cannot light a surface the camera does not
  see, which is the whole point of a room around a corner.
- **One ray per probe.** Too coarse; the octahedral map needs the 64 directions.
- **Round-robin probe updates.** Lower cost, but a moving lamp would show a slow
  wave. The first slice updates all probes and pays 0.116 ms.

## Consequences

- The room is brighter with the lamp on and stays dark without it. The GI debug
  toggle captures the same scene with and without the indirect term.
- The probe atlas is 1.5 KB per probe: 1 KB irradiance and 0.5 KB depth. The
  first volume holds 300 probes, about 450 KB per in-flight frame.
- A light, sun, or volume change resets the blend to a full replace. Moving
  geometry does not reset the probes yet; a crate that moves inside a lit room
  keeps stale indirect until a light changes. The leak-control ticket owns that
  dirty state.
- The volume covers the whole room, including internal walls. The depth test
  rejects back-facing probes, but a probe on the other side of a thin wall can
  still leak. Per-room classification, relocation, and a leak pair are the next
  ticket.
- The pass order is now `Tlas -> Cluster -> Probe -> Depth -> Scene -> Sky ->
  Taa -> Overlay`.
