# harbagsa

A first-person movement demo. The player walks, sprints, crouches, crawls,
jumps, dives, slides, and mantles in a fixed arena with stairs, ramps, tunnels,
mantle walls, a dive platform, and pushable crates. SDL3 provides the window and
input, raw Vulkan 1.3 with ray-query shadows draws the scene, and Box3D runs the
physics. A directional sun casts hard contact shadows and softer distant
shadows from the walls and crates.

## Requirements

- [Odin](https://odin-lang.org/) tested with `dev-2026-10`
- SDL3 and a Vulkan 1.3 driver with the Vulkan loader
- A GPU with `VK_KHR_acceleration_structure` and `VK_KHR_ray_query`
- `glslc` from shaderc to compile the GLSL shaders
- `spirv-val` from SPIRV-Tools to validate the compiled shaders (optional)
- A C and C++ compiler for the vendored Box3D, FreeType, and HarfBuzz libraries
- `make` (optional)

## Run

```sh
make run
```

`make run` builds the Box3D, FreeType, and HarfBuzz archives, compiles every
shader with `glslc`, builds the demo, and starts it. The first build compiles the
vendored font libraries and takes about a minute; later builds reuse them. The
SPIR-V lives in `build/shaders/` and is embedded into the binary.

## Controls

- `WASD`: move relative to the view. Every stance moves in any direction.
- Mouse: look. Left click captures the cursor.
- `Left Shift`: sprint. The settings menu switches the input mode between
  Hold and Toggle.
- `Space`: jump. In the air, hold `Space` while moving toward a ledge to mantle;
  a fresh press also works. Jump input buffers before landing.
- `C`: crouch. The settings menu switches the input mode between Hold and
  Toggle. While sprinting, it starts a crouch slide.
- `Z`: prone. The settings menu switches the input mode between Hold and
  Toggle. Crawl while prone. Dive in the air or from a sprint.
- `R`: return the player to spawn.
- `Shift+R`: reset the crates, the sun, and the player.
- `F1`: toggle the debug draw.
- `F2`: toggle debug mode.
- `F3`: toggle temporal anti-aliasing (TAA). TAA is on by default.
- `F4`: toggle the perf overlay. It shows the frame interval, the CPU frame
  time, and the GPU pass times.
- `Esc`: open the settings menu. The menu pauses the game and releases the
  cursor. Press `Esc` again to resume.

### Settings menu

`Esc` opens a centered settings menu. The menu pauses the simulation. It changes
the window mode, the display, the resolution, and the sprint, crouch, and prone
input modes, and below them it lists the active controls as a key legend.

The first seven rows are settings: the label sits on the left, the current value
is right-aligned on the panel edge. `Resume` is an action, not a setting, and sits
below a divider. The selected row always carries an amber bar on its leading
edge, so selection never depends on a colour change alone.

- `Up` / `Down`: select a row.
- `Left` / `Right`: change the selected row in that direction.
- `Enter`: change the selected row. `Resume` closes the menu.
- `Esc`: close the menu.
- Drag the `Type weight` track: set the weight directly. It is the only row with
  a continuous track.

`Window mode` is `Borderless` or `Windowed`. Borderless fills the selected
display at its desktop size. Windowed uses the chosen resolution and a normal
title bar, and asks for a fixed size; pick another resolution instead of
resizing it by hand. A tiling compositor that honors the size hint floats the
window.

`Display` chooses a connected display. The selected display supplies the
resolution list. On Wayland the compositor controls where a windowed window
sits; the selected display still decides where the next Borderless fullscreen
opens. On X11 the window also moves to the selected display.

`Resolution` cycles through the selected display's unique modes, largest first.
Changing it in Borderless switches to Windowed, because Borderless has only the
desktop size. The row shows the desktop size in Borderless and the chosen size
in Windowed. Modes smaller than 800x600 are left out so the settings menu stays
fully visible; the display's desktop mode is always kept.

`Type weight` sets the UI text weight on the variable axis from 100 to 900. The
number is the weight; the nine ticks mark Thin 100 through Black 900. Left and
Right step by 10, and the track above the scale can be dragged for any value. The
weight applies to the menu and the HUD. Roboto Mono stops at 700, so numbers stop
gaining weight above 700 while the prose continues to Black.

The display list and its modes come from SDL at startup. The choices last for
the current run. A new run starts Borderless, with 1280x720 as the Windowed
size.

When the menu closes, the game recaptures the cursor if it had capture before
the menu opened.

Movement follows the walkable ground plane. A straight climb keeps the stance
speed along the slope, so the horizontal speed drops by the slope cosine.
Step-ups and step-downs use a short camera lag, so the view stays smooth on the
stairs.

### Debug mode

`F2` replaces the player with a free-fly camera and enables scene editing.

- `WASD`: fly horizontally.
- Mouse: look while not dragging; drag the selection while the left button is held.
- `Space` / `Ctrl`: fly up / down.
- Left click: select a crate. Drag it on a horizontal plane.
- Wheel: raise or lower the selected crate.
- `E`: add a crate on the surface under the crosshair.
- `Delete` or `X`: remove the selected crate.
- `L`: select the sun. Drag to rotate it.
- `R`: reset the player and return the camera to spawn.
- `Shift+R`: reset the crates, the sun, and the player.
- `F2`: leave debug mode. The player returns to the saved position and view.
- `Esc`: open the settings menu.

The HUD shows the stance, gait, horizontal speed, grounded state, movement
state, and position, or the debug mode selection, crate count, and sun angles.
The settings menu shows the control list. Borderless fills the selected display;
Windowed uses the chosen resolution.

### Perf overlay

`F4` shows the perf overlay. It starts off and hides while the settings menu is
open.

The summary row holds frames per second, the frame interval, the CPU frame
time, the p95 interval, the spike count, and the GPU total with the costliest
pass. The pass row holds the last completed frame's GPU pass times: the TLAS
build, the depth prepass, the lit scene pass, the TAA resolve, and the overlay
pass.

The GPU numbers belong to the last completed frame, so they are two frames
behind the frame being recorded. A device without timestamp support shows the
CPU numbers only. The overlay adds six timestamp writes per frame.

## Agent harness

`bin/harbagsa-agent` drives the simulation and writes screenshots without a
window or compositor. `make build` builds it next to the game. Agent-specific
operational notes are in `docs/agents/harness.md`.

### Run a scenario

```sh
./bin/harbagsa-agent run scenarios/smoke.json
```

The default run directory is `runs/<scenario-stem>`:

```text
runs/smoke/
  report.json
  state.json
  analysis.json
  frames/frame_0000.png
  frames/frame_0090.png
  frames/frame_0121.png
  run.log
```

`analysis.json` exists when the run captured frames. With `"analysis": {"maps":
true}` the frames directory also holds `analysis-diff.png` and
`analysis-variance.png`.

`report.json` holds the pass/fail result, the final state, the setup block,
absolute screenshot paths, checks, the state digest, and the named perf reports
when perf ran. `state.json` holds the final state alone.
`analysis.json` holds the per-run image analysis when the run captured frames.
The pair and pixel analysis uses color captures. `run.log` holds the log lines.
Standard output is one JSON summary.

Exit codes:

- `0`: every check passed.
- `1`: a check or an invariant failed.
- `2`: the arguments or the scenario are bad.
- `3`: renderer or backend initialization failed.

Options:

- `--out DIR`: replace this run directory atomically. Default: `runs/<stem>`.
- `--size WxH`: capture size. Default: `1280x720`.
- `--no-render`: run the simulation and checks only. No Vulkan device is created.
- `--present`: render the real SDL window and capture the swapchain image
  before present. No compositor and no `grim`.
- `--debug-renderer`: accept the renderer debug command. A build with
  `-define:ENABLE_RENDERER_DEBUG=true` always accepts it.
- `--no-analysis`: skip `analysis.json` and the analysis maps.

The harness view starts with the HUD off, the debug draw off, and the capture
hint off. Only a `capture` command writes a PNG. A scenario with no capture and
no perf run never creates a Vulkan device unless `--present` asks for the window.

### Scenario format

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

The `commands` array runs verbatim, and `record` writes this form. Only a
`capture` command writes a PNG; a scenario without one renders nothing unless
`settle` or `--present` needs a frame. `step` advances one fixed
`SIMULATION_STEP` per frame. `look` applies once. `input` persists until the
next `input`; `jump` is an edge on the next step.

Check operators are `eq`, `ne`, `lt`, `le`, `gt`, and `ge`. Check fields use
the `state.json` shape, for example `player.position.y`, `player.grounded`,
`crates.0.position.z`, `crates.count`, `settings.window_mode`,
`settings.resolution`, `menu.open`, `debug.active`, `sun.elevation`,
`sun.angular_diameter`, `renderer.taa_enabled`, or `render_digest`. A capture
check can also read `capture.target`, `capture.format`, and `capture.stats.*`
for the last capture in its window. Add `"window": {"start": 2, "count": 8}` to
aggregate over part of the captures; `warmup` stays the shorthand for skipping
the first N.

A run with captures writes `analysis.json`. It holds per-pair deltas, a
summary, the dominant period, the worst unstable pixels' series, and optional
diff and variance maps. The pair and pixel analysis uses color captures; a run
with only intermediate captures writes an empty summary. Checks read `analysis.period.frames`,
`analysis.period.correlation`, and the `analysis.worst_*` fields. Disable it with
`"analysis": false` or `--no-analysis`; select a window and maps with
`"analysis": {"start": 2, "count": 8, "maps": true}`.

### Commands

The batch runner and the live session share one command set:

- `{"cmd": "reset"}`: fresh simulation. Crates return to spawn, the settings
  return to their defaults, the sun returns to its default, and the menu closes.
- `{"cmd": "look", "dx": 220, "dy": 0}`: pixel look delta through the game
  sensitivity and pitch clamp.
- `{"cmd": "face", "yaw": 0, "pitch": 0}`: set the player view directly.
- `{"cmd": "input", "forward": 1, "right": 0, "jump": false}`: set persistent
  input. Omitted fields keep their value.
- `{"cmd": "step", "frames": 60}`: fixed steps with no wall clock. A step is an
  error while the menu is open.
- `{"cmd": "settle", "frames": 520}`: fixed steps that render every frame but
  write no PNG. Use it to advance the temporal history before a capture. A
  settle is an error while the menu is open. Under `--no-render`, or in a
  scenario with no captures, it is a plain step.
- `{"cmd": "state"}`: player, eye, velocity, yaw, pitch, grounded, crates,
  window and input settings, debug mode, sun, menu, renderer state, render
  digest, frame, and simulation digest. The sun object reports azimuth,
  elevation, and angular diameter in degrees. The renderer object reports the
  frame count, TAA state, jitter index, history validity, convergence frames,
  history read index and weight, reset count and reason, and shadow phase.
  `render_digest` covers the effective camera, sun, boxes, jitter, shadow phase,
  and view flags.
- `{"cmd": "capture", "name": "shot", "frame": 90, "alpha": 1.0}`: write a PNG.
  `frame` is optional. A past frame is an error; a future frame queues. Add
  `"target": "velocity"`, `"history"`, `"depth"`, or `"scene_color"` to read an
  intermediate image, and `"format": "float"`, `"raw"`, or `"stats"` to choose
  the output. The default is a color PNG.
- `{"cmd": "camera", "position": [0, 2, 12], "yaw": 0, "pitch": 0}`: inspection
  camera. It does not move the player. `{"cmd": "camera", "clear": true}` drops
  the override.
- `{"cmd": "view", "hud": true, "debug": false, "hint": false, "perf": false}`:
  toggle the HUD, the debug draw, the capture hint, and the perf overlay.
- `{"cmd": "sun", "azimuth": 52.1, "elevation": 15, "diameter": 0.53}`: move the
  sun or resize its disk. `azimuth` is degrees from `+z` toward `+x`, `elevation`
  is degrees above the horizon, and `diameter` is the angle the sun disk
  subtends in degrees. Omitted fields keep the value. A change resets TAA
  history, like a scene change.
- `{"cmd": "crates", "clear": true}`: edit the dynamic crates. `reset` restores
  the starting three, `clear` removes every crate, `add` creates one crate or a
  row-major grid, and `remove` drops one by index. A grid add steps `columns`
  along x and then the next row along z. An add that would exceed the 64-crate
  limit is rejected as a whole.
- `{"cmd": "debug_mode", "active": true}`: enter or leave the `F2` debug mode.
  Entering swaps the player for the free-fly camera; leaving restores the player.
  Repeating the same value is a no-op.
- `{"cmd": "menu", "open": true, "item": "Type weight", "activate": true, "direction": -1, "set": 900}`:
  open or close the settings menu, select a row by name, activate the selected
  row, or set the Type weight. `item` is `Window mode`, `Display`, `Resolution`,
  `Type weight`, `Sprint mode`, `Crouch mode`, `Prone mode`, or `Resume`, and
  needs an open menu. `activate` and `set` also need an open menu. `direction`
  is `-1` or `1` (default `1`) and needs `activate`; `set` is a weight in
  100..900. Omitted fields keep the state. An open menu renders even when `hud`
  is off.
- `{"cmd": "check", "field": "player.position.y", "op": "gt", "value": 0}`:
  evaluate a predicate now.
- `{"cmd": "perf", "frames": 120, "warmup": 60, "prime": 2.0, "name": "default", "trace": "trace.jsonl"}`:
  measure frames. `frames` defaults to 120, `warmup` to 60, and `prime` to 2.0
  seconds (`0` disables the time loop). `name` labels the result; `report.json`
  keeps every named result in a `perf` array. `trace` writes one JSON object per
  measured frame; a relative path resolves against the run directory and a run
  holds one trace. Offscreen measures throughput; with `--present` it measures
  pacing. A run without a device reports CPU numbers only.
- `{"cmd": "renderer_debug", "jitter": false, "shadow_phase": 12}`: change TAA
  inputs. It needs `--debug-renderer` or a build with
  `-define:ENABLE_RENDERER_DEBUG=true`. `clear` resets every override. Changing
  a TAA input resets history.
- `{"cmd": "record", "path": "scenarios/walk.json"}`: start recording. Send
  `{"cmd": "record"}` to stop and write the scenario.
- `{"cmd": "replay", "path": "scenarios/walk.json"}`: reset and run a scenario.
- `{"cmd": "quit"}`: stop the session.

Unknown keys, wrong types, and out-of-range values are per-command errors. The
session stays usable.

The harness has no compositor, so it uses a fixed two-display list. `Display 1`
is 1920x1080 with 1600x900 and 1280x720 below it. `Display 2` is 2560x1440 with
1920x1080 and 1280x720 below it. `settings.resolution` is the effective size:
the display's desktop mode in Borderless, the stored size in Windowed.
`settings.window_resolution` is always the stored Windowed size.

### Live session

Standard input is one JSON command per line and standard output is one JSON
reply per line:

```sh
printf '%s\n' \
  '{"cmd": "step", "frames": 60}' \
  '{"cmd": "state"}' \
  '{"cmd": "quit"}' |
  ./bin/harbagsa-agent session
```

A Unix socket does the same:

```sh
./bin/harbagsa-agent session --socket /tmp/harbagsa.sock
socat - UNIX-CONNECT:/tmp/harbagsa.sock
```

The server prints one ready line on standard output. Capture files go to
`runs/session/frames/` unless `--out` selects another directory. The offscreen
target is created on the first `capture` or `replay`, so a simulation-only
session never creates a Vulkan device.

### Measure performance

```sh
./bin/harbagsa-agent run scenarios/perf.json
```

A `perf` command steps the simulation and draws one frame per measurement. The
reply and `report.json` carry the interval distribution, `p50`/`p95`/`mean` for
every CPU phase and GPU pass, and the prime frame count. `prime` (seconds,
default 2.0) warms the device clock before the measured window. `name` labels
the result and `report.json` keeps every named result in a `perf` array. Add
`"trace": "trace.jsonl"` to write one JSON object per measured frame under the
run directory; a run holds one trace. Offscreen runs measure throughput, because
nothing waits for the display. `--present` measures pacing, because FIFO bounds
the rate.

The first baseline is in [the perf baseline](docs/evidence/perf-baseline.md).
The scene-pass before/after is in
[the scene pass evidence](docs/evidence/perf-scene-pass.md).

`scenarios/perf-arena.json` measures the whole arena from above, and
`scenarios/perf-backface.json` measures the near wall where every covered pixel
faces away from the sun. Both are regression probes for the scene pass; run
them at the same size to compare two builds. `scenarios/perf-crates.json` adds
60 crates in a grid and measures them.

To compare two builds, use
[the benchmark recipe](docs/agents/harness.md#benchmark-two-builds).

### Movement checks

`scenarios/step-angle.json` walks from spawn to the 0.35 m step, turns, and
climbs it at 60 degrees. It gates that an angled approach takes the step instead
of sliding along the riser. The scenario needs no renderer:

```sh
./bin/harbagsa-agent run scenarios/step-angle.json --no-render
```

### Screenshot workflow

```sh
make build
./bin/harbagsa-agent run scenarios/smoke.json
```

Read `runs/smoke/report.json` and use the absolute paths in `screenshots`. The
PNG is RGBA, sRGB, and `1280x720` by default. The repository samples are
`docs/evidence/harness-smoke.png`, `docs/evidence/present-window.png`,
`docs/evidence/settings-menu.png`, and `docs/evidence/window-settings.png`. To
capture the owner's real window instead:

```sh
./bin/harbagsa-agent run scenarios/smoke.json --present --out runs/present
```

The compositor may resize the window. The PNG has the actual swapchain size. It
matches an offscreen capture at the same size when both frames share the same
TAA history; the first frame always matches.

The offscreen target submits one frame at a time, because it owns a single color
image and a single readback buffer. A capture-free sequence therefore cannot
overlap two writes to the same image and stays deterministic. The swapchain
target keeps two frames in flight.

`scenarios/taa-static.json` settles the stairs camera for 520 frames, then
captures 60 steady frames and checks the capture deltas and the analysis period.
It gates TAA edge stability without a window. The settle passes the 512-sample
cap, so the check sees the steady image instead of the initial convergence.

`scenarios/taa-motion.json` moves the camera up the stairs, turns around, and
holds, then captures 60 hold frames. It gates that the image settles after the
motion. Use `--size 800x600` to reproduce the reported stretched-window case.

`scenarios/settings-menu.json` opens the settings menu, captures it, changes the
crouch input mode, closes the menu, and checks the saved state.

`scenarios/type-weight.json` opens the menu, selects Type weight, captures 400,
sets 900 and 100, captures both, and checks the stored value.

`scenarios/window-settings.json` opens the menu, moves to Display 2, switches to
Windowed, changes the resolution, captures the result, and checks the window
settings.

`scenarios/renderer-state.json` settles a static scene, captures it, and checks
the renderer state and render digest. `scenarios/renderer-reset.json` teleports
the camera and checks that the history reset names the teleport. `report.json`
also carries a `setup` block: target kind, extent, view flags, and renderer
config, so a run is reproducible.

`scenarios/shadow-angle.json` puts the sun 15 degrees above the horizon and
captures a wall shadow twice: once with a 3-degree sun disk, then with the
0.53-degree disk the build uses. It also captures a top-down view of the same
edge, where the penumbra is measurable in pixels. Use it to compare a sun
angular diameter change. The penumbra width follows the diameter, so the small
disk gives a shadow edge about 5.7 times narrower.

A capture can read an intermediate target. `"target": "velocity"` with
`"format": "stats"` reports per-channel min, max, and mean plus the median
screen motion in texels. `"format": "float"` writes a `.f32` file and `"raw"`
writes the exact texel bytes. A PNG capture is color only.
`scenarios/capture-targets.json` covers every target.

`renderer_debug` changes TAA inputs for a diagnosis: TAA, jitter, history weight,
clamp, depth trust, and the shadow phase. Every build rejects it unless
`--debug-renderer` is passed or the build used the `ENABLE_RENDERER_DEBUG`
define. Changing an input resets history and records the `debug_override`
reason.
`scenarios/renderer-debug.json` covers the overrides, and
`scenarios/renderer-debug-converge.json` shows the image converging with jitter
off. `scenarios/renderer-debug-jitter.json` freezes the phase, lets jitter cycle,
and writes the analysis maps. `scenarios/capture-free.json` settles without
captures and then captures; run it twice and compare the digests and PNG hashes
to prove the offscreen sequence is deterministic.

## Build

```sh
make build
./bin/harbagsa
```

To run Odin directly, compile the shaders first:

```sh
make shaders
odin run . -collection:src=src -collection:libs=vendor
```

## Checks

```sh
make check
make check-spirv
make test
```

`make check` validates every compiled shader with `spirv-val` and runs the
strict compiler checks on the game, the agent, and every library package. If
`spirv-val` is not installed, the shader check prints a skip message and does
not fail the build. `make check-spirv` runs only the shader check. `make test`
runs the display, physics, simulation, frame, perf, harness, and renderer tests
headless. The offscreen render test logs a skip when no Vulkan device is
available.

If more than one agent or terminal can build in this checkout, use the
wrapper. It serializes Make with `flock` and needs `flock` from util-linux.

```sh
tools/make.sh check
tools/make.sh test
```

New source files start with `#+vet explicit-allocators`, which rejects calls
that silently use `context.allocator` or `context.temp_allocator`.

Do not pass `-no-bounds-check`. Bounds checks stay enabled in every build.

## Validation layers

Validation layers are off by default, so the demo runs on machines without
them.

`make validate` runs the agent harness with validation enabled. It runs
`scenarios/smoke.json` offscreen, then again with `--present` when a display is
available. Both runs exit on their own, and a validation error fails the target.

`make validate-offscreen` is the headless target. It builds the validation agent
and runs `smoke`, `type-weight`, `settings-menu`, `ui`, `shadow-angle`, and
`perf-crates` offscreen, each into its own directory under
`build/validate/offscreen/`. It never opens a window, stops on the first
failure, and is the target an agent runs. The `sun` scenario joins the list when
it exists.

`make validate-demo` runs the demo with validation enabled for a manual
session. It returns when you close the window.

All three targets check for `VK_LAYER_KHRONOS_validation` first. If the layer is
missing, they print the install command and exit without starting anything.
They never install anything. `make check` and `make test` never enable
validation.

To run Odin directly instead, build the vendored archives once with `make build`
first; they are build products and are not committed:

```sh
odin run . -collection:src=src -collection:libs=vendor -define:ENABLE_VALIDATION_LAYERS=true
```

## Vendored libraries

Box3D, FreeType, and HarfBuzz are built from `vendor/` by `make`. Their licences
ship beside each tree; see `vendor/*/PROVENANCE.md`.

Portions of this software are copyright © 2026 The FreeType Project
(https://freetype.org). All rights reserved.

## Clean

```sh
make clean
```
