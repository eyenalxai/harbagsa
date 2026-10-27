# Output dither for the 8-bit target

The scene colour is 16-bit and the TAA history is 32-bit. A smooth point-light gradient is continuous there. The resolve writes an 8-bit target, so quantization without dither turns shallow gradients into bands.

## Decision

Dither at the resolve, after the history update. The resolve encodes linear colour to sRGB, adds a stable per-pixel offset of 1.5 levels peak-to-peak, clamps, and decodes for the sRGB attachment. A linear fallback target writes the encoded value directly.

The exact sRGB transfer is used in both directions. The pattern depends on the pixel coordinate, not the frame. A static scene keeps the same quantization, and neither history nor scene colour contains the noise.

## Considered Options

- **A wider target**: reduces banding but changes swapchain negotiation, pipelines, captures, and readback for no current HDR requirement.
- **Pre-compensation in linear space**: makes the dither magnitude depend on the transfer approximation.
- **No dither**: leaves visible bands in shallow light gradients.

## Consequences

- The noise stays within one to two output levels and does not touch the HUD.
- The pattern is deterministic, so repeated scenario captures match.
- `analysis.bands` gates the defect. `scenarios/banding.json` measures a direct-lamp gradient at 1280x720.
- The output dither handles quantization only. It is not a lighting or visibility effect.
