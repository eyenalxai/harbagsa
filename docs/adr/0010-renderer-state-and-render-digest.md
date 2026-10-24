# Renderer state and render digest

The harness reports the renderer beside the simulation. `state.json` carries a
`renderer` object and a `render_digest`. `report.json` carries a `setup` block.
The simulation digest keeps its old meaning and its old field set.

## Why

A simulation digest cannot tell two renders apart. It does not see the camera
override, the jitter index, the shadow phase, the TAA history, or the overlay
flags. Two runs with the same player state can therefore draw different pixels.
The TAA investigation needs to assert those inputs before it compares images.

The renderer is the only component that knows the jitter and shadow phase it
applied, the history image it read, and the reset that last ran. The harness
therefore asks the renderer for a small report instead of guessing from the
scene.

## Decisions

- `renderer` holds the frame count, TAA state, jitter index, history validity,
  convergence frames, history read index, history weight, reset count, last
  reset reason, and shadow phase. The values describe the last frame the
  renderer recorded, not the next one.
- `render_digest` is FNV-1a over the effective camera, the sun direction, every
  box, the jitter, the shadow phase, and the view flags. If a frame has the same
  digest, its render inputs match.
- `history_weight` is the weight the next resolve would give the history,
  `count / (count + 1)`, from the renderer's convergence counter. A per-pixel
  count would need a readback; the scalar is enough to tell convergence from a
  reset.
- `setup` holds the target kind, the extent, the view flags, the device name,
  the frames in flight, and the TAA caps. It is written once per run.
- The simulation digest keeps its field set. Render fields never enter it.

## Consequences

- A check can read `renderer.*` and `render_digest`, so a scenario asserts the
  render inputs without a capture.
- A capture-free run with no renderer reports `renderer.active = false` and an
  empty `render_digest`. The object keeps its shape.
- The digest changes when the jitter or the shadow phase changes, so a static
  scene has a digest period of 64 frames, the larger of the two phases.
- Reset reasons make a history reset attributable. The enum is closed; a new
  reset source adds a reason instead of reusing one.
