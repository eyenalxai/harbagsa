# Scene pass culling and depth prepass

The scene pass draws every box twice: a depth-only prepass writes the nearest surface, then the lit pass shades only fragments that match that depth. Both passes cull back faces.

## Why

- Point-light loops should run for the visible surface, not for back faces or fragments hidden behind a nearer box.
- Every box is a closed cube, so back-face culling is exact.
- The prepass pays only vertex and raster cost for a 24-vertex cube.

## Considered Options

- **Frustum culling alone**: reduces draw work but does not remove overlapping fragment shading.
- **Culling alone**: removes back faces but leaves overdraw.
- **Deferred lighting**: adds a G-buffer and another material path for no requirement in this renderer.

## Consequences

- The scene pass has two render scopes: depth, then colour and velocity.
- Every scope is a `renderer.Pass`. `record_pass` is the only begin/end/viewport site, and `perf.PASS_ORDER` is the shared recording and timing order.
- A depth barrier orders prepass writes before lit reads.
- The lit pipeline writes no depth and compares `LESS_OR_EQUAL`.
- `box.frag` declares `early_fragment_tests`, so depth testing happens before point-light loops.
- The overlay and debug pipelines keep both faces.
- The prepass cost follows covered area, so hidden boxes do not multiply light work.
