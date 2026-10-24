# Ray-query sun shadows

The sun shadow traces rays against the scene instead of sampling a shadow map.
The renderer builds one BLAS for the unit cube and one TLAS per frame in flight
from the current box transforms. Each fragment traces one ray per sun sample to
a disk that matches the sun angular diameter and counts the unblocked rays.
There is no shadow map, depth bias, normal offset, PCF, or cascade.

## Why

- The 4096 shadow map over the 60 m arena gave 1.5 cm texels. At 2536x1386 the
  shadow shape and the PCF taps were visible as square blocks. A near cascade
  reduced the texel size, but the PCF tap footprint stayed.
- The scene is one cube mesh instanced as boxes. One BLAS and a small per-frame
  TLAS are cheap to build.
- The sun is a disk. Sampling the disk with rays gives the penumbra directly.
  Contact shadows are exact, and the penumbra grows with the blocker distance.
- Global illumination is still not involved. GI adds indirect light. The sun
  disk visibility is direct light.

## Considered Options

- **Fixed PCF or PCSS**: the shadow-map texel grid and the PCF tap footprint
  remain at close range.
- **Cascaded shadow maps**: reduce the texel size near the camera, but the PCF
  footprint, bias, and normal offset remain.
- **Variance shadow maps or ESM**: give a smooth blur, but they add light
  bleeding and do not give an exact shadow shape.
- **Analytic ray-box tests in the fragment shader**: no acceleration structures,
  but the full box list times the sun samples is too slow at high resolution.
- **Ray tracing pipeline with shaders**: a larger setup with a shader binding
  table. Ray queries in the lit shader need no extra pipeline.

## Consequences

- The device must support `VK_KHR_acceleration_structure` and
  `VK_KHR_ray_query`. The device selection rejects a device without them.
- The renderer builds the BLAS once and rebuilds each frame's TLAS from the box
  transforms. The TLAS build and the lit pass are in the same command buffer,
  separated by an acceleration-structure barrier.
- The lit pass costs 16 ray queries per pixel. TAA can average the sample
  pattern; without TAA the penumbra is slightly dithered.
- The sun angular diameter is a scene input, not a renderer constant. It sets
  the penumbra width directly: a wider disk softens every shadow. The demo uses
  the real 0.53°; a 3° disk softened a 4 m wall shadow by 3 m at a 15° sun,
  which read as a blur instead of a shadow. The harness can change the value
  with the `sun` command, so a scenario can compare two disks without a
  rebuild.
- A future light shape only needs a new sample-point function. The TLAS, ray
  query, and barrier stay the same.
