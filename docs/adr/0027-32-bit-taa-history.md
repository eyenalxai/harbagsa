# A 32-bit TAA history

The resolve keeps a ping-pong history and a per-pixel sample count. Each new sample has weight one over the count plus one, up to 512. At that cap the update is small enough to disappear or drift when the accumulated colour is only 16-bit.

## Decision

`HISTORY_FORMAT` is `R32G32B32A32_SFLOAT`. Scene colour, velocity, and sample-count targets stay 16-bit. Capture readback handles the larger texel size.

## Considered Options

- **Lower sample cap**: keeps updates larger, but loses the long stable average.
- **16-bit history**: uses less memory and bandwidth, but loses small late-convergence updates to rounding.
- **A second accumulation path**: adds a target and composite for a problem that one wider history solves directly.

## Consequences

- Two history images cost more memory and resolve bandwidth than 16-bit images.
- The final image keeps its stability rather than the old lighting sampling behaviour.
- Output dither remains a separate final quantization step described by ADR 0020.
