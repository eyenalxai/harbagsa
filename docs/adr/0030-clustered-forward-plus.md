# Clustered forward+ lighting

## Context

Every active point light was uploaded, and the lit shader looped all of them. The
loop cost grew with the whole scene, so a room with 64 lights traced 64 light
tests and up to 64 shadow rays per fragment, even when most lights were far away.
The target is interiors with many local lights.

## Decision

- Divide the view frustum into 16 x 9 x 24 clusters with logarithmic depth
  slices.
- A compute pass assigns each light to every cluster its range sphere overlaps.
  It writes a per-cluster count and a global light index list.
- The fragment shader derives its cluster from `gl_FragCoord` and view depth,
  then loops only that cluster's lights.
- The list uses a fixed stride of 256 indices per cluster. A cluster that
  overflows increments a counter. The renderer report exposes
  `cluster_overflow`.
- The cluster pass runs after the TLAS build and before the depth prepass. A
  compute-to-fragment buffer barrier publishes the lists.

## Why

- The per-pixel cost follows the lights that can reach the surface, not the
  lights that exist in the building.
- One compute dispatch handles the whole view. Per-object light lists would be
  wrong for a floor that spans many rooms.
- The fragment shader needs no G-buffer or deferred pass. The forward path stays.
- The light list is small and readable, so a light outside the view costs
  nothing per pixel.

## Considered Options

- **Keep the all-light loop.** Correct, and simple, but the cost grows with the
  scene. It was the state before this change.
- **2D tiles.** Cheaper to build, but a tile spans the whole depth range, so a
  long corridor keeps every light in front of the camera.
- **Per-object light lists.** A large floor object collects every light in the
  building.
- **A light BVH per pixel.** Better for thousands of lights, but it needs a
  traversal and a sampler per pixel. The cluster list is enough for rooms.
- **A bitmask per cluster.** A 64-bit mask is cheap, but it caps lights at 64.
  The target has more.

## Consequences

- The cluster pass costs about 0.005 ms with no lights and 0.04 ms with 64
  synthetic lights at 640 x 360. It is not pixel-bound.
- Each frame holds a 3.5 MB light index buffer per in-flight frame, plus the
  count buffer. The buffers are fixed because the grid is fixed.
- A cluster over 256 lights keeps the first 256 and increments
  `cluster_overflow`. The cap is a buffer bound, not a scene bound. The report
  makes it visible.
- Shadow rays are still one per light in the cluster. A shadow budget for the
  important lights is a later step.
- The room captures are byte-identical to the all-light path. The cluster list
  is conservative: a light is present when its range sphere overlaps the
  cluster.
- The pass order is now `Tlas -> Cluster -> Depth -> Scene -> Sky -> Taa ->
  Overlay`.
