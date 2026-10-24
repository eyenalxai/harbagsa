# Shadow evidence

Captured on 2026-10-24 at 1280x720 with TAA on. GPU: AMD Radeon RX 9060 XT
(RADV GFX1200).

- Before: `main` at `d265599`. Percentage-closer soft shadows over a 4096
  shadow map.
- After: `fix/ray-query-shadows`. Ray-query sun shadows with 16 sun samples.

![before](shadows-before.png)

![after](shadows-after.png)

## Zoom

3x nearest-neighbor crop of the green crate and its shadow. The PCSS path
quantizes the shadow shape and the penumbra. The ray-query path has an exact
shape and a smooth penumbra. The remaining diagonal steps are screen pixels at
1280x720, not shadow-map texels.

![zoom comparison](shadows-zoom-compare.png)

## Checks

- `make check` passes.
- `make test` passes: 1 physics, 108 simulation, 7 frame, 28 harness, and 4
  renderer tests.
- `make validate` ran with `VK_LAYER_KHRONOS_validation` for 15 seconds. Both
  the offscreen and present scenarios passed with no `VUID` or `[ERROR]` lines.
