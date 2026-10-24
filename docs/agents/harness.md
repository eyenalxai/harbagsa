# Agent harness

`bin/harbagsa-agent` drives the simulation, runs checks, and writes exact
screenshots. It needs no window, compositor, cursor capture, or `grim`.

The user-facing command reference is `README.md` under **Agent harness**. This
page is the short operational guide for agents.

## First move

```sh
tools/make.sh build
./bin/harbagsa-agent --help
./bin/harbagsa-agent run scenarios/smoke.json
```

`--help` and `-h` print the command list and exit 0.

Read `runs/smoke/report.json`. Use the absolute paths in `screenshots`. Exit
code 0 means every check passed.

Use `tools/make.sh` when another agent may build in the same checkout. It
serializes Make with `flock`.

## Surface map

| Task | Read |
| --- | --- |
| drive the simulation | **Scenario format** and **Commands** |
| capture the final image | **Capture targets** (`color` + `png`) |
| read velocity, history, depth, or scene color | **Capture targets** |
| read numeric image statistics | **Capture targets** (`stats`) |
| read renderer state or the render digest | **Renderer state** |
| change a renderer input for a diagnosis | **Renderer debug overrides** |
| check the sky and the ambient occlusion | **Sky and ambient occlusion** |
| measure image stability or the period | **Analysis** |
| compare two builds or revisions | **Cross-run diff** |
| measure frame time | **Performance** |
| prove a capture-free sequence is deterministic | **Screenshots** and `scenarios/capture-free.json` |
| understand a design choice | `docs/adr/0008` to `docs/adr/0016` |

## What one run writes

`runs/<scenario-stem>/`

- `report.json`: `ok`, `exit_code`, `frame`, `state`, `setup`, `screenshots`,
  `checks`, `failures`, `digest`, `error`, `perf` (a list of named reports) when
  perf ran, `trace` when the run wrote a perf trace, and `analysis` when the run
  wrote an analysis report.
- `analysis.json`: the per-run image analysis. See **Analysis**.
- `frames/analysis-diff.png` and `frames/analysis-variance.png`: the optional
  analysis maps.
- `trace.jsonl`: one JSON object per measured frame, when the perf command asks
  for a trace.
- `state.json`: the final state alone. It holds the player, crates, window and
  input settings, debug mode, sun, menu, frame, renderer, render digest, and
  simulation digest.
- `frames/<name>.png`, `.f32`, or `.bin`: captures. A color capture is a PNG;
  `float` and `raw` write the intermediate target.
- Each screenshot entry carries `delta_mean`, `delta_max`, and `delta_over_16`
  against the previous capture. The first capture has zeros.
- `run.log`: log lines from the renderer, the session, and the runner.

Standard output is one JSON summary. Standard error holds logs. `--verbose` (or
`--summary`) adds a human summary to standard error: the setup revision and
dirty flag, every capture, every check result, every failure, and every named
perf result. The JSON line on standard output does not change.

Exit codes:

- `0`: pass.
- `1`: a check or an invariant failed.
- `2`: bad arguments or a bad scenario.
- `3`: render/init or file I/O failed.

## Scenario format

```json
{
  "view": {"hud": false, "debug": false, "hint": false, "perf": false},
  "commands": [
    {"cmd": "look", "dx": 220, "dy": 0},
    {"cmd": "input", "forward": 1},
    {"cmd": "step", "frames": 90},
    {"cmd": "input", "jump": true},
    {"cmd": "step", "frames": 1},
    {"cmd": "capture", "name": "after-jump"}
  ],
  "checks": [
    {"field": "crates.0.position.z", "op": "lt", "value": 7.5}
  ]
}
```

Rules:

- The scenario has one body form: `commands`. It runs verbatim, and `record`
  writes the same form.
- `step` advances one `SIMULATION_STEP` (1/60 s) per frame. The harness does not
  use wall-clock time.
- `look` applies once. `input` persists until the next `input`; `jump` is an
  edge on the next step.
- Only a `capture` command captures. A scenario with no `capture` and no perf
  run does not create a renderer unless `--present` asks for the window.
- A check uses the `state.json` shape. Operators: `eq`, `ne`, `lt`, `le`, `gt`,
  `ge`. Examples: `player.position.y`, `crates.count`, `settings.window_mode`,
  `settings.resolution`, `settings.sprint_mode`, `settings.type_weight`, `menu.open`.
- A capture check reads the capture summary. Fields: `capture.count`,
  `capture.worst_mean_delta`, `capture.worst_max_delta`,
  `capture.worst_over_16`, and `capture.worst_over_16_fraction`. The fraction
  scales with the capture size. Each capture after the first compares its
  pixels with the previous capture. `warmup` skips that many captures before
  the summary, so a scenario can ignore TAA convergence.
- A check window selects captures instead: `"window": {"start": 2, "count": 8}`.
  `capture.count` is the window's count and every capture field aggregates only
  the window. `warmup` and `window` cannot be combined.
- A scenario-level `analysis` object controls the analysis report. `false`
  disables it; `{"start": 2, "count": 8, "maps": true}` selects a window and
  writes the maps. `--no-analysis` disables it for a run.
- A state check can read `renderer.*` fields and `render_digest`. The field set
  is in **Renderer state**.
- An analysis check reads `analysis.pairs`, `analysis.worst_mean`,
  `analysis.worst_max`, `analysis.worst_over_16`,
  `analysis.worst_over_16_fraction`, `analysis.period.frames`, and
  `analysis.period.correlation`.
- `settle` advances the simulation and renders every frame without writing a
  screenshot, so a scenario can reach a steady temporal state before it captures.
- `scenarios/taa-static.json` and `scenarios/taa-motion.json` use capture checks
  to gate TAA stability.
- A top-level `renderer_debug` object compiles to the renderer debug command
  before the commands. See **Renderer debug overrides**.

## Commands

- `{"cmd": "reset"}`
- `{"cmd": "look", "dx": 220, "dy": 0}`
- `{"cmd": "face", "yaw": 0, "pitch": 0}`
- `{"cmd": "input", "forward": 1, "right": 0, "jump": false}`
- `{"cmd": "step", "frames": 60}`
- `{"cmd": "settle", "frames": 300}`
- `{"cmd": "state"}`
- `{"cmd": "capture", "name": "shot", "frame": 90, "alpha": 1.0}`
- `{"cmd": "camera", "position": [0, 2, 12], "yaw": 0, "pitch": 0}`
- `{"cmd": "camera", "clear": true}`
- `{"cmd": "view", "hud": true, "debug": false, "hint": false, "perf": false}`
- `{"cmd": "sun", "azimuth": 52.1, "elevation": 15, "diameter": 0.53}`
- `{"cmd": "crates", "reset": true}`
- `{"cmd": "crates", "clear": true}`
- `{"cmd": "crates", "add": {"position": [0, 0.5, 6]}}`
- `{"cmd": "crates", "add": {"origin": [0, 0.5, 6], "count": 60, "columns": 10, "spacing": [1, 0, 1]}}`
- `{"cmd": "crates", "remove": {"index": 3}}`
- `{"cmd": "debug_mode", "active": true}`
- `{"cmd": "menu", "open": true, "item": "Type weight", "activate": true, "direction": -1}`
- `{"cmd": "menu", "set": 900}`
- `{"cmd": "check", "field": "player.position.y", "op": "gt", "value": 0}`
- `{"cmd": "perf", "frames": 120, "warmup": 60}`
- `{"cmd": "renderer_debug", "jitter": false, "shadow_phase": 12}`
- `{"cmd": "record", "path": "scenarios/walk.json"}`
- `{"cmd": "record"}`
- `{"cmd": "replay", "path": "scenarios/walk.json"}`
- `{"cmd": "quit"}`

A past capture frame is an error. A future capture frame queues. Unknown keys,
wrong types, and out-of-range values are per-command errors; the session stays
usable. A `step` or `settle` while the menu is open is an error, because the
game pauses. A settle renders every frame and writes no screenshot. An open menu renders even when the `view` HUD flag is off. `item` selects a row by name:
Window mode, Display, Resolution, Type weight, Sprint mode, Crouch mode, Prone
mode, or Resume. `item`, `activate`, and `set` need an open menu. `direction` is
`-1` or `1` (default `1`) and needs `activate`. `set` is a number in 100..900 and
sets the Type weight directly, without the ten-unit step.

`crates` edits the dynamic crates. `reset` restores the starting three, `clear`
removes every crate, `add` creates one crate or a row-major grid, and `remove`
drops one by index. A grid add steps `columns` along x and then the next row
along z; the y spacing is a constant offset. An add that would exceed the
64-crate limit is rejected as a whole. `scenarios/perf-crates.json` adds 60
crates in a grid and measures them.

A capture names its target and format. See **Capture targets**.

The `sun` command moves the light or resizes its disk. `azimuth` is degrees from
`+z` toward `+x`, and `elevation` is degrees above the horizon; both describe
where the sun sits, not the direction its light travels. `diameter` is the angle
the sun disk subtends, in degrees, and sets the penumbra width. Omitted fields
keep their value, and `reset` restores the default sun. The state reports the
same three values under `sun.*`, so a check can assert the light a capture used.
Changing the sun resets TAA history with the `scene_change` reason.

The harness has no compositor, so the menu uses a fixed two-display list:
`Display 1` (1920x1080) and `Display 2` (2560x1440). Each lists smaller modes.
`settings.display` is the short display name, `settings.display_index` is the
zero-based index, `settings.resolution` is the effective size, and
`settings.window_resolution` is the stored Windowed size. In Borderless the
effective size is the display's desktop mode.

## UI scenarios

The 2D layer is part of the feature, so its captures live next to it.

| Scenario | Proves |
| --- | --- |
| `scenarios/hud.json` | the status panel at spawn, mid-walk, and facing the arena |
| `scenarios/hud-debug.json` | the debug-mode readout, which shares the row renderer |
| `scenarios/ui.json` | the settings panel with a numeric value selected, then an action row |
| `scenarios/settings-menu.json` | the settings round trip and the menu digest |
| `scenarios/window-settings.json` | the window rows after a display change |
| `scenarios/type-weight.json` | the Type weight slider at 400, 900, and 100 |

Read the evidence from a run directory:

```sh
./bin/harbagsa-agent run scenarios/hud.json --out runs/ui/hud
./bin/harbagsa-agent run scenarios/hud-debug.json --out runs/ui/hud-debug
./bin/harbagsa-agent run scenarios/settings-menu.json --out runs/ui/menu
./bin/harbagsa-agent run scenarios/window-settings.json --out runs/ui/window
./bin/harbagsa-agent run scenarios/type-weight.json --out runs/ui/weight
```

The PNGs live under `frames/`. Evidence is a run directory plus a scenario.
Screenshots stay out of the repository; point at the run directory instead of
copying them into `docs/evidence/`.

Text is rasterized at the device pixel size. The first atlas builds
synchronously at startup; later weight or density changes rebuild on a worker.
A capture waits for the pending build, so the image and the text theme always
agree. A capture at another size exercises the density path:

```sh
./bin/harbagsa-agent run scenarios/settings-menu.json --size 2560x1440 --out /tmp/menu-2x
```

A UI scenario follows one shape: open the menu, select a row by name, capture,
check the state, check the analysis, close. `scenarios/type-weight.json` is the
worked example. The `renderer.atlas_weight` check proves the atlas worker caught
up; the `analysis.worst_mean` check proves the captures differ. Without the
second check the scenario could pass with identical images.

## Movement scenarios

Movement scenarios run with `--no-render` and check the simulation state.

| Scenario | Proves |
| --- | --- |
| `scenarios/step-angle.json` | the step-up climbs the 0.35 m step from a 60 degree approach |

`step-angle.json` walks from spawn to the 0.35 m step, turns, and climbs it at
60 degrees. The check gates that the player ends on the tread instead of sliding
along the riser.

## Shadow scenario

| Scenario | Proves |
| --- | --- |
| `scenarios/shadow-angle.json` | a low sun over the arena, at two sun angular diameters |

`shadow-angle.json` sets the sun 15 degrees above the horizon and captures the
wall shadow from the floor and from straight above. It captures the top-down
edge at a 3 degree disk and at the 0.53 degree disk the build ships, so the two
penumbra widths can be compared without a rebuild. The edge width scales with
the diameter: about 72 px at 3 degrees and 13 px at 0.53 degrees, measured on
the column at x=1200.

```sh
./bin/harbagsa-agent run scenarios/shadow-angle.json --out runs/shadow/angle
```

The run directory holds `wall-wide-sun.png`, `wall-real-sun.png`,
`penumbra-wide-sun.png`, and `penumbra-real-sun.png`. Crop the same column from
the two penumbra captures to reproduce the measurement.

## Live session

```sh
printf '%s\n' \
  '{"cmd": "step", "frames": 60}' \
  '{"cmd": "state"}' \
  '{"cmd": "quit"}' |
  ./bin/harbagsa-agent session

./bin/harbagsa-agent session --socket /tmp/harbagsa.sock
socat - UNIX-CONNECT:/tmp/harbagsa.sock
```

One JSON command per line. One JSON reply per line. The socket mode prints one
ready line on standard output. Capture files go to `runs/session/frames/` unless
`--out` selects another directory.

`record PATH` starts recording. A second `record` with no path stops and writes
the scenario. Recording starts with a fresh reset, so send the actions after the
start command if you want them in the scenario. `replay PATH` resets and runs the
scenario.

## Screenshots

- Headless runs use the offscreen target. The default is 1280x720 with the HUD,
  debug draw, and capture hint off.
- The offscreen target submits one frame at a time, so a capture-free sequence
  cannot overlap two writes to its single color image. The swapchain target
  keeps two frames in flight. See
  `docs/adr/0009-offscreen-submission-serialization.md`.
- `--present` opens the real window and captures the swapchain image before
  present. The compositor controls the window size.
- TAA history affects exact pixels. The first frame matches exactly. Later frames
  match when both runs share the same history. See the README note.
- `scenarios/taa-static.json` settles for 520 frames, captures 60 steady frames,
  and checks `capture.worst_mean_delta`,
  `capture.worst_over_16_fraction`, and the analysis period. The settle passes
  the 512-sample cap.
- `scenarios/taa-motion.json` settles, moves the camera up the stairs, turns
  around, and holds. It captures the hold frames and checks that the image
  settles after the motion. Run it with `--size 800x600` for the
  stretched-window repro.
- `scenarios/capture-free.json` settles without captures, then captures twice.
  Run it twice and compare the state digest and the PNG hashes to prove the
  offscreen sequence is deterministic.
- `scenarios/settings-menu.json` captures the settings menu and checks a changed
  input mode.
- `scenarios/window-settings.json` captures the menu after switching to
  Windowed and changing the resolution, then checks the window settings.
- `--no-render` and capture-free scenarios never create a Vulkan device. Under
  `--no-render`, `settle` is a plain step.

Use `capture` or `--present`. Do not use `grim` for automated screenshots.

## Capture targets

A capture reads the final color image or one intermediate target. It still
renders one frame. The default is the color target in PNG, so an existing
scenario does not change.

| Target | Image | Default format |
| --- | --- | --- |
| `color` | the final image, after the overlay | `png` |
| `velocity` | screen motion in unjittered UV, linear view depth in `.z` | `stats` |
| `history` | the resolved history: linear color, view depth in `.a` | `stats` |
| `depth` | the hardware depth buffer in [0, 1] | `stats` |
| `scene_color` | the linear scene color before the resolve | `stats` |

Formats:

- `png`: color only. 8-bit RGBA, sRGB. This is the screenshot path.
- `float`: intermediate targets only. Writes `<name>.f32` with
  `width * height * 4` little-endian `f32` values in RGBA order. Depth fills
  `.x` and the other channels are zero. Color values stay in 0..255.
- `raw`: intermediate targets only. Writes `<name>.bin` with the exact texel
  bytes. `target_format` in the report names the Vulkan format.
- `stats`: any target. Writes no file. The report holds per-channel `min`,
  `max`, and `mean`, and for `velocity` the median screen motion in texels over
  covered pixels.

`png` with an intermediate target, or `float`/`raw` with color, is a scenario
error. Capture deltas compare color PNG captures only; another target does not
move the baseline.

A check reads the last capture in its window: `capture.target`,
`capture.format`, and `capture.stats.min.x`, `capture.stats.max.x`,
`capture.stats.mean.x`, `capture.stats.velocity_median_texels`, and the same
`.y`, `.z`, `.w` channels.

`scenarios/capture-targets.json` covers a static and a moving velocity capture,
scene color, history, and depth.

## Analysis

A run with captures writes `analysis.json` beside `report.json`, and
`report.json` links it in `analysis`. The pair and pixel analysis uses color PNG
captures; a run with only intermediate captures writes an empty window and
summary. The analysis is on by default. Disable it with `"analysis": false` or
`--no-analysis`.

`analysis.json` holds:

- `window`: the capture `start` and `count` the analysis used.
- `frames`: the frame number of each analyzed capture.
- `pairs`: one entry per consecutive pair with `mean`, `max`, `over_16`, and
  `over_16_fraction`.
- `summary`: the pair count, the worst values, and the dominant period.
- `worst_pixels`: the eight most unstable pixels with `x`, `y`, their mean
  channel value, and the per-frame series.
- `maps`: the diff and variance image paths, when `maps` is on.

The dominant period is the lag with the strongest autocorrelation over the
per-pair mean series. A periodic series correlates at every multiple of its
period, so the report keeps the smallest lag within 10% of the strongest and
gives its correlation. `scenarios/taa-static.json` reports period 8 with the
jitter cycle.

`"analysis": {"start": 2, "count": 8, "maps": true}` analyzes captures 2
through 9 and writes `analysis-diff.png` and `analysis-variance.png` beside the
captures. The diff map is the first-to-last frame difference. The variance map
is the per-pixel variance over the window, square-rooted and scaled to 0..255.

`scenarios/renderer-debug-jitter.json` writes both maps.

## Cross-run diff

```sh
./bin/harbagsa-agent diff runs/before runs/after
./bin/harbagsa-agent diff runs/before runs/after --max-pixels 0 --json
```

`diff` reads each run's `report.json` and pairs the `screenshots` entries by
name. A run without a report, or an entry whose `path` is empty or unreadable,
falls back to `frames/<name>.png`. The frame fallback skips the derived
`analysis-diff.png` and `analysis-variance.png` maps.

Each pair reports `name`, `width`, `height`, `different_pixels`, `max_delta`,
`mean_delta`, `over_16`, and `identical`. A pixel differs when an RGB channel
changes; alpha is ignored. `mean_delta` is the mean over pixels of the largest
RGB channel delta, so it matches the per-capture deltas in `report.json`.

Exit codes:

- `0`: every pair is present, the sizes match, and no pair is over the limit.
- `1`: a pair is missing, a pair differs in size, or `--max-pixels N` is
  exceeded.
- `2`: bad arguments or a run directory that cannot be read.

Without `--max-pixels`, differences are reported but do not fail the command.
`--json` prints one object with `run_a`, `run_b`, `ok`, `pairs`, and `errors`
instead of the table. `errors` lists missing pairs, size mismatches, decode
failures, and limit hits. Check `setup.revision` and `setup.dirty` before the
pixels so a dirty tree is not mistaken for a revision change.

## Renderer state

Every `state` reply and `state.json` carries a `renderer` object and a
`render_digest`. Both describe the last rendered frame. They are empty when the
run never created a renderer, and `renderer.active` is `false`.

| Field | Meaning |
| --- | --- |
| `active` | a renderer exists |
| `frame_count` | frames the renderer recorded |
| `taa_enabled` | temporal anti-aliasing is on |
| `jitter_index` | the jitter phase the last frame applied |
| `history_valid` | the history buffer holds a frame |
| `convergence_frames` | frames accumulated since the last history reset, capped at 512 |
| `history_read` | the history image the last frame read |
| `history_weight` | the resolved sample's history weight, `count / (count + 1)` |
| `reset_count` | history resets since renderer creation |
| `last_reset` | the last reset reason |
| `shadow_phase` | the sun sample phase the last frame used |
| `atlas_weight` | the type weight the active coverage atlas holds |

The state also carries a `sun` object with `azimuth`, `elevation`, and
`angular_diameter`, in degrees. The angles describe the sun in the sky, so the
default sun reads about 52 degrees of azimuth and 60 degrees of elevation.

The reset reasons are `none`, `create`, `extent`, `toggle`, `teleport`,
`scene_change`, `debug_override`, `player_reset`, and `scene_reset`. A change to
the sun direction or the sun angular diameter is a `scene_change`. A state
check reads the override values as `renderer.debug.*`, for example
`renderer.debug.sky` and `renderer.debug.ao`.

The render digest is FNV-1a over the effective camera, the sun direction and
angular diameter, every box, the jitter, the shadow phase, the applied atlas
weight, the sky and AO flags, and the view flags. It changes when any of those
change and stays the same when they do not. It is
separate from the simulation digest: read `render_digest` for the render inputs
and `digest` for the simulation.

`report.json` carries a `setup` block: the target kind (`offscreen`,
`swapchain`, or `none`), the extent, the build revision and dirty flag, the view
flags, the device name, the frame count in flight, the TAA state, the jitter,
history, and sample caps, and the AO sample count and radius. Use it to compare
two runs before you compare their pixels. `revision` is the short HEAD; `dirty`
says the tree had uncommitted changes. A direct `odin run` or a test build
reports `unknown` and `false`.

`scenarios/renderer-state.json` checks the steady state. `scenarios/renderer-reset.json`
checks a teleport reset.

## Renderer debug overrides

`{"cmd": "renderer_debug", ...}` changes renderer inputs without editing source.
It is diagnostic and gated. A build with `-define:ENABLE_RENDERER_DEBUG=true`,
or a run with `--debug-renderer`, accepts it. Any other build rejects it with a
clear error.

| Field | Effect |
| --- | --- |
| `taa` | turn TAA on or off |
| `jitter` | enable or disable the camera jitter |
| `history_weight` | fix the resolve history weight in [0, 1] |
| `clamp` | enable or disable the YCoCg neighborhood clamp |
| `depth_trust` | force the depth test to trust the history |
| `freeze_shadow_phase` | freeze the sun sample phase |
| `shadow_phase` | set a phase in [0, 63] and freeze it |
| `sky` | draw the sky pass, and use the sky ambient in the lit pass |
| `ao` | trace the ambient occlusion rays |
| `clear` | reset every override and turn TAA, the sky, and the AO on |

An override starts from the current state. A scenario can put the same fields in
a top-level `renderer_debug` object; it compiles to the command before the commands.

Every change to the override resets the history with reason `debug_override`,
including a new shadow phase.

`scenarios/renderer-debug.json` sets every override and clears it.
`scenarios/renderer-debug-converge.json` turns jitter off and freezes the phase,
so the image converges. `scenarios/renderer-debug-jitter.json` freezes the phase
and lets jitter cycle, so the analysis can find the period.

## Sky and ambient occlusion

The sky is an analytic gradient. It draws after the lit pass and shades only the
background pixels. The lit pass traces eight ambient occlusion rays per fragment
and scales the ambient term by the visible fraction. Both features are on by
default. The design is in
`docs/adr/0015-sky-ambient-and-ray-traced-ambient-occlusion.md`.

`scenarios/sky-ao.json` settles the camera at the zenith and at the horizon,
then captures one arena corner with the AO override off and on, and finally the
zenith again with the sky off. It checks the mean green channel for each
capture. It needs `--debug-renderer`, because it changes the `ao` and `sky`
overrides:

```sh
./bin/harbagsa-agent run scenarios/sky-ao.json --debug-renderer
```

Without the flag, the session rejects the command.

## Performance

The renderer records a perf sample every frame: the frame interval, five CPU
phases, and five GPU pass times. The game shows it on `F4`. A scenario can show
the same panel with `{"cmd": "view", "perf": true}`.

`{"cmd": "perf", "frames": N, "warmup": M, "prime": S, "name": "label"}` runs
one priming frame, primes until `S` seconds of wall clock pass (capped at 10,000
frames), runs `M` warmup frames, and measures `N` frames. `prime` defaults to
2.0 and `0` disables the time loop. Each frame steps the simulation once and
draws once without a capture. `frames` is capped at 600. The reply and
`report.json` carry the interval distribution, `p50`/`p95`/`mean` for every CPU
phase and GPU pass, and `prime_seconds`/`prime_frames`. `report.json` keeps every
named perf result in a `perf` array; the session reply carries the last one.
`trace` writes one JSON object per measured frame under the run directory; it is
the file to read when a percentile hides one spike. A run holds one trace, so a
second `perf` with `trace` is rejected. `scenarios/perf.json` is the ready
example. `scenarios/perf-crates.json` clears the crates, adds 60 in a grid, and
measures them.

The prime loop exists because GPU clocks and shader caches move between a cold
and a warm device. A fixed warmup can stop before the device settles, so two
builds would be compared at different clock states. Prime frames never enter the
trace or the statistics.

- Offscreen runs measure throughput: nothing waits for the display.
- `--present` measures pacing: FIFO bounds the rate and the percentiles show
  missed refreshes.
- `--no-render` measures the CPU only.

What the numbers mean:

- The frame interval is wall clock. A capture outside a perf run has no interval.
- The GPU pass times come from Vulkan timestamps. They belong to the last
  completed frame, two frames behind the recording frame. The depth prepass and
  the lit scene pass are separate passes; the sky runs inside the scene pass.
- A device without timestamp support, a failed query pool, or a run without a
  device reports the CPU numbers and leaves the GPU fields empty.
- Perf data never enters `State`, the state digest, or the pixel hash. A perf
  run cannot change a check result.

The design and its alternatives are in
`docs/adr/0008-performance-instrumentation.md`. The current numbers and the
ranked causes are in `docs/evidence/perf-baseline.md`.

`scenarios/perf-arena.json` and `scenarios/perf-backface.json` are the scene
pass probes. The arena view shows every static box at once; the backface view
covers the screen with surfaces that receive no direct sun. Run either at the
same size on two builds to compare. The before/after is in
`docs/evidence/perf-scene-pass.md`.

### Benchmark two builds

A single before/after pair is noisy. Alternate the order of each pair so clock
drift affects both sides equally, and compare medians, not one run. `--prime`
keeps the cold clock out of the measured window.

```sh
tools/ab.sh \
  --ref origin/main \
  --scenario scenarios/perf.json \
  --size 2560x1440 \
  --runs 5 \
  --prime 2.0 \
  --out runs/ab
```

The ref must understand the scenario's commands. `scenarios/perf-crates.json`
needs a ref with the `crates` command; a base without it exits non-zero, which
is the intended failure.

The tool builds the ref in a detached worktree under `build/ab/base`, builds the
current tree in place, and copies both agents to a temporary directory. It runs
each pair in alternating order, parses each `report.json`, and writes
`summary.json` and `summary.md`. The table gives the median per side and the
paired ratio for the frame interval, the GPU total, and each pass. The `setup`
block names the revision and dirty state of each side, so the result does not
need a hand-written label. A run directory is a complete record: the report, the
state, the captures, and the trace.

A ref that predates `prime` rejects the field. The tool reruns that base side
with the original scenario and records `base_prime_supported: false`; the
optimized side still uses `--prime`. The note stays in `summary.json`.

To measure one build by hand, drive a session and run perf twice. The first run
warms the path; the second is the comparable one:

```sh
printf '%s\n' \
  '{"cmd": "perf", "frames": 120, "warmup": 60, "prime": 2.0, "name": "warm"}' \
  '{"cmd": "perf", "frames": 120, "warmup": 60, "prime": 0, "name": "measure"}' \
  '{"cmd": "quit"}' |
  ./bin/harbagsa-agent session
```

Offscreen throughput is not present pacing. An offscreen perf run measures how
fast the renderer can submit frames with nothing waiting for the display; a
windowed FIFO run measures how often a frame reaches the screen. Compare the
same mode on both sides, and do not use the offscreen ratio to claim a visible
frame-rate change.

## Determinism

- Fixed 60 Hz. Never sleep or use a wall-clock delta.
- A perf command is the one wall-clock exception. It never writes the state,
  the digest, or the pixel hash.
- `reset` creates a fresh `Simulation`. Crates return to spawn, the settings
  return to their defaults, and the menu closes.
- `look` uses the game sensitivity and pitch clamp. `face` sets yaw and pitch
  directly.
- Capture alpha defaults to 1.0 (post-step), so a capture matches `state` at the
  same frame.
- The digest is FNV-1a over frame, player, crates, the window and input
  settings, and menu state. Use it in reports and regression checks.

## Where the code lives

- `src/harness/`: CLI, scenario parser, commands, session, runner, socket, PNG.
- `src/harness/scenario.odin`: the one `commands` scenario form and the analysis config.
- `src/harness/diff.odin`: the pure pair comparison and the diff report types.
- `src/harness/diff_captures.odin`: run capture discovery and the frame fallback.
- `src/harness/diff_cli.odin`: the `diff` command and its table/JSON output.
- `src/harness/capture.odin`: the capture result, target, format, and file write.
- `src/harness/capture_stats.odin`: the capture statistics and pixel hash.
- `src/harness/capture_command.odin`: the capture target/format parser.
- `src/harness/perf_run.odin`: the perf run and its prime loop.
- `src/harness/perf_report.odin`: the perf report types and fill.
- `src/harness/perf_command.odin`: the perf command parser.
- `src/harness/session_state.odin`: the session's renderer snapshot.
- `src/harness/sun_command.odin`: the sun command parser.
- `src/harness/session_sun.odin`: the sun command's session state.
- `src/harness/crates_command.odin`: the crates command parser.
- `src/harness/session_crates.odin`: the crates command's session state.
- `src/harness/session_debug.odin`: the renderer debug gate and overrides.
- `src/harness/renderer_debug_command.odin`: the override parser.
- `src/harness/analysis.odin`: the analysis config, summary, and period.
- `src/harness/analysis_report.odin`: the analysis file.
- `src/harness/analysis_images.odin`: PNG decode and the analysis maps.
- `src/harness/check_capture.odin`: capture checks and the check window.
- `src/harness/check_analysis.odin`: analysis check fields.
- `src/harness/report.odin`: the run report and summary types.
- `src/harness/report_setup.odin`: the run's setup block.
- `src/harness/build_info.odin`: the injected revision and dirty flag.
- `src/harness/run_summary.odin`: the `--verbose` run summary.
- `src/digest/digest.odin`: FNV-1a for the state and render digests.
- `src/perf/`: the perf sample, ring, statistics, and text formatting.
- `src/renderer/timing.odin`: the timestamp pools, the pass boundaries, and the
  read.
- `src/renderer/debug.odin`: the debug gate, overrides, and shadow phase.
- `src/renderer/state.odin`: the renderer report and setup.
- `src/renderer/render_digest.odin`: the render digest.
- `src/renderer/sky_draw.odin`: the sky pass, after the lit pass.
- `src/renderer/capture.odin`: the target copy and RGBA f32 decode.
- `src/frame/`: shared scene assembly and draw for the game and the harness.
- `src/game/menu.odin`: the menu rows, settings text, and control list.
- `src/game/settings.odin`: the runtime window and input-mode settings.
- `src/display/`: the display list, mode ordering, and window settings types.
- `src/renderer/`: `Target` and `Platform` ports, swapchain/offscreen targets,
  TAA, HUD and menu overlay.
- `src/platform/`: SDL and headless adapters. `display.odin` queries displays and
  applies the window state.
- `tests/harness/` (including `analysis.odin`, `crates.odin`, `diff.odin`,
  `menu_digest.odin`, `renderer_debug.odin`, `renderer_state.odin`,
  `setup.odin`, `sun.odin`, and `verbose.odin`), `tests/frame/`,
  `tests/display/display.odin`, `tests/renderer/` (including `target.odin`,
  `render_digest.odin`, `capture_values.odin`, and `debug.odin`).
- `scenarios/smoke.json`, `scenarios/taa-static.json`,
  `scenarios/taa-motion.json`, `scenarios/hud.json`, `scenarios/hud-debug.json`,
  `scenarios/ui.json`, `scenarios/type-weight.json`,
  `scenarios/settings-menu.json`, `scenarios/window-settings.json`,
  `scenarios/renderer-state.json`, `scenarios/renderer-reset.json`,
  `scenarios/capture-targets.json`, `scenarios/renderer-debug.json`,
  `scenarios/renderer-debug-converge.json`,
  `scenarios/renderer-debug-jitter.json`, `scenarios/sky-ao.json`,
  `scenarios/capture-free.json`, `scenarios/shadow-angle.json`,
  `scenarios/perf.json`, `scenarios/perf-crates.json`,
  `scenarios/perf-arena.json`, `scenarios/perf-backface.json`,
  `scenarios/step-angle.json`.

## Adding a command

Change:

- `Command_Kind` and `Command` in `src/harness/command.odin`.
- `command_name` and `command_destroy`.
- `command_parse` and a parser in `src/harness/command_parsers.odin`, or a new
  file when the command grows (`src/harness/menu_command.odin` and
  `src/harness/crates_command.odin` are the examples).
- `session_execute` and `session_record_command` in
  `src/harness/session_commands.odin`, with a helper in a `session_*.odin` file
  when the command has its own state.
- A scenario block when the command is a setup step: parse it into the same
  command and append it before the commands. `renderer_debug` is the example.
- README and, for a new domain word, `GLOSSARY.md`.
- A section in this page when the command needs more than a line of
  explanation. `capture` and `renderer_debug` are the examples.
- A test in `tests/harness/`.

## Checks

```sh
tools/make.sh check
tools/make.sh test
tools/make.sh build
```

`make validate` builds the agent with validation enabled and runs
`scenarios/smoke.json` offscreen, then with `--present` when a display is
available. `make validate-offscreen` is the headless target: it runs `smoke`,
`type-weight`, `settings-menu`, `ui`, `shadow-angle`, and `perf-crates` offscreen,
each into its own output directory, and stops on the first failure.
`make validate-demo` runs the game with validation enabled.

## Keep the harness current

The harness is part of the product. When you add or change a feature, update the
harness in the same change. Do not leave the automation behind the game.

- New simulation input: add it to `game.Input_Snapshot`, the `input` command,
  and `tests/harness`.
- New state field: add it to `State`, `state_build`, `state_field`, the report
  schema, and the docs. Add it to `state_digest` only when it changes the
  simulation.
- New setting or menu row: add it to `Settings` and `DEFAULT_SETTINGS`, then
  `Menu_Item`, `MENU_ITEM_COUNT`, `MENU_ITEM_NAMES`, `menu_view`, and
  `menu_change_setting`. Add it to `Settings_State` or `Menu_State`, the digest,
  and the docs.
- New window setting: add it to `display.Window_Settings` and apply it in
  `platform.apply_window_state`.
- New view toggle: add it to the `view` command, `frame.Options`, the README, and
  this page.
- New CPU phase or GPU pass: add it to the `perf` enums, the renderer timing
  boundaries, the formatters, the tests, and this page.
- New perf field: add it to the perf report struct, the reply, the run report,
  the trace, and this page.
- New command: follow **Adding a command**, add a JSONL test, and add a scenario
  example when it changes a normal workflow.
- New CLI subcommand or flag: add the dispatcher and parser, the `--help` text,
  the README, this page, and a test.
- New capture target or format: add it to `Capture_Target` or `Capture_Format`,
  the name/parse and extension helpers, `target_image`, `record_capture_copy`,
  `read_capture_target`, and `capture_values`. Add it to the capture parser,
  the README, this page, and a scenario. An unread target is not a tool.
- New analysis field: add it to the `Analysis_*` types, `analysis_field`, the
  analysis report, the docs, and a unit test. A check must read the same value
  the file records.
- New renderer debug override: add it to `Renderer_Debug`,
  `set_renderer_debug`, the camera uniform or the resolve push constants and
  shader, `renderer_debug_fields`, the renderer state, the render digest, the
  docs, and the gate test. Do not make it reachable without the gate.
- New scenario key or run option: add it to `scenario_parse` and its allowed
  key set, the CLI parser, the README, this page, and a parser test.
- Render state is not simulation state: render fields do not go into
  `state_digest`. Put pipeline state in the render digest and `Renderer_State`.
  A scene input such as the sun stays at the top level and feeds the render
  digest.
- New renderer pass or target: keep it behind `Target` or `Frame_View`. Add an
  offscreen test when the pass must match the game.
- New screenshot or evidence path: update the README and this page.
- New domain word: add it to `GLOSSARY.md` before you use it.

If you cannot update the harness in the same change, open a ticket and state the
gap. Do not silently ship a game feature that the harness cannot see.

## Pitfalls

- Do not add a control socket to the game. The agent is a separate binary.
- Do not duplicate frame assembly. The game and the harness call `src/frame`.
- Keep the offscreen target lazy. Simulation-only runs must not create a Vulkan
  device.
- Keep `renderer.Target` and `renderer.Platform` as the seams. The renderer core
  must not import `src:platform`.
- Keep the harness tests in the normal `make test` run. Do not hide them behind a
  manual target.
- Do not make a renderer debug override reachable without the define or
  `--debug-renderer`.
- Do not widen a capture target without a readback path; an unread target is not
  a tool.
