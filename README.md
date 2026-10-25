# harbagsa

A first-person movement demo. The player walks, sprints, crouches, crawls,
jumps, dives, slides, and mantles in a fixed arena with stairs, ramps, tunnels,
mantle walls, a dive platform, and pushable crates. SDL3 provides the window and
input, raw Vulkan 1.3 with ray-query shadows draws the scene, and Box3D runs the
physics. A directional sun casts hard contact shadows and softer distant
shadows from the walls and crates. An analytic sky gradient fills the
background. Ray-traced ambient occlusion uses the same scene acceleration
structure to darken the ambient light in shade, corners, and tunnels. A sunlit
surface keeps its full ambient.

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
- `F5`: write a repro scenario to `runs/repro/`. It holds the camera, sun,
  placed objects, settings, view flags, and display list.
- `Esc`: open the settings menu. The menu pauses the game and releases the
  cursor. Press `Esc` again to resume.

### Settings menu

`Esc` opens a centered settings menu. The menu pauses the simulation. It changes
the window mode, the display, the resolution, the type weight, and the sprint,
crouch, and prone input modes, and below them it lists the active controls as a
key legend.

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
- `M`: flip the body mode for the next placement while the palette is open or
  the placement tool is armed. Otherwise it flips the selected object between
  static and dynamic.
- `Ctrl+D`: duplicate the selected object one prefab half extent along +X, and
  select the copy. A duplicate at the object cap does nothing.
- `Delete` or `X`: remove the selected object.
- `Ctrl+Z`: undo the last place, delete, duplicate, move, wheel height, rotate,
  or body conversion. `Ctrl+Shift+Z`: redo it.
- `C`: cycle the next lamp's light colour through warm, cool, red, green, and
  blue. With the palette closed and a placed lamp selected, it edits that lamp.
- `[` / `]`: change the lamp light intensity in 0.2 steps from 0.2 to 4.0.
- `,` / `.`: change the lamp light range in 1 m steps from 2 to 20 m.
  The light settings stick to the next placement until the prefab changes. A
  non-lamp object ignores them. The palette preview, the inspector, and the
  ghost show the current light.
- `L`: toggle the sun placement. The sun follows the crosshair on a sky dome
  and the lighting updates live. A click commits the position; `Esc` or a right
  click restores the sun from before the mode.
- `R`: reset the player and return the camera to spawn.
- `Shift+R`: reset the placed objects, the sun, and the player.
- `F5`: write a repro scenario to `runs/repro/`.
- `F2`: leave debug mode. The player returns to the saved position and view.
- `Esc`: close the palette, cancel the placement, cancel the sun placement, or
  open the settings menu, in that order. The settings menu closes the palette and
  cancels the placement and the sun placement when it opens.

The palette shows the eleven box prefabs in a six by two grid with a preview
pane. Hover or use the arrow keys to change the selection, `1`-`9` selects one of
the first nine cards, and `Enter` or a click picks. A click outside the panel
closes it. A click inside the panel that misses every card does nothing. A lamp
card glows, and the preview adds the colour, intensity, and range line.

The HUD shows the stance, gait, horizontal speed, grounded state, movement
state, and position. In debug mode the inspector shows the selection as the
prefab and object id, the object count and capacity, the selected object's body,
size, position, yaw, and snap state, its light values for a lamp, and the active
light count against the lamp count. Every changing value uses a fixed field and
the mono face, so the panel does not resize with the selection. While the
placement tool is armed, it shows the armed prefab, body, height, yaw, snap,
object count, and the next lamp light instead. While sun placement is active, it
adds a sun placement row. The eight nearest lamps to the camera are active; the
rest stay emissive but do not light the scene.
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
- `--param NAME=VALUE[,VALUE...]`: override a scenario parameter. A comma list
  runs one scenario per value; repeat the flag for every parameter and the
  runner takes the cartesian product. See **Parameter sweep**.
- `--size WxH`: capture size. Default: `1280x720`. A scenario `size` and
  `--size` together are an error.
- `--renderer-debug KEY=VALUE`: apply a gated renderer override before the
  commands. Repeat the flag for more fields. It needs the same gate as the
  command.
- `--no-render`: run the simulation and checks only. No Vulkan device is created,
  captures are skipped, and a perf run measures CPU time only.
- `--present`: render the real SDL window and capture the swapchain image
  before present. No compositor and no `grim`.
- `--debug-renderer`: accept the renderer debug command. A build with
  `-define:ENABLE_RENDERER_DEBUG=true` always accepts it, and so does a
  scenario that declares `"requires": {"renderer_debug": true}`.
- `--no-analysis`: skip `analysis.json` and the analysis maps.

`run -` reads the scenario from standard input. It leaves no throwaway file
behind:

```sh
printf '%s\n' '{"cmd":"step","frames":2}' | ./bin/harbagsa-agent run -
```

The harness view starts with the HUD off, the debug draw off, and the capture
hint off. Only a `capture` command writes a PNG. A scenario with no capture and
no perf run never creates a Vulkan device unless `--present` asks for the
window.

### Parameter sweep

A scenario declares its knobs and uses `${name}`:

```json
"parameters": {"lamp_x": 20.0},
"commands": [
  {"cmd": "editor", "place": {"prefab": "Lamp",
   "position": ["${lamp_x}", 2.0, -19.5]}}
]
```

`--param` overrides a value. A comma list runs one scenario per value:

```sh
./bin/harbagsa-agent run scenarios/lamp-threshold.json \
  --param lamp_x=20,19.999,19.99,19.9 --out runs/lamp-threshold
```

Each value gets its own run directory, and the parent gets `sweep.json`:

```text
runs/lamp-threshold/
  sweep.json
  lamp_x=20/report.json
  lamp_x=19.999/report.json
  lamp_x=19.99/report.json
  lamp_x=19.9/report.json
```

Repeat `--param` for more parameters; the runner takes the cartesian product,
with the last parameter changing fastest. A value cannot hold a comma, and a
sweep holds at most 256 runs. One value is a plain run, so
`--param lamp_x=19.999` writes the usual run directory and no `sweep.json`.

`sweep.json` lists each combination's parameters, run directory, report, state,
digest, exit code, and error. The process exit code is the highest of the runs,
so one bad combination fails the sweep while the rest still run. An override
must match a `${name}` in the scenario, and it must parse as the declared type.

Read the per-value metrics from the reports:

```sh
for report in runs/lamp-threshold/*/report.json; do
  jq -r '[.scenario.parameters[0].value,
          .screenshots[0].stats.gradient[1]] | @tsv' "$report"
done
```

The report stores statistics as arrays in RGBA order. A check names the same
channels `x`, `y`, `z`, and `w`, so `capture.named.wall.stats.gradient.y` is
green.

### Suites

A suite manifest names scenarios to run in order. The first manifests are
`suites/renderer.json`, `suites/offscreen.json`, and `suites/ui.json`:

```sh
./bin/harbagsa-agent suite renderer
./bin/harbagsa-agent suite renderer --list
./bin/harbagsa-agent suite offscreen --json
```

A manifest entry is a scenario name, or an object with `scenario` and optional
`label`, `size`, `params`, and `no_render`. The scenario owns its `requires`;
the suite reads the merged scenario after `extends` and lets the runner enable
the gate. The exit code is the highest entry code. The run directory holds
`suite.json` beside one directory per entry.

`make validate-offscreen` runs `suites/offscreen.json` with the validation
build. `make ui` runs `suites/ui.json`. `make suite SUITE=renderer` runs the
normal agent. `--list` shows each entry's size, gate, and render mode without
running it. `--fail-fast` stops at the first failure; the default runs every
entry.

### Compare two runs

`compare` writes a labeled before/after panel for the captures that share a
name:

```sh
./bin/harbagsa-agent compare runs/before runs/after
./bin/harbagsa-agent compare runs/before runs/after --out runs/compare/stairs
```

The default output is `runs/compare/<a>-vs-<b>/compare.png` with
`compare.json` beside it. The header names each scenario, revision, dirty flag,
and run directory. Each row names the capture, its frame and extent, and the
pixel delta. A missing pair or a size mismatch is labeled in the panel and
exits 1. A long comparison splits into `compare-2.png`, `compare-3.png`, and so
on; `compare.json` lists every page.

`compare` uses the embedded font stack and writes PNGs, so it needs no
ImageMagick or compositor. Keep the output under `runs/`; an image never enters
the repository. `diff` stays the numeric command.

### Live repro

`F5` in the game writes `runs/repro/repro-<unix>.json` and logs the absolute
path. The file is a normal scenario with one `scene` command; run it directly:

```sh
./bin/harbagsa-agent run runs/repro/repro-1750000000.json
```

The scene carries the camera source and view, the player pose when the source is
`player`, the sun, every placed object with its exact rotation and light, the
window and input settings, the type weight, the display list, and the view
flags. `record` starts with the same scene, so a recording begins from the live
state instead of a bare reset.

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

A scenario may declare `"size": "1280x720"` to pin its pixels. It may extend
another scenario with `"extends": "base.json"`, which merges the base object and
lets the child win. A `parameters` block substitutes `${name}` in any command
value; a parameter must be a string, number, or boolean. The base path resolves
against the extending file. A placeholder is always a JSON string, so a number
in an array is written `["${lamp_x}", 2.0, -19.5]`; substitution puts the
parameter's own type in its place.

The `commands` array runs verbatim, and `record` writes this form. Only a
`capture` command writes a PNG; a scenario without one renders nothing unless
`--present` asks for the window. One step means one fixed `SIMULATION_STEP`.
`look` applies once before the step. `input` persists until the next `input`;
`jump` is an edge on the first frame of its block. Capture frames are
zero-based frame numbers.

Check operators are `eq`, `ne`, `lt`, `le`, `gt`, and `ge`. A numeric check
takes an optional `tolerance`; it applies to `eq` and `ne` and is absolute.
A tolerance on an ordering op or a non-number is an error. A check compares
with `value`, or with another field with `other`:
`{"cmd":"check","field":"capture.1.stats.mean.y","op":"gt","other":"capture.0.stats.mean.y"}`.
A type mismatch or a missing field is a check error. `capture.N.*` names one
capture in the window; `capture.first` and `capture.last` are aliases.
`capture.named.<name>.*` names a capture by its `name`; a missing name is a
check error.

Every angle in a scenario, `state.json`, and `report.json` is in degrees, and
every angle key ends in `_deg`. Positions and distances are metres unless a
field says otherwise. `look` deltas are pixels. `step.frames` and `perf.frames`
are frames; `perf.prime` is seconds. Capture regions and crops are pixels.

Check fields use the `state.json` shape, for example `player.position.y`,
`player.grounded`, `player.stance`, `objects.1.position.z`, `objects.count`,
`settings.window_mode`, `settings.resolution`, `settings.type_weight`,
`menu.open`, `menu.status`, `menu.blocked`, `debug.active`,
`debug.placement.armed`, `debug.sun.angular_diameter_deg`, `sun.elevation_deg`,
`sun.angular_diameter_deg`, `camera.yaw_deg`, `camera.fov_deg`, `camera.source`,
`camera.overridden`, `player.yaw_deg`, `settle.converged`,
`rows.menu.3.kind`, `renderer.taa_enabled`, `renderer.text_truncated_runs`, or
`render_digest`. A capture check can also read `capture.target`,
`capture.format`, `capture.stats.*`, `capture.region.*`, `capture.profile.*`,
`capture.crop.*`, `capture.histogram.*`, `capture.png`, and
`capture.render_digest` for the last capture in its window.
`capture.stats.steps.count`, `.pairs`, and `.max` read the visibility-band
metric; a stats capture must name a region. Add
`"window": {"start": 2, "count": 8}` to aggregate over part of the captures;
`warmup` stays the shorthand for skipping the first N.

A run with captures writes `analysis.json`. It holds per-pair deltas, a
summary, the dominant period, the worst unstable pixels' series, and optional
diff and variance maps. The pair and pixel analysis uses color captures; a run
with only intermediate captures writes an empty summary. Checks read
`analysis.period.frames`, `analysis.period.correlation`,
`analysis.bands.longest_run`, `analysis.bands.median_run`,
`analysis.bands.levels`, and the `analysis.worst_*` fields. `analysis.bands`
measures the identical-luma runs down the columns, so a gradient that bands
after the 8-bit write shows up as a long run. Disable it with
`"analysis": false` or `--no-analysis`; select a window and maps with
`"analysis": {"start": 2, "count": 8, "maps": true}`.

### Commands

The batch runner and the live session share one command set:

- `{"cmd": "reset"}`: fresh simulation. Placed objects return to spawn, the
  settings return to their defaults, the menu closes, and the debug palette,
  placement, and sun return to their defaults.
- `{"cmd": "look", "dx": 220, "dy": 0}`: pixel look delta through the game
  sensitivity and pitch clamp.
- `{"cmd": "face", "yaw_deg": 0, "pitch_deg": 0}`: set the player view directly.
  Both angles are degrees.
- `{"cmd": "input", "forward": 1, "right": 0, "jump": false}`: set persistent
  input. Omitted fields keep their value.
- `{"cmd": "step", "frames": 60}`: fixed steps with no wall clock. A step is an
  error while the menu is open.
- `{"cmd": "settle", "frames": 520}`: fixed steps that render every frame but
  write no PNG. Use it to advance the temporal history before a capture. A
  settle is an error while the menu is open. Under `--no-render`, or in a
  scenario with no captures, it is a plain step.
  `{"cmd":"settle","until":"converged"}` waits for the 512-sample cap and reports
  the frames and the result in `settle.frames` and `settle.converged`.
- `{"cmd": "state"}`: player, eye, velocity, `yaw_deg`, `pitch_deg`, stance, grounded, camera,
  objects, window and input settings, debug mode, menu, rows, settle, renderer
  state, render digest, frame, and simulation digest. Each object entry carries
  its id, prefab, body mode, position, rotation, scale, spawn age, and light
  (`active`, `color`, `intensity`, `range`). The debug entry carries `active`,
  `selection`, `selected_id`, the palette (`open`, `selected`, `body`), the
  placement (`armed`, `prefab`, `position`, `height`, `yaw_deg`, `snap`, `light`),
  the sun (`active`, `position`, `azimuth_deg`, `elevation_deg`,
  `angular_diameter_deg`), the inspector (`prefab`, `body`, `size`, `position`,
  `yaw_deg`, `snap`, `light`),
  the light budget (`lights.active`, `lights.lamps`), and the history (`depth`,
  `redo`). Every angle field ends in `_deg` and is in degrees. `camera` reports
  the view the renderer uses: position, `yaw_deg`, `pitch_deg`, `fov_deg`,
  `source` (`player`,
  `debug`, or `override`), and whether an override is active.
  `rows` dumps the HUD and menu rows. The renderer object reports the frame
  count, TAA state, jitter index, history validity, convergence frames, history
  read index and weight, reset count and reason, shadow phase, the active light
  count, the applied atlas weight, text truncations and dropped fonts, and the
  debug override values. `render_digest` covers the target extent, the effective
  camera, sun direction and angular diameter, boxes, point lights, emissive
  strengths, jitter, shadow phase, applied atlas weight, the sky and AO flags,
  and view flags.
- `{"cmd": "capture", "name": "shot", "frame": 90, "alpha": 1.0}`: write a PNG.
  `frame` is optional. A past frame is an error; a future frame queues. Add
  `"target": "velocity"`, `"history"`, `"depth"`, or `"scene_color"` to read an
  intermediate image, and `"format": "float"`, `"raw"`, `"stats"`, or
  `"profile"` to choose the output. The default is a color PNG. A stats capture
  accepts `"region": {"x","y","w","h"}` or `"rect": [x,y,w,h]` and an optional
  `"histogram": 8`. A color capture accepts `"crop": {"x","y","w","h","scale"}`
  to write a scaled PNG, and a `"profile"` block to measure an edge. Add
  `"png": true` to a color `stats` or `profile` capture to write the image
  beside the numbers. One capture stays one result. Region, profile, and crop
  do not change the capture extent; the crop reports `written_width` and
  `written_height`. A capture name is unique in one run; a second capture with
  the same name is an error.
- `{"cmd": "camera", "position": [0, 2, 12], "yaw_deg": 0, "pitch_deg": 0}`: inspection
  camera. It does not move the player. It accepts `look_at` instead of
  `yaw_deg`/`pitch_deg`, and `fov_deg` in degrees (1..170). `look_at` with
  `yaw_deg`/`pitch_deg` is an error. `{"cmd": "camera", "clear": true}` drops the override.
- `{"cmd": "view", "hud": true, "debug": false, "hint": false, "perf": false}`:
  toggle the HUD, the debug draw, the capture hint, and the perf overlay.
- `{"cmd": "sun", "azimuth_deg": 52.1, "elevation_deg": 15, "diameter_deg": 0.53}`: move the
  sun or resize its disk. `azimuth_deg` is degrees from `+z` toward `+x`,
  `elevation_deg` is degrees above the horizon, and `diameter_deg` is the angle
  the sun disk subtends in degrees. Omitted fields keep the value, and at least one field is
  required. `{"cmd":"sun","clear":true}` restores the default direction and
  diameter. A change resets TAA history, like a scene change.
- `{"cmd": "debug_mode", "active": true}`: enter or leave the `F2` debug mode.
  Entering swaps the player for the free-fly camera; leaving restores the player.
  Repeating the same value is a no-op.
- `{"cmd": "editor", "open": true, "select": 4, "body": "static", "pick": true, "height": 0.5, "yaw_deg": 45, "snap": true, "cancel": false}`:
  drive the debug placement tool. The command needs debug mode. `open` opens or
  closes the object palette, `select` is the zero-based prefab index, `body` is
  `static` or `dynamic`, and `pick` arms the selected prefab. `height` is the
  offset above the surface in metres, `yaw_deg` is the rotation in degrees, and
  `snap` toggles the 0.25 m X/Z grid. `light_color` is `warm`, `cool`, `red`,
  `green`, or `blue`; `light_intensity` is in [0.2, 4.0] and `light_range` in
  [2, 20]. The light fields tune the next lamp placement, or the selected lamp
  when neither the palette nor the placement tool owns the editor. `cancel`
  clears the armed tool. Every field is optional; fields apply in that order,
  and the `sun` group applies last. A rejected edit returns `ok: false` with a
  reason.
  The pointer and relative fields mirror the keyboard: `palette_step` and
  `palette_number` select a card, `flip_body` is `M`, `snap_toggle` is `G`,
  `turn` and `wheel` step the armed tool or the selection, `large` applies the
  Shift step, `primary` and `secondary` are the mouse buttons, and
  `drag_move`/`drag_release` drive one object drag.
- `{"cmd": "editor", "camera": {"position": [0, 1.7, 14], "look_at": [0, 1.7, 4]}}`:
  set the debug camera. It accepts `look_at` or `yaw_deg` and `pitch_deg`, never
  both; the angles are degrees, as in the `camera` command. The editor command accepts
  this alongside the other fields.
- `{"cmd": "editor", "place": {"prefab": "Block", "position": [0, 0.5, 10], "yaw_deg": 0, "body": "static"}}`:
  create an object at an exact transform, bypassing the placement ray. `prefab`
  and `position` are required; `yaw_deg` (degrees) defaults to 0 and `body` to the
  prefab's default.
- `{"cmd": "editor", "select_object": 1, "move": [1, 0.5, 7], "rotate_deg": 15, "body": "static", "delete": false, "duplicate": true, "undo": false, "redo": false}`:
  edit a placed object by id. `select_object` is the object id, and 0 clears the
  selection. `move` sets the centre, `rotate_deg` turns the object by degrees, and
  `body` flips between `static` and `dynamic`. The open palette or the armed
  placement tool owns it; otherwise it converts the selection. `delete`, `duplicate`,
  `undo`, and `redo` are actions. A duplicate at the cap does nothing.
- `{"cmd": "editor", "sun": {"active": true, "position": [0, 40, -30], "place": false, "cancel": false}}`:
  drive the sun placement. `active` enters or leaves the mode, `position` is
  projected onto the 50 m sky dome and clamped above the arena floor, `place`
  commits and leaves, and `cancel` restores the sun from before the mode. The
  fields apply in that order and every field is optional.
- `{"cmd": "menu", "open": true, "item": "Type weight", "activate": true, "direction": -1, "set": 900}`:
  open or close the settings menu, select a row by name, activate the selected
  row, or set the Type weight. `item` is `Window mode`, `Display`, `Resolution`,
  `Type weight`, `Sprint mode`, `Crouch mode`, `Prone mode`, or `Resume`, and
  needs an open menu. `activate` and `set` also need an open menu. `direction`
  is `-1` or `1` (default `1`) and needs `activate`; `set` is a weight in
  100..900. Omitted fields keep the state. Opening the menu closes the object
  palette and cancels placement and sun placement. An open menu renders even
  when `hud` is off.
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
  ambient occlusion off, `light_shadows` turns the point-light shadows off, and
  `synthetic_lights` replaces the frame's lamps with 0 to 8 test lights. `clear`
  resets every override. Changing an input resets history.
- `{"cmd": "scene", ...}`: apply an exact scene with `camera`, `sun`, `objects`,
  `settings`, `view`, and `displays` blocks. `F5` writes one and `record` starts
  with one; see **Live repro**.
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
overlay. The sky has its own timestamps. `prime` (seconds, default 2.0) warms the
device clock before the measured window. `name` labels the result and
`report.json` keeps every named result in a `perf` array. Add
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
them at the same size to compare two builds. `scenarios/perf-crates.json`
places 60 objects in a grid with the Crate prefab and measures them, so the box
count is part of the probe.

`scenarios/perf-lamps.json` injects eight synthetic point lights through the
renderer debug override, then measures the same view with point-light shadows on
and off. It writes `trace-shadows-on.jsonl` and `trace-shadows-off.jsonl` in one
run, so the shadow cost is a paired comparison. Only a build with
`ENABLE_RENDERER_DEBUG` or a run with `--debug-renderer` accepts it. The result
is in [the point light evidence](docs/evidence/perf-lamps.md).

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
of sliding along the riser. `scenarios/ramp-headroom.json` puts a prone player
under each ramp and tries to stand; it gates that the stance stays low instead
of growing through the slab. Both scenarios need no renderer:

```sh
./bin/harbagsa-agent run scenarios/step-angle.json --no-render
./bin/harbagsa-agent run scenarios/ramp-headroom.json --no-render
```

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
scenario: point at the run, not at a checked-in image. To capture the owner's
real window instead:

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

`scenarios/blocked-note.json` opens the menu, blocks the Type weight at 900,
captures the status note, sets the weight to 400, and captures the cleared note.

`scenarios/type-weight.json` opens the menu, selects Type weight, captures 400,
sets 900 and 100, captures both, and checks the stored value.

`scenarios/sky-ao.json` captures the arena with the sky and the ambient
occlusion on, off, and split, so the two terms can be compared at the same
camera. `scenarios/stairs-ao.json` captures the dive stairs at a 25° sun and
checks that the AO leaves the sunlit floor alone while the shaded wall still
darkens. `scenarios/shadow-angle.json` puts the sun 15 degrees above the horizon
and captures a wall shadow twice: once with a 3-degree sun disk, then with the
0.53-degree disk the build uses. The penumbra width follows the diameter, so
the small disk gives a shadow edge about 5.7 times narrower.
`scenarios/ramp-shadow.json` looks at the shaded floor below the 20 degree ramp
and gates the step count in a region that holds no geometry edge. The step
metric box-filters the luma, so the output dither drops out and a ray-count
step remains.

`scenarios/editor-ghost.json` enters debug mode, picks the platform prefab, and
captures the ghost on the floor and raised, then places a block and cancels the
tool. It checks the palette, placement, and object state without a window.

`scenarios/debug-palette.json` opens the object palette in debug mode and
captures the Platform and Ramp previews. Run it with `--size 800x600` to check
that the bottom dock still fits and clears the crosshair.

`scenarios/editor-sun.json` enters sun placement, captures the sun gizmo on the
sky dome, sets a sun position through the dome projection, and captures the
committed lighting.
`scenarios/editor-object.json` edits a placed object, captures the inspector,
then captures the undo and redo restores. `scenarios/editor-lamps.json` captures
the three lamp previews, places a warm lamp, a cool panel, a red beacon, and a
pillar, then captures the lit scene, the point-light shadow, and the selected
lamp edit with its undo. `scenarios/editor-input.json` drives the pointer,
wheel, relative turn, palette step, number key, snap toggle, and right-click
clear through the same action set as the keyboard. `scenarios/lamp-wall-plane.json`
aims the debug camera at a wall, arms the Lamp, and clicks the ghost, so the
anchor and `debug_placement_place` are part of the regression. A wall gradient
check gates the shadow fan directly, without a before/after pair. It also
captures a crate with the point-light shadows on and off to prove the point
light still casts. The scenario declares `requires.renderer_debug`, so it needs
no flag, and `make validate-offscreen` runs it.

`scenarios/window-settings.json` opens the menu, moves to Display 2, switches to
Windowed, changes the resolution, captures the result, and checks the window
settings.

`scenarios/renderer-state.json` settles a static scene, captures it, and checks
the renderer state and render digest. `scenarios/renderer-reset.json` teleports
the camera and checks that the history reset names the teleport. `report.json`
also carries a `setup` block: target kind, extent, view flags, the renderer
debug gate, the renderer config, and the AO sample count, radius, and strength,
so a run is reproducible.

A capture can read an intermediate target. `"target": "velocity"` with
`"format": "stats"` reports per-channel min, max, mean, `stddev`, and
`gradient`, plus the median screen motion in texels for a velocity target. The
gradient is the mean absolute difference between 4-neighbour pixels over the
region. `"format": "float"` writes a `.f32` file and `"raw"` writes the exact
texel bytes. A PNG capture is color only.
`scenarios/capture-targets.json` covers every target.

`renderer_debug` changes renderer inputs for a diagnosis: TAA, jitter, history
weight, clamp, depth trust, the shadow phase, the point-light shadow switch,
the synthetic light count, the sky, and the ambient occlusion. Every build
rejects it unless `--debug-renderer` is passed, the build used the
`ENABLE_RENDERER_DEBUG` define, or the scenario declares
`"requires": {"renderer_debug": true}`. Changing an input resets history and
records the `debug_override` reason.
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
runs the display, platform, physics, simulation, frame, perf, harness, renderer,
and docs tests headless. The offscreen render test logs a skip when no Vulkan
device is available.

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

`make validate-demo` runs the demo with validation enabled for a manual
session. It returns when you close the window.

Both targets check for `VK_LAYER_KHRONOS_validation` first. If the layer is
missing, they print the install command and exit without starting anything.
They never install anything. `make check` and `make test` never enable
validation.

To run Odin directly instead:

```sh
odin run . -collection:src=src -collection:libs=vendor -define:ENABLE_VALIDATION_LAYERS=true
```

## Clean

```sh
make clean
```
