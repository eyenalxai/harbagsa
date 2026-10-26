# Intermediate capture targets

A capture reads one image: the final color, the velocity target, the history,
the depth buffer, or the scene color. It writes one of four formats: PNG,
`float`, `raw`, or `stats`. The renderer owns the GPU copy. The harness owns
the file formats and the statistics.

## Why

The TAA investigation compared resolve inputs and outputs. Without a capture
target it had to patch a shader and decode the result with external Python.
The renderer already owns the images, their layouts, and the readback buffer,
so it is the only place that can copy them safely.

## Decisions

- One capture target per frame. The command names it; `color` with `png` is the
  default, so an existing scenario keeps its behavior.
- The renderer copies the image to the existing readback buffer and converts it
  to four `f32` values per pixel in RGBA order. Depth fills only `.x`. A color
  capture keeps 0..255 channel values; intermediate images are linear floats.
- The harness writes `png` for color, a `.f32` RGBA dump for `float`, the exact
  texel bytes for `raw`, and inline statistics for `stats`.
- The readback buffer is sized for the largest texel, eight bytes. The color
  path uses a prefix of it, so one buffer serves every target.
- Velocity statistics use the median over pixels with a covered depth. The
  clear value has zero motion and would otherwise dominate a background-heavy view.
- A color PNG keeps the delta baseline. Another target does not move it,
  because a delta between a color image and a depth image means nothing.

## Considered Options

- **Separate capture commands**: more names to learn and to record, for one
  readback path. A target field keeps one command.
- **A shader dump**: needs a storage buffer, a bind, and a shader variant. The
  transfer copy needs none of them and works for depth too.
- **PNG for every target**: loses the range that makes the velocity and history
  targets useful. `float` and `raw` keep it.
- **Per-pixel depth linearization on the GPU**: a second shader pass for a
  value the velocity target already stores in `.z`.

## Consequences

- An intermediate capture is a transfer copy plus one barrier. It does not
  change the rendered image.
- A raw file needs `target_format` from the report to decode.
- The depth target is the hardware depth buffer in 0..1. The linear view depth
  is in the velocity target's `.z`.
- The copy returns the history image to the sampler layout, so the next
  resolve reads it as before.
