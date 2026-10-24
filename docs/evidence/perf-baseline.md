# Performance baseline

Measured on 2026-10-24 from branch `add-gpu-frametime-instrumentation`, after
the perf command, the report, and the trace landed. Machine: AMD Radeon RX 9060
XT (RADV GFX1200), Mesa 26.2.5, Hyprland on Wayland. Displays: `HDMI-A-1`
1920x1080 at 60 Hz, `HDMI-A-2` 2560x1440 at 74.97 Hz, VRR off.

> These tables are the pre-optimization baseline. The scene pass changed later
> on 2026-10-24; the before/after is in
> [the scene pass evidence](perf-scene-pass.md).

## Method

`scenarios/perf.json` runs one priming frame, 60 warmup frames, and 120 measured
frames. Each frame steps the simulation once and draws once.

- **Offscreen** (`--size WxH`) measures throughput: nothing waits for the
  display, so the interval is the cost of the frame.
- **Present** (`--present --size WxH`) measures pacing: FIFO waits for the
  display, so the interval is quantized to the refresh.

The harness window is compositor-controlled. The requested size is not a
guaranteed display mode; the measured refresh in the table is the evidence of
where the window landed.

Reproduce:

```sh
./bin/harbagsa-agent run scenarios/perf.json --size 1920x1080 --out runs/perf-cpu
./bin/harbagsa-agent run scenarios/perf.json --present --size 1920x1080 --out runs/perf-present
```

## Pass cost, offscreen throughput

| Size | Interval p50 | p95 | p99 | TLAS | Scene | TAA | Overlay | GPU total | CPU record |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1920x1080 | 1.80 | 1.89 | 1.93 | 0.18 | 1.46 | 0.15 | 0.00 | 1.79 | 1.77 |
| 2560x1440 | 3.07 | 3.23 | 3.30 | 0.17 | 2.50 | 0.26 | 0.00 | 2.93 | 2.91 |

All values are milliseconds, means over the measured window. `CPU record` is
the build-to-record phase, which includes the fence wait. No offscreen interval
was a spike.

The captures are not committed. Reproduce them with the commands above; the
overlay shows the pass row and the costliest pass, not the pacing.

## Pacing, present

Two runs of the same command produced different pacing. The difference is where
the compositor placed the window.

Run A, the spiky run:

| Window | Output | p50 | p95 | p99 | Max | Spikes | GPU total | CPU record |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1920x1080 | 75 Hz | 13.34 | 26.68 | 26.86 | 26.88 | 11 | 0.90 | 14.48 |
| 2560x1440 | 60 Hz | 16.66 | 16.92 | 33.33 | 33.36 | 3 | 0.52 | 17.01 |

Run B, the clean run:

| Window | Output | p50 | p95 | p99 | Max | Spikes | GPU total | CPU record |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1920x1080 | 60 Hz | 16.66 | 16.82 | 16.87 | 17.08 | 0 | 1.07 | 16.58 |
| 2560x1440 | 60 Hz | 16.67 | 16.81 | 16.88 | 16.93 | 0 | 1.08 | 16.58 |

A spike is an interval above 1.5 times the median. In Run A the 75 Hz p95 and
the 60 Hz p99 are two refreshes: those frames missed one vblank.

Traces from Run A: [75 Hz](perf/present-75hz-trace.jsonl) and
[60 Hz](perf/present-60hz-trace.jsonl).

## What the numbers say

1. **The GPU is not the bottleneck.** At 2560x1440 the four passes cost 2.93 ms
   in total, about 18% of a 60 Hz frame and 22% of a 75 Hz frame. At 1920x1080
   the total is 1.79 ms. The costliest pass is the scene pass, which traces the
   sun rays: 1.46 ms at 1080p and 2.50 ms at 1440p. The TLAS build is 0.17 to
   0.18 ms, the TAA resolve 0.15 to 0.26 ms, and the overlay about 0.002 ms.
2. **The frame is present-bound.** In the present runs the CPU spends 14.48 to
   17.01 ms in the record phase. That phase waits on the previous submission's
   fence, so it is the display, not CPU work.
3. **The pacing varies between identical runs.** Run A dropped 11 of 120 frames
   at 75 Hz and 3 of 120 at 60 Hz. Run B dropped none. The renderer and the
   simulation were the same; the compositor placed the windows differently.
4. **The GPU-load reading is not saturation.** A block-busy counter samples the
   short ray-query burst every frame. The pass times show the headroom that the
   counter hides.

## Ranked causes

1. **Present and compositor pacing.** The frame rate is the display refresh,
   and the misses are dropped vblanks. The same command produced a clean run
   and a spiky run, so placement and scheduling decide the pacing. The mixed
   60 Hz and 75 Hz outputs make the compositor schedule against two clocks.
2. **Two frames in flight with FIFO.** The CPU can be a frame or two ahead of
   the display, which adds latency and makes a miss wait for the next vblank.
3. **GPU cost at higher resolution.** The scene pass grows from 1.46 ms to
   2.50 ms between 1080p and 1440p. It is still far below the budget, but it is
   the first pass to watch if the target rises. The scene pass has since been
   optimized without changing the sample count; see
   [the scene pass evidence](perf-scene-pass.md).
4. **The external GPU-load counter.** It is not a saturation signal and must
   not be used as one.

## Limitations

- The harness window is compositor-controlled, so a run can land on either
  output. A display-targeted harness option is the next step for a controlled
  per-display baseline.
- These runs are headless apart from the present runs. The game overlay on the
  real window is the check for input and cursor capture.
- VRR was off. A VRR run would change the interval distribution.

## Next

The fixes are separate tickets: a display-targeted present run, a decision on
the present mode and frames-in-flight policy, and a presentation-time
measurement as a follow-up. Reducing the 16 sun samples is a quality trade-off,
not a pacing fix.

The scene pass was later optimized without reducing the sample count. The
before/after and the two regression probes are in
[the scene pass evidence](perf-scene-pass.md).
