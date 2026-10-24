# Performance instrumentation

The demo measures its own frame. One perf sample holds the frame interval, five
CPU phase durations from six ordered marks, and five GPU pass times from six
timestamps. The passes are the TLAS build, the depth prepass, the lit scene
pass, the TAA resolve, and the overlay pass. One timestamp query pool per frame
in flight serves the GPU timestamps, and the existing fence wait retires a slot
before the results are read. The renderer publishes the completed sample
through one procedure. The game loop and the harness perf run read the same
numbers. `F4` shows a summary line and a pass line.

## Why

- MangoHud reports the present interval and a system-wide block-busy counter.
  With FIFO the interval is the display refresh, and the counter does not see
  shader work. Neither can name the pass or the CPU stage that owns the time.
- The renderer owns the command buffer and the frame-in-flight bookkeeping, so
  it is the only place that can place accurate pass boundaries.
- Six timestamp writes per frame need no new synchronization. The fence wait
  at `begin_frame` already guarantees that a slot's previous submission is
  complete before the pool is reset and read.
- The CPU marks are clock reads in the existing loop. They add no allocation,
  no thread, and no frame of latency.

## Considered Options

- **MangoHud only**: no code, but only an external, system-wide view. It cannot
  separate the shadow shader from the resolve, and it cannot feed a check.
- **Tracy or another profiler**: a rich timeline, but a new dependency and
  instrumentation zones in every hot file. The per-pass numbers are already
  available from Vulkan, so the dependency buys little here.
- **Build-time-only instrumentation**: keeps release builds clean, but the
  numbers would be missing exactly when a release build is measured, and the
  harness would carry a second code path.
- **One timestamp pair per frame**: cheaper by four timestamp writes, but it
  cannot say which pass owns the time, which is the question that started the
  work.
- **Present wait and present IDs**: exact presentation timing, but the wait
  perturbs the pacing it measures. The frame interval and the present-call
  duration answer the pacing question for now.

## Consequences

- Timestamps are always recorded when the device supports them. `F4` only
  controls display, so the line has data the moment it opens.
- A slot reports the frame it measured, which is two frames older than the
  frame being recorded. The overlay and the report describe it as the last
  completed sample.
- A device with no timestamp support, a failed query pool, or a run with no
  device reports the CPU numbers and marks the GPU fields unavailable. Nothing
  fails.
- The overlay and any harness report derive from the same statistics procedure,
  so two surfaces cannot disagree.
- Perf data never enters the simulation state, the state digest, the pixel
  hash, or the recorded command stream.
