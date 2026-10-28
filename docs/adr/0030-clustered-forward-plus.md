# Clustered forward+ lighting

Every active point light is uploaded. An all-light fragment loop would scale with the whole scene, even when most lights are out of range. Clustered forward+ keeps the direct-light path while limiting that loop.

## Decision

- Divide the view frustum into 16 x 9 x 24 clusters with logarithmic depth slices.
- A compute pass assigns each light to every cluster its range sphere overlaps. It writes a count and global light index list.
- The fragment shader derives its cluster from `gl_FragCoord` and view depth, then loops only that cluster's lights.
- The list has a fixed stride of 256 indices per cluster. Overflow increments `cluster_overflow` in the renderer report.
- The cluster pass runs before the depth prepass. A compute-to-fragment barrier publishes the lists.

## Why

- Per-pixel cost follows lights that can reach the surface, not every light in the arena.
- One dispatch handles the view. Per-object lists would overfill for large floors and walls.
- The forward path needs no G-buffer or deferred material pass.

## Considered Options

- **All-light loop**: simple, but cost grows with total scene lights.
- **2D tiles**: a tile spans the whole depth range and keeps too many lights in long views.
- **Per-object lists**: large geometry collects lights that affect only a small part of it.
- **A fixed bitmask**: caps the light count at the mask width.

## Consequences

- The index buffers are fixed because the grid is fixed. Object and light upload buffers still grow on demand.
- A cluster over 256 lights keeps the first 256 and reports the overflow.
- The pass order is `Cluster -> Depth -> Scene -> Taa -> Overlay`.
- A synthetic light field covers 32 and 64 lights and measures direct-light cost.
