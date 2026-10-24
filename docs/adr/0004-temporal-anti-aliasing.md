# Temporal anti-aliasing

The renderer reserves temporal inputs: a jittered clip position, per-object velocity, and a ping-pong RGBA16F history with a per-pixel sample count. The scene renders to linear offscreen color, velocity, and depth targets. A fullscreen resolve compares the history depth with the current 3x3 depth range, clamps the history in YCoCg, averages the sample with weight one over the count plus one, and writes the swapchain, the next history, and the next count. The neighborhood range keeps the history valid when jitter moves a geometry edge across a pixel; a real disocclusion still falls outside the range. The HUD and debug lines draw after the resolve, so they stay crisp. `F3` toggles TAA because the debug mode uses `F2`.

This supersedes the sentence in ADR-0002 that says the renderer does not reserve temporal inputs.

## Considered Options

- **MSAA**: it anti-aliases geometry edges, but not the HUD or debug lines, and it multiplies the color and depth sample cost. It also does not reduce the aliasing that remains after the forward pass.
- **FXAA or SMAA**: spatial filters blur the image and still shimmer on thin edges. They do not use the scene motion.
- **Camera-only TAA**: depth reprojection handles the camera, but moving crates smear because their own motion is missing.
- **No temporal AA**: the demo keeps hard box and wall edges at 1280x720.

## Consequences

- The scene renders offscreen at `R16G16B16A16_SFLOAT`. The scene, velocity, history, and count targets cost about 60 MB at 1280x720; the two count targets add about 4 MB.
- The scene descriptor set carries a per-frame object storage buffer with the current and previous model matrices. The box fragment shader writes the previous-to-current screen motion in unjittered UV space and linear view depth. Both ends of the velocity use the same projection space, so a still camera produces zero screen motion.
- The history resets on the first frame, a swapchain extent or format change, `F3` on, `R`, a fall reset, a camera teleport, and a crate add or remove. A reset starts the count at 1, so the first samples enter with new-sample weights 1/2, 1/3, 1/4, and so on. The count follows the reprojected surface; a depth rejection resets it to 1. The count stops at 512, which leaves the phase weights within a jitter cycle nearly equal and removes the visible ripple.
- TAA costs one fullscreen resolve pass. The demo keeps 60 fps at 1280x720 on the target machine.
