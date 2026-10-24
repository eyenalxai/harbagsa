# harbagsa

A first-person movement demo. The player walks, sprints, crouches, crawls,
jumps, dives, slides, and mantles in a fixed arena with stairs, ramps, tunnels,
mantle walls, a dive platform, and pushable crates. SDL3 provides the window and
input, raw Vulkan 1.3 with ray-query shadows draws the scene, and Box3D runs the
physics. A directional sun casts hard contact shadows and softer distant
shadows from the walls and crates. An analytic sky gradient fills the
background. Ray-traced ambient occlusion uses the same scene acceleration
structure to darken the ambient light in corners and tunnels.

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
- `Shift+R`: reset the placed objects, the sun, and the player.
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
  While the palette is open, the mouse moves the pointer and the camera stays still.
- `Space` / `Ctrl`: fly up / down.
- `Tab`: open or close the object palette. The cursor is released while the
  palette is open. Picking a card recaptures it.
- Left click: select a placed object. Drag it on a horizontal plane. While the
  placement tool is armed, a click places the object at the ghost and keeps the
  tool armed.
- Wheel: raise or lower the ghost while armed, otherwise the selected object.
- `Q` / `E`: turn the ghost or the selected object left or right in 15 degree
  steps. Hold `Shift` for 45 degree steps.
- `G`: toggle the 0.25 m grid snap.
- `M`: flip the body mode for the next placement while the palette is open.
  With the palette closed, it flips the selected object between static and
  dynamic.
- `Ctrl+D`: duplicate the selected object one prefab half extent along +X, and
  select the copy. A duplicate at the object cap does nothing.
- `Delete` or `X`: remove the selected object.
- `Ctrl+Z`: undo the last place, delete, duplicate, move, wheel height, rotate,
  or body conversion. `Ctrl+Shift+Z`: redo it.
- `L`: toggle the sun placement. The sun follows the crosshair on a sky dome
  and the lighting updates live. A click commits the position; `Esc` or a right
  click restores the sun from before the mode.
- `R`: reset the player and return the camera to spawn.
- `Shift+R`: reset the placed objects, the sun, and the player.
- `F2`: leave debug mode. The player returns to the saved position and view.
- `Esc`: close the palette, cancel the placement, cancel the sun placement, or
  open the settings menu, in that order. The settings menu closes the palette and
  cancels the placement and the sun placement when it opens.

The palette shows the box prefabs in a six by two grid with a preview pane. Hover
or use the arrow keys to change the selection, `1`-`9` selects one of the first
nine cards, and `Enter` or a click picks. A click outside the panel closes it. A
click inside the panel that misses every card does nothing.

The HUD shows the stance, gait, horizontal speed, grounded state, movement
state, and position. In debug mode the inspector shows the selection as the
prefab and object id, the object count and capacity, and the selected object's
body, size, position, yaw, and snap state. Every changing value uses a fixed
field and the mono face, so the panel does not resize with the selection. While
the placement tool is armed, it shows the armed prefab, body, height, yaw, snap,
and object count instead. While sun placement is active, it adds a sun placement
row.
The settings menu shows the control list. Borderless fills the selected display;
Windowed uses the chosen resolution.

### Perf overlay

`F4` shows the perf overlay. It starts off and hides while the settings menu is
open.

The summary row holds frames per second, the frame interval, the CPU frame
time, the p95 interval, the spike count, and the GPU total with the costliest
pass. The pass row holds the last completed frame's GPU pass times: the TLAS
build, the depth prepass, the lit scene pass, the sky pass, the TAA resolve, and
the overlay pass.

The GPU numbers belong to the last completed frame, so they are two frames
behind the frame being recorded. A device without timestamp support shows the
CPU numbers only. The overlay adds seven timestamp writes per frame. Both sky
timestamps are written even when the sky is off, so the pass reads near zero.

## Agent harness

`bin/harbagsa-agent` drives the simulation and writes screenshots without a
window or compositor. `make build` builds it next to the game. Agent-specific
operational notes are in `docs/agents/harness.md`. Run
`./bin/harbagsa-agent --help` (or `-h`) for the command and option list.

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
- `--tag NAME`: append NAME to the run directory, so `runs/smoke/before` and
  `runs/smoke/after` coexist. The report records the final directory.
- `--size WxH`: capture size. Default: `1280x720`. A scenario `size` and
  `--size` together are an error.
- `--renderer-debug KEY=VALUE`: apply a gated renderer override before the
  commands. Repeat the flag for more fields. It needs the same gate as the
  command.
- `--no-render`: run the simulation and checks only. No Vulkan device is created.
- `--present`: render the real SDL window and capture the swapchain image
  before present. No compositor and no `grim`.
- `--debug-renderer`: accept the renderer debug command. A build with
  `-define:ENABLE_RENDERER_DEBUG=true` always accepts it.
- `--no-analysis`: skip `analysis.json` and the analysis maps.
- `--verbose` (or `--summary`): write the setup revision and dirty flag, every
  capture, every check result, every failure, and every named perf result to
  standard error. Standard output stays one JSON line.

`run -` reads the scenario from standard input. It leaves no throwaway file
behind:

```sh
printf '%s\n' '{"cmd":"step","frames":2}' | ./bin/harbagsa-agent run -
```

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
    {"field": "objects.1.position.z", "op": "lt", "value": 7.5}
  ]
}
```

One step means one fixed `SIMULATION_STEP`. `look` applies once before the
step. `forward`, `right`, and `jump` persist; `jump` is an edge on the first
frame of its block. Capture frames are zero-based frame numbers. Check operators
are `eq`, `ne`, `lt`, `le`, `gt`, and `ge`. Check fields use the `state.json`
shape, for example `player.position.y`, `player.grounded`, `objects.1.position.z`,
`objects.count`, `settings.window_mode`, `settings.resolution`, `menu.open`,
`debug.active`, `debug.placement.armed`, `renderer.taa_enabled`, or
`render_digest`. A capture check can
also read `capture.target`, `capture.format`, and `capture.stats.*` for the last
capture in its window. Add `"window": {"start": 2, "count": 8}` to aggregate over
part of the captures; `warmup` stays the shorthand for skipping the first N.

A run with captures writes `analysis.json`. It holds per-pair deltas, a
summary, the dominant period, the worst unstable pixels' series, and optional
diff and variance maps. The pair and pixel analysis uses color captures; a run
with only intermediate captures writes an empty summary. Checks read `analysis.period.frames`,
`analysis.period.correlation`, `analysis.bands.longest_run`,
`analysis.bands.median_run`, `analysis.bands.levels`, and the `analysis.worst_*`
fields. `analysis.bands` measures the identical-luma runs down the columns, so a
gradient that bands after the 8-bit write shows up as a long run. Disable it with
`"analysis": false` or `--no-analysis`; select a window and maps with
`"analysis": {"start": 2, "count": 8, "maps": true}`.

### Commands

The batch runner and the live session share one command set:

- `{"cmd": "reset"}`: fresh simulation. Placed objects return to spawn, the
  settings return to their defaults, the menu closes, and the debug palette,
  placement, and sun return to their defaults.
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
- `{"cmd": "state"}`: player, eye, velocity, yaw, pitch, grounded, objects,
  window and input settings, debug mode, menu, renderer state, render digest,
  frame, and simulation digest. Each object entry carries its id, prefab, body
  mode, position, rotation, scale, and spawn age. The debug entry carries
  `active`, `selection`, `selected_id`, the palette (`open`, `selected`,
  `body`), the placement (`armed`, `prefab`, `position`, `height`, `yaw`,
  `snap`), the sun (`active`, `position`, `azimuth`, `elevation`), the inspector
  (`prefab`, `body`, `size`, `position`, `yaw`, `snap`), and the history
  (`depth`, `redo`). The
  renderer object reports the frame count, TAA state, jitter index,
  history validity, convergence frames, history read index and weight, reset
  count and reason, shadow phase, and the active light count. `render_digest`
  covers the effective camera, sun, boxes, point lights, emissive strengths,
  jitter, shadow phase, and view flags.
- `{"cmd": "capture", "name": "shot", "frame": 90, "alpha": 1.0}`: write a PNG.
  `frame` is optional. A past frame is an error; a future frame queues. Add
  `"target": "velocity"`, `"history"`, `"depth"`, or `"scene_color"` to read an
  intermediate image, and `"format": "float"`, `"raw"`, `"stats"`, or
  `"profile"` to choose the output. The default is a color PNG. A stats capture
  accepts `"region": {"x","y","w","h"}` or `"rect": [x,y,w,h]` and an optional
  `"histogram": 8`. A color capture accepts `"crop": {"x","y","w","h","scale"}`
  to write a scaled PNG, and a `"profile"` block to measure an edge. Region,
  profile, and crop do not change the capture extent; the crop reports
  `written_width` and `written_height`.
- `{"cmd": "camera", "position": [0, 2, 12], "yaw": 0, "pitch": 0}`: inspection
  camera. It does not move the player. It accepts `look_at` instead of
  `yaw`/`pitch`, and `fov` in degrees (1..170). `look_at` with yaw/pitch is an
  error. `{"cmd": "camera", "clear": true}` drops the override.
- `{"cmd": "view", "hud": true, "debug": false, "hint": false, "perf": false}`:
  toggle the HUD, the debug draw, the capture hint, and the perf overlay.
- `{"cmd": "sun", "azimuth": 52.1, "elevation": 15, "diameter": 0.53}`: move the
  sun or resize its disk. `azimuth` is degrees from `+z` toward `+x`, `elevation`
  is degrees above the horizon, and `diameter` is the angle the sun disk
  subtends in degrees. Omitted fields keep the value. `{"cmd":"sun","clear":true}`
  restores the default direction and diameter. A change resets TAA history, like
  a scene change.
- `{"cmd": "crates", "clear": true}`: edit the dynamic crates. `reset` restores
  the starting three, `clear` removes every crate, `add` creates one crate or a
  row-major grid, and `remove` drops one by index. A grid add steps `columns`
  along x and then the next row along z. An add that would exceed the 64-crate
  limit is rejected as a whole.
- `{"cmd": "debug_mode", "active": true}`: enter or leave the `F2` debug mode.
  Entering swaps the player for the free-fly camera; leaving restores the player.
  Repeating the same value is a no-op.
- `{"cmd": "editor", "open": true, "select": 4, "body": "static", "pick": true, "height": 0.5, "yaw": 45, "snap": true, "cancel": false}`:
  drive the debug placement tool. The command needs debug mode. `open` opens or
  closes the object palette, `select` is the zero-based prefab index, `body` is
  `static` or `dynamic`, and `pick` arms the selected prefab. `height` is the
  offset above the surface in metres, `yaw` is the rotation in degrees, and
  `snap` toggles the 0.25 m X/Z grid. `cancel` clears the armed tool. Every field
  is optional; fields apply in that order, and the `sun` group applies last.
- `{"cmd": "editor", "camera": {"position": [0, 1.7, 14], "yaw": 0, "pitch": -0.6}}`:
  set the debug camera. `yaw` and `pitch` are radians, as in the `camera`
  command. The editor command accepts this alongside the other fields.
- `{"cmd": "editor", "place": {"prefab": "Block", "position": [0, 0.5, 10], "yaw": 0, "body": "static"}}`:
  create an object at an exact transform, bypassing the placement ray. `prefab`
  and `position` are required; `yaw` (degrees) defaults to 0 and `body` to the
  prefab's default.
- `{"cmd": "editor", "select_object": 1, "move": [1, 0.5, 7], "rotate": 15, "body": "static", "delete": false, "duplicate": true, "undo": false, "redo": false}`:
  edit a placed object by id. `select_object` is the object id, and 0 clears the
  selection. `move` sets the centre, `rotate` turns the object by degrees, and
  `body` flips between `static` and `dynamic` when the palette is closed. With
  the palette open, `body` still sets the next placement. `delete`, `duplicate`,
  `undo`, and `redo` are actions. A duplicate at the cap does nothing.
- `{"cmd": "editor", "sun": {"active": true, "position": [0, 40, -30], "place": false, "cancel": false}}`:
  drive the sun placement. `active` enters or leaves the mode, `position` sets
  the sun position directly, `place` commits and leaves, and `cancel` restores
  the sun from before the mode. The fields apply in that order and every field
  is optional.
- `{"cmd": "menu", "open": true, "select": 1, "activate": true, "direction": -1}`:
  open or close the settings menu, select a row, and activate the selected row.
  `select` is zero-based and needs an open menu. `activate` also needs an open
  menu. `direction` is `-1` or `1` (default `1`) and needs `activate`. Omitted
  fields keep the state. Opening the menu closes the object palette and cancels
  placement and sun placement. An open menu renders even when `hud` is off.
- `{"cmd": "check", "field": "player.position.y", "op": "gt", "value": 0}`:
  evaluate a predicate now. Use `other` to compare two fields.
- `{"cmd": "displays", "set": [{"name": "Solo", "desktop": "1280x720", "modes": ["1280x720"]}]}`:
  script the display list; `{"cmd":"displays","clear":true}` restores the
  fallback list. A display may have zero modes, which blocks the menu's
  Resolution row.
- `{"cmd": "rows"}`: reply with the HUD and menu rows: kind, label, value,
  blocked, ratio, and ticks.
- `{"cmd": "perf", "frames": 120, "warmup": 60, "prime": 2.0, "name": "default", "trace": "trace.jsonl"}`:
  measure frames. `frames` defaults to 120, `warmup` to 60, and `prime` to 2.0
  seconds (`0` disables the time loop). `name` labels the result; `report.json`
  keeps every named result in a `perf` array. `trace` writes one JSON object per
  measured frame; a relative path resolves against the run directory and a run
  holds one trace. Offscreen measures throughput; with `--present` it measures
  pacing. A run without a device reports CPU numbers only.
- `{"cmd": "renderer_debug", "jitter": false, "shadow_phase": 12}`: change
  renderer inputs. It needs `--debug-renderer` or a build with
  `-define:ENABLE_RENDERER_DEBUG=true`. `sky` and `ao` turn the sky and the
  ambient occlusion off. `clear` resets every override. Changing an input resets
  history.
- `{"cmd": "record", "path": "scenarios/walk.json"}`: start recording. Send
  `{"cmd": "record"}` to stop and write the scenario.
- `{"cmd": "replay", "path": "scenarios/walk.json"}`: reset and run a scenario.
- `{"cmd": "quit"}`: stop the session.

Unknown keys, wrong types, and out-of-range values are per-command errors. The
session stays usable.

The harness has no compositor, so it starts with a fixed two-display list.
`Display 1` is 1920x1080 with 1600x900 and 1280x720 below it. `Display 2` is
2560x1440 with 1920x1080 and 1280x720 below it. The `displays` command replaces
the list for a scenario. `settings.resolution` is the effective size:
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
every CPU phase and GPU pass, and the prime frame count. The GPU passes are the
TLAS build, the depth prepass, the lit scene, the sky, the TAA resolve, and the
overlay. The sky has its own timestamps. `prime` (seconds,
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
[the benchmark recipe](docs/agents/harness.md#benchmark-two-builds) or the
wrapper:

```sh
./bin/harbagsa-agent ab --base origin/main --scenario scenarios/perf.json --out runs/ab
```

The wrapper translates `--base` to the `tools/ab.sh` `--ref` flag and passes the
rest through. It writes the same `summary.json` and `summary.md`.

### Movement checks

`scenarios/step-angle.json` walks from spawn to the 0.35 m step, turns, and
climbs it at 60 degrees. It gates that an angled approach takes the step instead
of sliding along the riser. The scenario needs no renderer:

```sh
./bin/harbagsa-agent run scenarios/step-angle.json --no-render
```

`scenarios/perf-lamps.json` injects eight synthetic point lights through the
renderer debug override, then measures the same view with point-light shadows on
and off. It writes `trace-shadows-on.jsonl` and `trace-shadows-off.jsonl` in one
run, so the shadow cost is a paired comparison. Only a build with
`ENABLE_RENDERER_DEBUG` or a run with `--debug-renderer` accepts it. The result
is in [the point light evidence](docs/evidence/perf-lamps.md).

### Screenshot workflow

```sh
make build
./bin/harbagsa-agent run scenarios/smoke.json
```

The one-command form prints the capture paths:

```sh
make shot SCENARIO=scenarios/ui.json
make ui
make smoke
```

Read `runs/smoke/report.json` and use the absolute paths in `screenshots`. The
PNG is RGBA, sRGB, and `1280x720` by default. Evidence is a run directory plus a
scenario: run a scenario into `runs/<scenario-stem>/` and read `frames/`. To
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

`scenarios/editor-ghost.json` enters debug mode, picks the platform prefab, and
captures the ghost on the floor and raised, then places a block and cancels the
tool. It checks the palette, placement, and object state without a window.

`scenarios/debug-palette.json` opens the object palette in debug mode and
captures the Platform and Ramp previews. Run it with `--size 800x600` to check
that the bottom dock still fits and clears the crosshair.

`scenarios/editor-sun.json` enters sun placement, captures the sun gizmo on the
sky dome, sets an exact sun position, and captures the committed lighting.
`scenarios/editor-object.json` edits a placed object, captures the inspector,
then captures the undo and redo restores.

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

`renderer_debug` changes TAA inputs and point-light inputs for a diagnosis: TAA,
jitter, history weight, clamp, depth trust, the shadow phase, the point-light
shadow switch, and the synthetic light count. Every build rejects it unless
`--debug-renderer` is passed or the build used the `ENABLE_RENDERER_DEBUG`
define. Changing an input resets history and records the `debug_override`
reason.
`scenarios/renderer-debug.json` covers the overrides, and
`scenarios/renderer-debug-converge.json` shows the image converging with jitter
off. `scenarios/renderer-debug-jitter.json` freezes the phase, lets jitter
cycle, and writes the analysis maps. `scenarios/capture-free.json` settles
without captures and then captures; run it twice and compare the digests and PNG
hashes to prove the offscreen sequence is deterministic.

`scenarios/sky-ao.json` captures the sky gradient and one arena corner with
ambient occlusion off and on, then the zenith with the sky off, and checks the
mean green channel. It needs `--debug-renderer`, because it changes the `ao`
and `sky` overrides:

```sh
./bin/harbagsa-agent run scenarios/sky-ao.json --debug-renderer
```

The zenith gate fails when the sky is off, the corner gates fail when the AO is
never re-enabled, and the flat-zenith gate fails when the sky never turns off.

### Compare two runs

```sh
./bin/harbagsa-agent diff runs/before runs/after
./bin/harbagsa-agent diff runs/before runs/after --max-pixels 0 --json
```

`diff` pairs the PNG captures by name from each `report.json` `screenshots`
array. When a run has no report, or an entry has no readable path, it uses
`frames/<name>.png`. Each row reports the size, the number of different pixels,
the largest RGB channel delta, the mean delta, the count over 16, and whether
the pair is identical. Alpha is ignored. `analysis-diff.png` and
`analysis-variance.png` are derived maps, so the frame fallback skips them.

Exit codes:

- `0`: every pair is present, the sizes match, and no pair is over the limit.
- `1`: a pair is missing, a pair differs in size, or `--max-pixels N` is
  exceeded.
- `2`: bad arguments or a run directory that cannot be read.

Without `--max-pixels`, differences are reported but do not fail the command.
`--json` prints one object with `run_a`, `run_b`, `ok`, `pairs`, and `errors`
instead of the table. Compare `setup.revision` and `setup.dirty` before the
pixels so a dirty tree is not mistaken for a revision change.

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
runs the display, physics, simulation, frame, perf, harness, renderer, and docs
tests headless. The offscreen render test logs a skip when no Vulkan device is
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
