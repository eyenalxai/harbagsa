# Performance instrumentation

> The TLAS pass adds a sixth GPU pass. See [ADR 0040](0040-hard-point-light-shadows.md). [ADR 0045](0045-mixed-static-baked-indirect.md) removes the probe pass.

The demo measures its own frame. One perf sample holds the frame interval, five CPU phase durations from six ordered marks, and one GPU pass time per timestamped pass. The passes are TLAS, cluster assignment, depth prepass, lit scene, TAA resolve, and overlay. One timestamp query pool per frame in flight serves the GPU timestamps. The existing fence wait retires a slot before the results are read.

## Why

- External overlays cannot name the pass or CPU stage that owns the time.
- The renderer owns the command buffer and frame-in-flight bookkeeping, so it is the only place that can place accurate pass boundaries.
- Six timestamp writes need no new synchronization. The fence wait at `begin_frame` already guarantees that a slot's previous submission is complete.
- The CPU marks add no allocation, thread, or frame of latency.

## Considered Options

- **External profiler**: useful for deep analysis, but a new dependency is not needed for five pass boundaries.
- **Build-time-only instrumentation**: would hide the numbers in the release build that performance work needs to measure.
- **One timestamp pair per frame**: cannot say which pass owns the time.

## Consequences

- Timestamps are always recorded when the device supports them. `F4` only controls display.
- A slot reports the last completed frame, not the frame being recorded.
- A perf run primes the device before warmup. Prime frames stay out of the trace and statistics.
- A run keeps every named perf result in `report.json`. Each duration carries `p50`, `p95`, and `mean`.
- A device without timestamp support reports CPU numbers and marks GPU fields unavailable.
- The overlay and harness reports derive from the same statistics procedure.
- Perf data never enters the simulation state, state digest, pixel hash, or recorded command stream.
