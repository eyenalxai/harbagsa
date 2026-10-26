# TAA evidence

Evidence is a run directory plus a scenario. The current checks do not depend on a particular lighting effect. They measure reprojection, accumulation, and stability of the final colour image.

## Still camera

`scenarios/taa-static.json` settles for 520 frames, then captures a steady sequence. It gates `capture.worst_mean_delta` and `capture.worst_over_16_fraction`. The settle reaches the 512-sample cap, so the checks measure the stable image rather than initial convergence.

## After motion

`scenarios/taa-motion.json` moves the camera through the arena, turns, and holds. It captures the hold sequence after warmup and applies the same stability gates. The per-pixel history count must reconverge after disocclusions instead of retaining an old edge pattern.

## Debug controls

`scenarios/renderer-state.json` checks TAA state, history validity, convergence, jitter, and render digest. `scenarios/renderer-debug-converge.json` checks stability with jitter disabled. `scenarios/renderer-debug-jitter.json` checks the eight-phase jitter period with jitter enabled. `scenarios/renderer-reset.json` covers history resets.

## History precision

The history is `R32G32B32A32_SFLOAT`; scene colour, velocity, and count targets stay 16-bit. The wide history preserves small updates near the 512-sample cap. The decision is [ADR 0027](../adr/0027-32-bit-taa-history.md).

Output dither is a separate final quantization step. `scenarios/banding.json` measures it on a direct-lamp gradient. See [ADR 0020](../adr/0020-output-dither-for-the-8-bit-target.md).

## Reproduce

```sh
tools/make.sh build
./bin/harbagsa-agent suite renderer --out runs/renderer
./bin/harbagsa-agent checks runs/renderer/taa-static
./bin/harbagsa-agent checks runs/renderer/taa-motion
```

The run directories hold frames and `analysis.json`. Do not commit the images.
