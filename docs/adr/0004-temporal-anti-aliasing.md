# Temporal anti-aliasing

The renderer reserves temporal inputs: a jittered projection, per-object velocity, and a ping-pong RGBA16F history. The scene renders to linear offscreen color, velocity, and depth targets. A fullscreen resolve clamps the history in YCoCg, rejects it by depth, and writes the swapchain and the next history. The HUD and debug lines draw after the resolve, so they stay crisp. `F3` toggles TAA because the debug mode uses `F2`.

This supersedes the sentence in ADR-0002 that says the renderer does not reserve temporal inputs.

## Considered Options

- **MSAA**: it anti-aliases geometry edges, but not the HUD or debug lines, and it multiplies the color and depth sample cost. It also does not reduce the aliasing that remains after the forward pass.
- **FXAA or SMAA**: spatial filters blur the image and still shimmer on thin edges. They do not use the scene motion.
- **Camera-only TAA**: depth reprojection handles the camera, but moving crates smear because their own motion is missing.
- **No temporal AA**: the demo keeps hard box and wall edges at 1280x720.

## Consequences

- The scene renders offscreen at `R16G16B16A16_SFLOAT`. The scene, velocity, and two history targets cost about 30 MB at 1280x720.
- The scene descriptor set carries a per-frame object storage buffer with the current and previous model matrices. The box fragment shader writes the previous-to-current UV motion and linear view depth.
- The history resets on the first frame, a swapchain extent or format change, `F3` on, `R`, a fall reset, a camera teleport, and a crate add or remove. The history weight ramps from 0.5 to 0.75 to 0.9 after a reset.
- TAA costs one fullscreen resolve pass. The demo keeps 60 fps at 1280x720 on the target machine.
