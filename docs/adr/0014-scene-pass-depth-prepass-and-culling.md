# Scene pass culling, depth prepass, and sun-facing rays

The scene pass draws every box twice: a depth-only prepass writes the nearest
surface, then the lit pass shades only fragments that match that depth. Both
passes cull back faces. A fragment whose normal faces away from the sun skips
the sun rays.

## Why

- The lit pass traces 16 rays per fragment. The rays dominate the pass, and the
  old path traced them for fragments the frame never shows: the back faces of
  closed boxes, fragments hidden behind a nearer box, and faces with no direct
  sun.
- The frame cost grew with the number of boxes in view. The measured cost is per
  covered fragment, so back-face area and overdraw multiplied it.
- Every box is a closed cube, so back-face culling is exact: the visible surface
  is always a front face.
- A face with `dot(normal, to_light) <= 0` receives no direct sun, so skipping
  its rays is exact. The old path still traced them and multiplied the result
  by zero.
- The prepass pays vertex and raster cost only. The box is a 24-vertex cube, so
  that cost is small next to a ray per fragment.

## Considered Options

- **Half-resolution shadow mask**: traces a quarter of the rays, but softens
  contact shadows and adds a target, a pass, an upsample, and a second set of
  bindings. Deferred: the lossless changes already clear the frame budget.
- **Fewer sun samples**: cuts the ray count, but trades penumbra quality and
  needs TAA to hide the noise. Without TAA the penumbra dithers.
- **Frustum culling of boxes**: helps the CPU draw list and the vertex stage,
  not the fragment stage that owns the time.
- **Culling alone**: removes the backface cost, but leaves the overdraw. The two
  changes together are measured in the evidence.

## Consequences

- The scene pass is two render scopes: a depth-only scope that clears depth,
  then a color scope that loads depth and clears color and velocity.
- The depth image is shared by both scopes. A late-fragment-test to
  early-fragment-test barrier orders the prepass writes before the lit reads.
- The lit pipeline writes no depth and compares `LESS_OR_EQUAL`. Coplanar
  surfaces resolve to the last draw, so a few edge pixels differ from the old
  path.
- `box.frag` declares `early_fragment_tests`, so the depth test is guaranteed to
  run before the ray queries.
- The cube's front face is counter-clockwise. Culling is opt-in per pipeline;
  the overlay and debug pipelines keep both faces.
- The prepass cost follows the covered area, not the box count, so adding crates
  does not grow the per-pixel lighting work.
- The remaining scene cost is the 16 rays on visible pixels. The evidence
  records the measured headroom and the half-resolution option.
