# Agent harness

`bin/harbagsa-agent` drives the simulation, runs checks, and writes exact
screenshots. It needs no window, compositor, cursor capture, or `grim`.

The user-facing command reference is `README.md` under **Agent harness**. This
page is the short operational guide for agents.

## Quick start

Five recipes. Each writes a run directory; read `report.json` for the result.

1. Capture the HUD:

   ```sh
   tools/make.sh build
   ./bin/harbagsa-agent run scenarios/hud.json --out runs/ui/hud
   jq -r '.screenshots[].path' runs/ui/hud/report.json
   ```

2. Capture the settings menu:

   ```sh
   ./bin/harbagsa-agent run scenarios/settings-menu.json --out runs/ui/menu
   ```

3. Assert a state without a renderer:

   ```sh
   ./bin/harbagsa-agent run scenarios/smoke.json --no-render --out runs/smoke
   ```

   A check is one JSON object: `{"cmd":"check","field":"player.position.y","op":"gt","value":0}`.
   Use `other` to compare two fields.

4. Record a scenario from a live session:

   ```sh
   printf '%s\n' \
     '{"cmd":"record","path":"/tmp/opencode/walk.json"}' \
     '{"cmd":"step","frames":60}' \
     '{"cmd":"record"}' |
     ./bin/harbagsa-agent session
   ```

5. Measure a build:

   ```sh
   ./bin/harbagsa-agent run scenarios/perf.json --out runs/perf
   jq -r '.perf[0].gpu.scene' runs/perf/report.json
   ```

## First move

```sh
tools/make.sh build
./bin/harbagsa-agent run scenarios/smoke.json
```

Read `runs/smoke/report.json`. Use the absolute paths in `screenshots`. Exit
code 0 means every check passed.

Use `tools/make.sh` when another agent may build in the same checkout. It
serializes Make with `flock`.

## Surface map

| Task | Read |
| --- | --- |
| drive the simulation | **Scenario format** and **Commands** |
| drive the object palette, placement, object edits, and history | **Editor** |
| drive the sun placement | **Editor** |
| capture the final image | **Capture targets** (`color` + `png`) |
| read velocity, history, depth, or scene color | **Capture targets** |
| read numeric image statistics | **Capture targets** (`stats`) |
| read renderer state or the render digest | **Renderer state** |
| change a renderer input for a diagnosis | **Renderer debug overrides** |
| check the sky and the ambient occlusion | **Sky and ambient occlusion** |
| test lighting inside the closed room | **Interior room** |
| measure image stability or the period | **Analysis** |
| compare two builds or revisions | **Cross-run diff** and **Cross-run compare** |
| discover command fields and check paths | `harbagsa-agent schema` |
| script the display list | **Commands** (`displays`) |
| dump the HUD and menu rows | **Commands** (`rows`) |
| measure an edge or a gradient | **Capture targets** and **Analysis** |
| compare two builds | **Performance** and `ab` |
| measure frame time | **Performance** |
| prove a capture-free sequence is deterministic | **Screenshots** and `scenarios/capture-free.json` |
| reproduce a live view | **Live session** and `docs/adr/0025` |
| understand a design choice | `docs/adr/0008` to `docs/adr/0026` |

## What one run writes

`runs/<scenario-stem>/`

- `report.json`: `ok`, `exit_code`, `scenario` (`path`, `hash`, and the
  effective `parameters`), `run_dir`,
  `frame`, `state`, `setup`, `screenshots`, `checks`, `failures`, `digest`,
  `error`, `perf` (a list of named reports) when perf ran, `trace` when the run
  wrote a perf trace, and `analysis` when the run wrote an analysis report.
- `analysis.json`: the per-run image analysis. See **Analysis**.
- `frames/analysis-diff.png` and `frames/analysis-variance.png`: the optional
  analysis maps.
- `trace.jsonl`: one JSON object per measured frame, when the perf command asks
  for a trace. A run holds one trace.
- `state.json`: the final state alone. It holds the player, camera, placed
  objects, window and input settings, the debug mode, menu, rows, settle, frame,
  renderer, render digest, and simulation digest. Each object carries `id`,
  `prefab`, `body`, `position`, `rotation`, `scale`, `spawn_age`, and `light`
  (`active`, `color`, `intensity`, `range`). The debug mode carries the palette,
  the placement tool, the sun, the inspector, the light budget, and the history.
- `frames/<name>.png`, `.f32`, or `.bin`: captures. A color capture is a PNG;
  `float` and `raw` write the intermediate target.
- Each screenshot entry carries `delta_mean`, `delta_max`, and `delta_over_16`
  against the previous capture. The first capture has zeros.
- `run.log`: log lines from the renderer, the session, and the runner.

Standard output is one JSON summary. Standard error holds logs.

`run -` reads the scenario from standard input. `--tag NAME` appends a directory
to the run path, so `runs/smoke/before` and `runs/smoke/after` coexist.
`--param NAME=VALUE[,VALUE...]` overrides a scenario parameter, and a comma
list runs a sweep. See **Parameter sweep**.
`--renderer-debug KEY=VALUE` applies one gated override before the commands;
repeat the flag for more fields.

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
    {"field": "objects.1.position.z", "op": "lt", "value": 7.5}
  ]
}
```

Rules:

- The `commands` array runs verbatim, and `record` writes this form.
- One step is one `SIMULATION_STEP` (1/60 s). The harness does not use wall-clock
  time.
- `look` applies once. `input` persists until the next `input`; `jump` is an edge
  on the first frame of its block.
- Only a `capture` command writes a PNG. A scenario with no capture and no perf
  run never creates a Vulkan device.
- A capture frame is a zero-based frame number. A past frame is an error; a
  future frame queues.
- A check uses the `state.json` shape. Operators: `eq`, `ne`, `lt`, `le`, `gt`,
  `ge`. A numeric check takes an optional absolute `tolerance`; it applies to
  `eq` and `ne`. A tolerance on an ordering op or a non-number is an error. Examples: `player.position.y`, `player.stance`, `objects.count`, `settings.window_mode`,
  `settings.resolution`, `settings.sprint_mode`, `settings.type_weight`,
  `menu.open`, `debug.active`, `debug.palette.open`, `debug.placement.armed`,
  `debug.placement.prefab`, `debug.sun.active`, `debug.sun.angular_diameter_deg`,
  `debug.inspector.body`, `debug.inspector.size.x`, `debug.inspector.yaw_deg`,
  `debug.inspector.snap`, and `debug.history.depth`.
- An object check addresses a placed object by id: `objects.7.position.z`,
  `objects.7.rotation.w`, `objects.7.prefab`, `objects.7.body`,
  `objects.7.scale`, and `objects.7.spawn_age`. The id is stable while the object
  exists. `objects.count` is the list length.
- A capture check reads the capture summary. Fields: `capture.count`,
  `capture.worst_mean_delta`, `capture.worst_max_delta`,
  `capture.worst_over_16`, and `capture.worst_over_16_fraction`. A check can read
  `capture.png` to tell whether a result wrote an image. The fraction scales
  with the capture size. Each capture after the first compares its
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
- A top-level `"requires": {"renderer_debug": true}` enables the gated command
  for this scenario without `--debug-renderer`. The gate still rejects a
  scenario that does not declare it.
- A top-level `"size": "1280x720"` pins the extent. `--size` with a declared
  size is an error.
- A top-level `"extends": "base.json"` merges the base object and lets the child
  win; a relative path resolves against the extending file. A `parameters` block
  substitutes `${name}` in any command value. A parameter must be a string,
  number, or boolean. A placeholder is a JSON string, so `["${x}", 0, 0]` puts a
  numeric parameter in an array.
- A check compares with `value` or with `other`:
  `{"cmd":"check","field":"capture.1.stats.mean.y","op":"gt","other":"capture.0.stats.mean.y"}`.
  `capture.N.*`, `capture.first.*`, and `capture.last.*` name one capture.
  `capture.named.<name>.*` names a capture by its `name`; a missing name is a
  check error. A check with `tolerance` compares two numbers within that
  absolute distance.

## Units

Every angle in a scenario, `state.json`, and `report.json` is in degrees, and
every angle key ends in `_deg`. The engine converts to radians at the edge.
Positions, heights, and light ranges are metres. `look` deltas are pixels.
`step` and `perf` counts are frames; `perf.prime` is seconds. Capture regions
and crops are pixels. `turn` and `wheel` are step counts.

## Commands

- `{"cmd": "reset"}`
- `{"cmd": "look", "dx": 220, "dy": 0}`
- `{"cmd": "face", "yaw_deg": 0, "pitch_deg": 0}`
- `{"cmd": "input", "forward": 1, "right": 0, "jump": false}`
- `{"cmd": "step", "frames": 60}`
- `{"cmd": "settle", "until": "converged"}`: wait for the 512-sample cap; the
  reply and `state.json` report `settle.frames` and `settle.converged`.
- `{"cmd": "settle", "frames": 300}`
- `{"cmd": "state"}`
- `{"cmd": "rows"}`
- `{"cmd": "capture", "name": "shot", "frame": 90, "alpha": 1.0}`
- `{"cmd": "camera", "position": [0, 2, 12], "yaw_deg": 0, "pitch_deg": 0}`
- `{"cmd": "camera", "position": [0, 2, 12], "look_at": [0, 1, 0], "fov_deg": 75}`
- `{"cmd": "camera", "clear": true}`
- `{"cmd": "view", "hud": true, "debug": false, "hint": false, "perf": false}`
- `{"cmd": "sun", "azimuth_deg": 52.1, "elevation_deg": 15, "diameter_deg": 0.53}`
- `{"cmd": "sun", "clear": true}`
- `{"cmd": "displays", "set": [{"name": "Solo", "desktop": "1280x720", "modes": ["1280x720"]}]}`
- `{"cmd": "displays", "clear": true}`
- `{"cmd": "rows"}`
- `{"cmd": "scene", "camera": {...}, "sun": {...}, "objects": [...], "settings": {...}, "view": {...}, "displays": [...]}`
- `{"cmd": "repro", "path": "runs/repro/live.json"}`
- `{"cmd": "debug_mode", "active": true}`
- `{"cmd": "editor", "open": true, "select": 4, "pick": true, "height": 0.5}`
- `{"cmd": "editor", "select": 8, "light_color": "cool", "light_intensity": 2.2, "light_range": 12}`
- `{"cmd": "editor", "camera": {"position": [0, 1.7, 14], "yaw_deg": 0, "pitch_deg": -34.3775}}`
- `{"cmd": "editor", "place": {"prefab": "Block", "position": [0, 0.5, 10], "body": "static"}}`
- `{"cmd": "editor", "sun": {"active": true, "position": [0, 40, -30]}}`
- `{"cmd": "editor", "sun": {"place": true}}`
- `{"cmd": "editor", "sun": {"cancel": true}}`
- `{"cmd": "menu", "open": true, "item": "Type weight", "activate": true, "direction": -1}`
- `{"cmd": "menu", "open": true, "set": 900}`
- `{"cmd": "check", "field": "player.position.y", "op": "gt", "value": 0}`
- `{"cmd": "check", "field": "capture.1.stats.mean.y", "op": "gt", "other": "capture.0.stats.mean.y"}`
- `{"cmd": "perf", "frames": 120, "warmup": 60}`
- `{"cmd": "renderer_debug", "jitter": false, "shadow_phase": 12}`
- `{"cmd": "renderer_debug", "light_shadows": false, "synthetic_lights": 8}`
- `{"cmd": "renderer_debug", "sky": false, "ao": false}`
- `{"cmd": "record", "path": "scenarios/walk.json"}`
- `{"cmd": "record"}`
- `{"cmd": "replay", "path": "scenarios/walk.json"}`
- `{"cmd": "quit"}`

`camera` accepts `look_at` instead of `yaw_deg`/`pitch_deg`, and `fov_deg` in
degrees (1..170). Both angle forms together are an error, and so is a `look_at`
equal to the position. `state.camera` reports the effective view and whether an override
is active.

`settle` also takes `{"cmd":"settle","until":"converged"}`. It renders until the
convergence count reaches the 512 cap and reports `settle.frames` and
`settle.converged`. It needs a renderer.

A `scene` command applies one exact scene. Its blocks are `camera`, `sun`,
`objects`, `settings`, `view`, `displays`, and `renderer_debug`, and every block
is optional. A `settings` block may carry any subset of its fields; an omitted
field keeps the live value. A `view` block may carry any subset of its four
flags. A `renderer_debug` block uses the same keys as the command and needs the
same gate. The camera source is `player`, `debug`, or `override`; a player source
carries a `player` block with the feet position, yaw, pitch, stance, velocity,
grounded state, step smoothing, and eye height. An object carries its id,
prefab, body, position, rotation quaternion, colour, and light. The settings
carry the window mode, display index, windowed resolution, input modes, and type
weight. The display list replaces the menu list. `F5` writes one scene, and
`record` starts with one, so a live view replays as a normal scenario. A scene
load closes the settings menu.

`repro` writes the same scene snapshot the `F5` key writes and sets the same
notice. `path` is required and holds at most 160 bytes, so the notice can name
the file. A write failure returns `ok: false` and leaves the failure notice set.
The reply's `written` field carries the absolute path.

`sun clear` restores the default direction and angular diameter.

`displays` replaces the harness display list for the rest of the run. A display
with no `desktop` and no modes gives the menu a zero-mode display, which blocks
the Resolution row. `clear` restores the fallback list.

`rows` returns the HUD and menu rows that the renderer would draw: `kind`,
`label`, `value`, `blocked`, `ratio`, and `ticks`.

A past capture frame is an error. A future capture frame queues. Unknown keys,
wrong types, and out-of-range values are per-command errors; the session stays
usable. A `step` or `settle` while the menu is open is an error, because the
game pauses. A settle renders every frame and writes no screenshot. An open menu renders even when the `view` HUD flag is off. Opening the menu closes the object palette and cancels placement and sun placement.
`item` selects a row by name: Window mode, Display, Resolution, Type weight,
Sprint mode, Crouch mode, Prone mode, or Resume. `item`, `activate`, and `set`
need an open menu. `direction` is `-1` or `1` (default `1`) and needs
`activate`. `set` is a Type weight in 100..900.

A capture names its target and format. A capture name is unique in one run; a
second capture with the same name is an error. See **Capture targets**. A region
limits the statistics to a rectangle, a profile measures an edge or a gradient,
a crop writes a scaled PNG, and a histogram counts the region's channels.

`displays` replaces the menu's display list. Each entry has a name, an optional
desktop size, and an optional mode list. A display with no modes blocks the
Resolution row, so the blocked menu state is scriptable. `clear` restores the
fallback list.

`rows` replies with the HUD and menu rows: kind, label, value, blocked, ratio,
and ticks. A check reads them as `rows.hud.N.*` and `rows.menu.N.*`.

## Parameter sweep

A scenario declares its knobs in `parameters` and uses `${name}`. `--param`
overrides one value; a comma list runs the scenario once per value:

```sh
./bin/harbagsa-agent run scenarios/lamp-threshold.json \
  --param lamp_x=20,19.999,19.99,19.9 --out runs/lamp-threshold
```

Repeat `--param` for every parameter. The runner takes the cartesian product in
flag order and the last parameter changes fastest. Values cannot hold a comma,
and a sweep holds at most 256 runs. With one value the run is a plain run into
the usual directory; with more than one, each run gets a directory named by its
values and the parent gets `sweep.json`.

`sweep.json` holds `ok`, `exit_code`, `scenario`, and one entry per combination:
`parameters`, `run_dir`, `report`, `state`, `digest`, `exit_code`, `ok`, and
`error`. The process exit code is the highest of the runs, so every combination
still runs after a check failure. A scenario parse error for one value is
recorded for that value and the sweep continues.

An override must match a `${name}` used outside the `parameters` block. The
declared default sets the type: a string stays text, a boolean must parse as
`true` or `false`, and a number accepts both `20` and `19.999`. A parameter
the flag does not name keeps its declared value.

The effective parameters are in `report.scenario.parameters`, sorted by name,
and they join the scenario hash, so two sweep runs of one file are distinct
scenarios. `scenarios/lamp-threshold.json` is the worked example; it measures
the wall gradient at each lamp position and writes no check.

## Suites

`suites/<name>.json` is a manifest of scenario entries. `harbagsa-agent suite
<name|path>` runs them in order and writes `suite.json` beside one run
directory per entry.

```json
{
  "version": 1,
  "name": "renderer",
  "description": "Renderer state and temporal stability",
  "entries": [
    "renderer-state",
    {"scenario": "taa-motion", "label": "taa-motion-800", "size": "800x600"},
    {"scenario": "smoke", "no_render": true}
  ]
}
```

An entry is a scenario name or an object. The object keys are `scenario`,
`label`, `size`, `params`, and `no_render`. A name without a path resolves
under `scenarios/`. `params` holds one scalar per name; a comma list is not
allowed because a suite entry is one run. `label` names the run directory and
must use only letters, digits, `-`, and `_`.

A suite never declares `requires` itself. It parses each scenario after
`extends` and reads the merged `requires`, and `run_scenario` enables the gate.
The suite exit code is the highest entry code, so one failure does not hide the
other rows. `--fail-fast` stops at the first failure. `--list` parses every
entry and prints its size, gate, and render mode without running it. Each entry
prints `suite: <label>` before it runs and its wall-clock time in `suite.json`;
`--quiet` suppresses the progress lines. `--timeout SECONDS` applies one budget
to each entry. Suite names and scenario names resolve from the repository root,
so the command works from any directory.

`harbagsa-agent suite offscreen` is the validation target. `make
validate-offscreen` builds the validation agent and runs
`suites/offscreen.json`; `make ui` runs `suites/ui.json`; `make suite
SUITE=renderer` uses the normal agent. Positional selectors replace the
manifest entries, so `make validate-offscreen SCENARIO=renderer-debug` still
runs one scenario.

`harbagsa-agent schema` prints the command fields, units, scenario and suite
keys, capture targets and formats, check fields, and the state field tree as
JSON. `schema capture --text` prints one command; `schema --text` prints the
command table. `run`, `session`, `diff`, `compare`, `suite`, and `ab` accept
`-h`/`--help`.

## Editor

The `editor` command drives the debug placement tool, the lamp light, and the sun
placement. It needs debug mode; send `{"cmd": "debug_mode", "active": true}`
first. Every field is optional, and one command may combine fields. They apply
in this order: `camera`, `open`, `select`, `palette_step`, `palette_number`,
`select_object`, `body`, `flip_body`, `height`, `yaw_deg`, `snap`,
`snap_toggle`, `light_color`, `light_intensity`, `light_range`, `pick`,
`cancel`, `place`, `move`, `rotate_deg`, `turn`, `wheel`, `primary`,
`secondary`, `drag_move`, `drag_release`, `delete`, `duplicate`, `undo`,
`redo`, `sun`.

The keyboard and the harness both build `game.Edit_Action` values and call
`game.edit_apply`; the rules live there once. A rejected edit returns `ok: false`
and a stable reason, such as no selection, not a lamp, the scene is full, the
menu is open, or the palette, placement, or sun mode owns the input. `cancel`
with no active mode is a no-op.

| Field | Meaning |
| --- | --- |
| `open` | open or close the object palette |
| `select` | zero-based prefab index; a new prefab restores its default body |
| `body` | `static` or `dynamic`; the next placement while the palette or the placement tool owns the editor, the selected object otherwise |
| `flip_body` | the `M` key: flip the same target as `body` |
| `palette_step` | arrow-key selection step; wraps around the catalog |
| `palette_number` | 1-based catalog key in [1, 9] |
| `snap_toggle` | the `G` key: flip the 0.25 m grid snap |
| `turn` | relative yaw steps, 15 or 45 degrees; the armed tool or the selection |
| `wheel` | relative height steps, 0.25 or 1 metre; the armed tool or the selection |
| `large` | Shift step for `turn` and `wheel` |
| `primary` | left mouse press: select and start a drag, place the ghost, or commit the sun |
| `secondary` | right mouse press: cancel the active mode or clear the selection |
| `drag_move` | `[dx, dy]` look delta applied to the current object drag |
| `drag_release` | left mouse release: end the object drag |
| `pick` | arm the selected prefab, close the palette, cast the placement ray |
| `height` | offset above the surface in metres; clamped at 0 |
| `yaw_deg` | rotation in degrees |
| `snap` | round the X/Z bottom anchor to a 0.25 m grid |
| `light_color` | `warm`, `cool`, `red`, `green`, or `blue` |
| `light_intensity` | intensity in [0.2, 4.0], rounded to a tenth |
| `light_range` | range in [2, 20] metres, rounded to a whole metre |
| `cancel` | clear the armed tool without placing |
| `camera` | `{"position", "look_at"}` or `{"position", "yaw_deg", "pitch_deg"}` for the debug camera; angles are degrees |
| `place` | `{"prefab", "position", "yaw_deg", "body"}` creates at an exact transform |
| `select_object` | placed object id; 0 clears the selection |
| `move` | `[x, y, z]` centre for the selected object; y clamps above the floor |
| `rotate_deg` | degrees to turn the selected object; negative turns the other way |
| `delete` | remove the selected object |
| `duplicate` | copy the selected object one half extent along +X, select the copy, and play the pop; a no-op at the cap |
| `undo` | restore the previous object-list snapshot |
| `redo` | restore the next object-list snapshot |
| `sun` | `{"active", "position", "place", "cancel"}` drives sun placement; `position` is projected onto the 50 m sky dome and clamped above the floor |

`select` follows the catalog order: Crate, Small crate, Wide crate, Block,
Platform, Ramp, Pillar, Wall, Lamp, Light panel, Beacon. A pick casts a 100 m ray
from the debug camera. A hit puts the object's AABB bottom on the hit point; a
miss puts it 3 m ahead of the camera. The state reports the ghost centre as
`debug.placement.position`.

The three light prefabs carry a lamp light. The light fields apply to the next
lamp placement while the palette is open or the placement tool is armed, and to
the selected lamp otherwise. A non-lamp target is an error. `debug.placement.light`
reports the next placement light, `debug.inspector.light` the selected lamp, and
`debug.lights` the active and total lamp counts. The state and the HUD read
`debug.placement.light` from `game.next_placement_light`.

`place` requires `prefab` and `position`. Its `yaw_deg` defaults to 0 and its
`body` to the prefab default. It bypasses the ray and leaves the armed tool unchanged.
A lamp uses the tuned next-placement light when it is the palette-selected
prefab, and its catalog default otherwise. At the 128-object cap it returns an
error and creates nothing.

`select_object` changes only the selection, so it does not add a history entry.
`move`, `rotate`, `delete`, `duplicate`, and `body` on the selection each add one
entry. The 64-entry history covers place, delete, duplicate, move, wheel height,
rotate, and body conversion. Undo and redo restore the object list, keep the
object ids, and skip the spawn pop. A new edit clears redo. Camera, sun, palette,
and placement state are not undoable.

The `sun` fields apply in this order: `active`, `position`, `place`, `cancel`.
`active: true` enters the mode and saves the current sun for a cancel; it also
closes the palette and cancels the object placement. `position` sets the sun
directly, so a capture is deterministic; the light direction follows the new
position. `place` commits and leaves the mode. `cancel` restores the sun from
before the mode. `active: false` leaves the mode and keeps the current sun.

The state carries `debug.palette` (`open`, `selected`, `body`),
`debug.placement` (`armed`, `prefab`, `position`, `height`, `yaw_deg`, `snap`,
`light`), `debug.sun` (`active`, `position`, `azimuth_deg`, `elevation_deg`,
`angular_diameter_deg`), `debug.inspector` (`prefab`, `body`, `size`,
`position`, `yaw_deg`, `snap`, `light`), `debug.lights` (`active`, `lamps`),
and `debug.history` (`depth`, `redo`). Every angle field ends in `_deg` and is
in degrees. A light value carries `active`, `color`, `intensity`, and `range`.
`debug.selection` is `none` or `object`, and `debug.selected_id` is the selected
placed object's id or 0. `debug.inspector` reports zeroes and empty strings when
nothing is selected. `debug.history.depth` is the undo count, from 0 to 64, and
`debug.history.redo` is the redo count. `debug.placement.height` is metres,
`debug.placement.yaw_deg` is degrees, and `debug.placement.position` is the ghost
centre (zero when not armed). The ghost is drawn as debug lines while armed: the
oriented box, the footprint on the surface, and the height guide.

The sun gizmo is debug lines too: a ring, a cross, and a dashed line to the
arena centre. It is bright amber while the placement mode is active and dimmer
amber while idle. The palette, the object placement, and the sun placement are
mutually exclusive. The settings menu cancels the sun placement when it opens.

`scenarios/editor-ghost.json` captures the armed ghost on the floor and raised,
then places a block at an exact transform. `scenarios/debug-palette.json` opens
the palette, captures the Platform preview, selects the Ramp, and captures its
pitched preview. Run it with `--size 800x600` to check the dock fits the smallest
supported window. `scenarios/editor-sun.json` captures the default light, the
sun gizmo on the sky dome, and the committed lighting.
`scenarios/editor-object.json` selects an object, moves, rotates, and converts
it, duplicates it, then captures the inspector and the undo and redo restores.
`scenarios/editor-input.json` drives the pointer, wheel, relative turn, palette
step, number key, snap toggle, and right-click clear through the same actions.
`scenarios/editor-lamps.json` captures the three lamp previews, places a warm
lamp, a cool panel, a red beacon, and a pillar, then checks the light values and
the active and lamp counts. It captures the lit scene, the point-light shadow,
the selected lamp edit, and its undo.

The harness has no real cursor. Frame tests cover the card hit test, platform
tests cover the normalized pointer math and the key map, and a manual run covers
the cursor capture handoff.

## Spawn pop

A placement or a duplicate plays a 0.28 s spawn pop. The visual scale follows
`easeOutBack` with a back factor of 1.5: it peaks at about 1.08 and has a floor
of 0.01. The scale multiplies the box half extents and moves the centre so the
AABB bottom stays fixed. The physics body keeps its full size.

Initial objects and undo or redo restores are settled: scale 1 and spawn age 0.
`objects.<id>.scale` and `objects.<id>.spawn_age` report the animation.
`objects.<id>.position` and `objects.<id>.rotation` stay the physical transform,
so the state digest covers the transform and not the animation phase.

The visual box is what the renderer and the selection outline use. The TLAS and
the sun shadows therefore follow the pop. A pop keeps the box count, so the
renderer does not reset TAA history for it; a placement or a deletion still
changes the box count and resets history with `scene_change`.

`scenarios/debug-pop.json` enters debug mode, renders the arena once, places a
block with the `editor` command, and captures the start, overshoot, and settled
frames. It checks the scale, the spawn age, the physical position, and that the
pop does not reset TAA. `simulation_apply_snapshot` is the settled restore path:
it recreates the body, keeps the object id, and clears the selection when the
selected object is gone.

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
| `scenarios/editor-ghost.json` | the armed placement HUD, the ghost, and an exact place |
| `scenarios/editor-sun.json` | the default light, the sun gizmo, and the committed sun |
| `scenarios/editor-object.json` | the inspector, the object edit flow, and the undo and redo restores |
| `scenarios/editor-lamps.json` | the three lamp previews, the lit scene, a point-light shadow, and a lamp edit |
| `scenarios/debug-palette.json` | the open palette, its selection, and the cube and ramp previews |
| `scenarios/debug-pop.json` | the spawn pop at the start, overshoot, and settled frames |
| `scenarios/ui.json` | the settings panel with a numeric value selected, then an action row |
| `scenarios/settings-menu.json` | the settings round trip and the menu digest |
| `scenarios/blocked-note.json` | the blocked-change note and its clear on a successful change |
| `scenarios/repro-notice.json` | the scene snapshot notice and its clear after two seconds |
| `scenarios/window-settings.json` | the window rows after a display change |
| `scenarios/type-weight.json` | the Type weight row at 400, 900, and 100 |

Run the scenarios and read the frames in `runs/<scenario-stem>/frames/`. Do not
commit the PNGs; a run directory is the evidence.

```sh
./bin/harbagsa-agent run scenarios/hud.json --out runs/ui/hud
./bin/harbagsa-agent run scenarios/hud-debug.json --out runs/ui/hud-debug
./bin/harbagsa-agent run scenarios/settings-menu.json --out runs/ui/menu
./bin/harbagsa-agent run scenarios/blocked-note.json --out runs/ui/blocked-note
./bin/harbagsa-agent run scenarios/repro-notice.json --out runs/ui/repro-notice
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

## Movement scenarios

Movement scenarios run with `--no-render` and gate the simulation state.

| Scenario | Proves |
| --- | --- |
| `scenarios/step-angle.json` | the step-up climbs the 0.35 m step from a 60 degree approach |
| `scenarios/ramp-headroom.json` | a stand attempt under each ramp stays low instead of growing through the slab |

`ramp-headroom.json` sets a prone player under each ramp, presses jump as the
stand attempt, and checks that the stance stays Prone. The jump is refused
because the slab crosses the standing capsule.
`tests/simulation/headroom.odin` also releases prone and checks that the stance
falls to the tallest one that fits.

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
the scenario. Recording starts with `reset`, one `scene` snapshot of the current
state, and the current `input`. `"actions": true` omits the scene snapshot and
keeps the reset, so only the action sequence matters. Send the actions after the
start command if you want them in the scenario. `replay PATH` resets and runs
the scenario.

The game has no control socket. `F5` writes
`runs/repro/repro-<unix-ms>.json`, logs its absolute path, and shows
`Scene snapshot · <path>` in the top-right for two seconds. A failed write shows
`Scene snapshot failed · <path>` instead. The file is a normal scenario with one
`scene` command, so `bin/harbagsa-agent run runs/repro/repro-....json` is the
whole repro step. A scene with renderer debug overrides carries its own
`"requires": {"renderer_debug": true}`. `--repro-dir DIR` or
`HARBAGSA_REPRO_DIR` moves the directory. The `repro` command writes the same
file and sets the same notice, so a scenario can capture what the player sees.
The key writes a file only; it does not open a command channel.

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

A stats capture accepts `"region": {"x","y","w","h"}` or `"rect": [x,y,w,h]`.
The statistics cover the region. `"histogram": 8` adds per-channel bin counts
for the region or the whole image. `capture.stats.region.*` and
`capture.histogram.*` read them.

A capture with `"crop": {"x","y","w","h","scale"}` writes a nearest-neighbor
scaled PNG. `width` and `height` stay the source extent; `written_width` and
`written_height` name the file. A crop stays out of the analysis window and the
delta baseline, because it covers a rectangle rather than the frame.

A profile capture measures one line or a mean profile:

```json
{"cmd":"capture","name":"edge","format":"profile",
 "profile":{"axis":"y","at":1200,"from":300,"to":520,"channel":"luma"}}
```

`axis` names the direction the profile runs; `at` is the fixed coordinate on the
other axis. `mean: true` averages the whole perpendicular span instead and
ignores `at`. `channel` is `luma`, `x`, `y`, or `z`; values are decoded from
sRGB to linear. `capture.profile.width` is the 10%–90% crossing width over the
span's own minimum and maximum; `low_index`, `high_index`, and `flat` describe
the crossing. `scenarios/edge-profile.json` uses a region, a histogram, a
profile, and a crop on the shadow edge.

Formats:

- `png`: color only. 8-bit RGBA, sRGB. This is the screenshot path.
- `float`: intermediate targets only. Writes `<name>.f32` with
  `width * height * 4` little-endian `f32` values in RGBA order. Depth fills
  `.x` and the other channels are zero. Color values stay in 0..255.
- `raw`: intermediate targets only. Writes `<name>.bin` with the exact texel
  bytes. `target_format` in the report names the Vulkan format.
- `stats`: any target. Writes no file unless the capture adds `"png": true`.
  The report holds per-channel `min`,
  `max`, `mean`, `stddev`, and `gradient`, and for `velocity` the median screen
  motion in texels over covered pixels. `stddev` is the population standard
  deviation over the region. `gradient` is the mean absolute difference between
  each pixel and its left and top neighbours; a region with no neighbour pair
  reports 0.

A stats capture accepts `"region": {"x","y","w","h"}` or `"rect": [x,y,w,h]`.
The statistics cover the region and the report echoes it; a check reads
`capture.stats.region.x` and the other region fields. Add `"histogram": 8` for
per-channel bin counts in `capture.histogram.x`, `.y`, `.z`, and `.w`.

A stats capture with a region also reports `capture.stats.steps`. It
box-filters the luma 9x9 by default, which removes the output dither and the
sample noise, then counts adjacent jumps above half a level and below 8 levels.
A soft shadow gradient reports no steps; a ray-count step leaves a run of them.
Keep the region at least four pixels inside a flat boundary, because the filter
reads that margin. `"steps": {"blur": 9, "min": 0.5, "max": 8}` tunes the kernel
and thresholds; `blur` is an odd kernel size in [1, 31]. The result echoes
`blur`, `min`, and `max_levels`. `scenarios/ramp-shadow.json` and
`scenarios/ramp-shadow-crouch.json` are the worked examples; the second looks
from the crouched view under the ramp, where the steps are widest.

A capture accepts a `profile` block and `"format": "profile"` for an edge
measurement on the color target or an intermediate target. A color profile
decodes sRGB; a float profile reads linear values and reports
`profile.source` as `linear`. A color capture also accepts a `crop` block to
write a scaled PNG. Add `"png": true` to a color `stats` or `profile` capture to
write the image beside the numbers. One capture stays one result, so
`capture.count` and named checks do not change. A sidecar joins the PNG delta
series and the analysis window. A crop and a sidecar cannot be combined.

`{"cmd":"captures","name":"pair","outputs":[...]}` renders one frame and writes
one or more outputs from that frame. Each output carries one capture's `target`,
`format`, `png`, `region`, `profile`, `crop`, `histogram`, and `steps`, plus an
optional `name`; `frame` and `alpha` belong to the group. The outputs share the
frame, so a PNG, history statistics, and a linear profile describe the same
pixels. A group holds at most eight outputs and a name must be unique in the
group and the run. `scenarios/capture-group.json` covers all six output forms.

`png` with an intermediate target, or `float`/`raw` with color, is a scenario
error. Capture deltas compare color PNG captures only; another target does not
move the baseline.

A check reads the last capture in its window: `capture.target`,
`capture.format`, and `capture.stats.min.x`, `capture.stats.max.x`,
`capture.stats.mean.x`, `capture.stats.stddev.x`, `capture.stats.gradient.x`,
`capture.stats.steps.count`, `capture.stats.steps.pairs`,
`capture.stats.steps.max`, `capture.stats.steps.blur`,
`capture.stats.steps.min`, `capture.stats.steps.max_levels`,
`capture.stats.velocity_median_texels`, and the same `.y`, `.z`, `.w` channels.

`scenarios/capture-targets.json` covers a static and a moving velocity capture,
scene color, history, and depth.

## Analysis

A run with captures writes `analysis.json` beside `report.json`, and
`report.json` links it in `analysis`. The pair and pixel analysis uses color PNG captures, including a stats or
profile sidecar; a run with only intermediate captures writes an empty window
and summary. The analysis is on by default. Disable it with `"analysis": false` or
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

`analysis.bands` measures the identical-luma runs down the columns of the last
analyzed frame: `longest_run`, `median_run`, `levels`, `columns`, and the
optional `region`. A gradient that is continuous in 16-bit and bands after the
8-bit resolve shows a long run. Add `"region": {"x","y","w","h"}` to the
analysis object to keep a flat patch or an overlay out of the metric; checks
read `analysis.bands.region.*`. `scenarios/banding.json` gates the sky at
`longest_run < 64`.

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

`analysis.bands` reports the longest and median identical-luma run down the
columns, the number of distinct levels, and the column count. A gradient that is
continuous in the 16-bit scene colour and bands after the 8-bit write shows a
long run. `scenarios/banding.json` gates the sky at 1280x720: the output dither
keeps the longest run below 64 rows, and the median at most 2.

### Measure an edge

`scenarios/edge-profile.json` is the worked example. It puts the camera above a
wall shadow and captures three ways:

```json
{"cmd": "capture", "name": "edge-stats", "format": "stats",
 "region": {"x": 300, "y": 160, "w": 40, "h": 40}, "histogram": 8}
{"cmd": "capture", "name": "edge-profile", "format": "profile",
 "profile": {"axis": "y", "at": 320, "from": 140, "to": 220}}
{"cmd": "capture", "name": "edge-zoom",
 "crop": {"x": 300, "y": 160, "w": 40, "h": 20, "scale": 4}}
```

The checks gate the regional statistics, the histogram bin count, the profile
width, and the written crop size. A check reads `capture.profile.width`,
`capture.profile.low_index`, `capture.profile.high_index`,
`capture.profile.flat`, and `capture.profile.values.N`.

The profile decodes sRGB bytes to linear and measures the 10%-90% crossing width
over the span's own range. `"mean": true` averages the whole perpendicular span
instead of one line, so a full gradient can be read. `channel` is `luma` by
default, or `x`, `y`, or `z`. `low` and `high` are optional fractions.

A crop is independent of the region and the profile. It writes a nearest-neighbour
PNG at `w*scale` by `h*scale`, keeps the source extent in `width`/`height`, and
reports the written size in `written_width`/`written_height`. A cropped capture
does not join the delta or analysis series.

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
`mean_delta`, `over_16`, and `identical`. A stats or profile capture with a
PNG sidecar is paired like a plain PNG capture. A pixel differs when an RGB channel
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

## Cross-run compare

```sh
./bin/harbagsa-agent compare runs/before runs/after
./bin/harbagsa-agent compare runs/before runs/after --out runs/compare/stairs --json
```

`compare` pairs the color PNG captures by name, like `diff`. It writes
`compare.png` and `compare.json` under `runs/compare/<a>-vs-<b>/` by default.
The panel names each run's scenario, revision, dirty flag, extent, capture
count, and run directory; each row names the capture, its extent, and the pixel
delta. A missing pair, a size mismatch, or a decode failure is labeled in the
panel and exits 1.

`--pairs NAME,...` compares only the named captures; a name missing from both
runs becomes a failed pair. `--scale N` allows up to N times upscaling, so a
small capture fills its column. `--delta` adds an `A-B` difference column.

A panel holds six pairs and splits into `compare-2.png`, `compare-3.png`, and
so on. `compare.json` lists every page. The labels use the embedded font stack,
so no ImageMagick or compositor is needed. The command refuses an output path
inside either run's `frames/` directory, because `diff` would read the panel as
a capture.

`diff` reads the same run metadata and prints both scenario paths, revisions,
dirty flags, extents, and capture counts. `diff` stays numeric. Use `compare`
when the image is the evidence.

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
| `light_count` | the point lights the last frame uploaded, at most 8 |
| `atlas_weight` | the type weight the active coverage atlas holds |
| `text_truncated_runs` | text runs cut at the 128-glyph cap |
| `text_font_drops` | HarfBuzz fonts dropped at the 8-font cap |
| `text_truncated_runs` | runs cut at the 128-glyph cap |
| `text_font_drops` | fonts dropped at the 8-font shaper cap |

The state also carries a `camera` object: `position`, `yaw_deg`, `pitch_deg`,
`fov_deg`, `source`, and `overridden`. Every angle is in degrees. It reports
the view the renderer uses. `source` is `player`, `debug`, or `override`;
`overridden` is true whenever that view is not the player. A `camera` command
sets the override; `clear` drops it and restores the player or debug view. The
`sun` object is the debug sun placement: it carries `azimuth_deg`,
`elevation_deg`, and `angular_diameter_deg`. The `settle` object carries the
last wait's `frames` and `converged`. The `rows` object carries the HUD and menu
rows. The `menu` object carries `status` and `blocked` beside `open`, `selected`,
and `item`; the status stays until the next setting change, so a check can read
the note after the frame that drew it. The `notice` object carries `text`, which
is empty when no notice is showing; it stays out of the simulation digest. The
angles describe the sun in the sky, so the default sun reads about 52 degrees of
azimuth and 60 degrees of elevation.
The reset reasons are `none`, `create`, `extent`, `toggle`, `teleport`,
`scene_change`, `debug_override`, `player_reset`, and `scene_reset`.

The nested `debug` object repeats the active override values: `taa`, `jitter`,
`history_weight`, `clamp`, `depth_trust`, `shadow_phase_frozen`,
`shadow_phase`, `light_shadows`, `synthetic_lights`, `sky`, and `ao`.

The `debug.sun` object reports `active`, `position`, `azimuth_deg`,
`elevation_deg`, and `angular_diameter_deg`. Every angle is in degrees, and the
position is the sky-dome point the light comes from.

The render digest is FNV-1a over the target extent, the effective camera, the sun
direction and angular diameter, every box, the box emissive strengths, the point
lights, the jitter, the shadow phase, the applied atlas weight, the sky and AO
flags, and the view flags. It changes when any of those change and stays the
same when they do not. It is separate from the simulation digest: read
`render_digest` for the render inputs and `digest` for the simulation.

`report.json` carries a `setup` block: the target kind (`offscreen`,
`swapchain`, or `none`), the extent, the view flags, the renderer debug gate,
the device name, the frame count in flight, the TAA state, the jitter,
history, and sample caps, and the AO sample count, radius, and strength. Use it
to compare two runs before you compare their pixels.

`scenarios/renderer-state.json` checks the steady state. `scenarios/renderer-reset.json`
checks a teleport reset.

## Renderer debug overrides

`{"cmd": "renderer_debug", ...}` changes renderer inputs without editing
source. It is diagnostic and gated. A build with
`-define:ENABLE_RENDERER_DEBUG=true`, or a run with `--debug-renderer`, accepts
it. Any other build rejects it with a clear error.

| Field | Effect |
| --- | --- |
| `taa` | turn TAA on or off |
| `jitter` | enable or disable the camera jitter |
| `history_weight` | fix the resolve history weight in [0, 1] |
| `clamp` | enable or disable the YCoCg neighborhood clamp |
| `depth_trust` | force the depth test to trust the history |
| `freeze_shadow_phase` | freeze the sun sample phase |
| `shadow_phase` | set a phase in [0, 63] and freeze it |
| `light_shadows` | enable or disable the point-light shadow rays |
| `synthetic_lights` | replace the frame's lights with 0 to 8 test lights |
| `sky` | draw the sky pass and use the sky ambient in the lit pass |
| `ao` | trace the ambient occlusion rays |
| `clear` | reset every override and turn TAA, the sky, and the AO on |

An override starts from the current state. A scenario can put the same fields in
a top-level `renderer_debug` object; it compiles to the command before the commands.

Every change to the override resets the history with reason `debug_override`,
including a new shadow phase and a light change.

`scenarios/renderer-debug.json` sets every override and clears it.
`scenarios/renderer-debug-converge.json` turns jitter off and freezes the phase,
so the image converges. `scenarios/renderer-debug-jitter.json` freezes the phase
and lets jitter cycle, so the analysis can find the period.
`scenarios/lamp-wall-plane.json` aims the debug camera at the wall, arms the
Lamp, and clicks the ghost. A wall gradient check gates the fan of shadows that
appears when the shadow ray counts the wall the light sits on, so no
before/after pair is needed. A crate capture with `light_shadows` on and off
still proves the point light casts.
`scenarios/perf-lamps.json` injects eight synthetic lights, measures shadows on,
then disables the point-light shadows and measures again. It writes one trace per
side.

## Sky and ambient occlusion

The sky is an analytic gradient. It draws after the lit pass and shades only the
background pixels. The lit pass traces eight ambient occlusion rays per fragment
and scales the ambient term by the visible fraction, but only where the sun does
not reach the point. A sunlit fragment keeps the full ambient. Both features are
on by default. Both are debug overrides, so the two terms can be measured apart.
`{"cmd": "renderer_debug", "sky": false}` removes the sky pass and its ambient
contribution; `{"cmd": "renderer_debug", "ao": false}` keeps the sky light but
drops the occlusion term. `clear` turns both back on.

`scenarios/sky-ao.json` captures the arena with both on, both off, and split.
`scenarios/stairs-ao.json` captures the stairs at a 25° sun with the AO on and
off, and checks that the sunlit floor keeps one value while the shaded wall
still darkens. It declares `requires.renderer_debug`.
`scenarios/ramp-shadow.json` looks at the shaded floor below the 20 degree ramp
and gates the visibility band metric. A partial ray count is offset inside its
own step, so the shade
does not show 1/8 or 1/16 contour bands; the full and empty counts stay exact.
`scenarios/ramp-shadow-crouch.json` repeats the gate from the crouched view
under the ramp, where the 1/8 steps are widest; it also needs the 32-bit TAA
history, because a 16-bit history rounds the accumulated update away and keeps
the steps. The render digest covers both flags because they change the image.
The design and the noise budget are in
`docs/adr/0017-sky-ambient-and-ray-traced-ambient-occlusion.md`; the count
dither is in `docs/adr/0024-visibility-count-dither.md`; the history width is
in `docs/adr/0027-32-bit-taa-history.md`.

## Interior room

`scenarios/room-lighting.json` drives the closed room in the arena's +x/+z
corner. The room is static arena geometry, not a placed object. The scenario:

1. captures the outside, the one doorway, the sealed corner, and the ceiling;
2. captures the sealed corner and the ceiling on the depth target and checks
   that the maximum depth is below 1.0, so neither view contains a sky pixel;
3. moves the sun behind the doorway and to the far side, and compares the same
   floor region through the doorway;
4. places a warm lamp with the editor, leaves debug mode so the sun gizmo is not
   drawn, and compares the same interior view with the lamp on and off.

The depth check proves the room is closed. It does not prove the interior is
dark: the ambient term is a normal ramp, not an integral of the visible sky, and
the 1.5 m AO radius never reaches across the room. A room can therefore look
brighter than a path tracer would make it, and the doorway sun patch does not
bounce. Use the scenario to test those limits, not to assume global
illumination.

## Performance

The renderer records a perf sample every frame: the frame interval, five CPU
phases, and six GPU pass times (the TLAS build, the depth prepass, the lit
scene, the sky, the TAA resolve, and the overlay). The game shows it on `F4`. A scenario can show
the same panel with `{"cmd": "view", "perf": true}`.

`{"cmd": "perf", "frames": N, "warmup": M}` runs one priming frame, `M` warmup
frames, and `N` measured frames. Each frame steps the simulation once and draws
once without a capture. `frames` is capped at 600. The reply and `report.json`
carry the interval percentiles, the CPU phase means, and the GPU pass means.
`trace` writes one JSON object per measured frame under the run directory; it is
the file to read when a percentile hides one spike. `scenarios/perf.json` is the
ready example.

- Offscreen runs measure throughput: nothing waits for the display.
- `--present` measures pacing: FIFO bounds the rate and the percentiles show
  missed refreshes.
- `--no-render` measures the CPU only.

What the numbers mean:

- The frame interval is wall clock. A capture outside a perf run has no interval.
- The GPU pass times come from Vulkan timestamps. They belong to the last
  completed frame, two frames behind the recording frame. The depth prepass, the
  lit scene, and the sky are separate passes; the lit pass does not include the
  depth prepass. Both sky timestamps are written even when the sky is off, so
  that pass reads near zero and the set is always complete.
- A device without timestamp support, a failed query pool, or a run without a
  device reports the CPU numbers and leaves the GPU fields empty.
- Perf data never enters `State`, the state digest, or the pixel hash. A perf
  run cannot change a check result.

The design and its alternatives are in
`docs/adr/0008-performance-instrumentation.md`. The current numbers and the
ranked causes are in `docs/evidence/perf-baseline.md`.

`scenarios/perf-arena.json` and `scenarios/perf-backface.json` are the scene
pass probes. The arena view looks down on every static box; the closed room's
roof hides its interior. The backface view covers the screen with surfaces that
receive no direct sun. Run either at the same size on two builds to compare.
The before/after is in `docs/evidence/perf-scene-pass.md`.

`scenarios/perf-crates.json` places 60 objects in a grid with the Crate prefab
and measures them, so the box count is part of the probe.

`scenarios/perf-lamps.json` measures the point-light path. The top-level
`renderer_debug` block injects eight synthetic lights, the first `perf` command
measures them with hard shadows, then the command disables point-light shadows
and the second `perf` measures again. Both traces stay in the run directory:
`trace-shadows-on.jsonl` and `trace-shadows-off.jsonl`. Its `requires.renderer_debug` declaration enables
the gated command, so it needs no flag. The paired result is in
`docs/evidence/perf-lamps.md`.

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
needs a ref with the `editor` command and the Crate prefab; a base without it
exits non-zero, which is the intended failure.

The wrapper `./bin/harbagsa-agent ab --base REF ...` translates `--base` to
`--ref` and passes the rest through. Use it when one command is easier to keep
in a note.

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
- `reset` creates a fresh `Simulation`. Placed objects return to spawn, the
  settings return to their defaults, the menu closes, and the debug palette,
  placement, and sun return to their defaults.
- `look` uses the game sensitivity and pitch clamp. `face` sets yaw and pitch
  directly.
- Capture alpha defaults to 1.0 (post-step), so a capture matches `state` at the
  same frame.
- The digest is FNV-1a over frame, player, the sun position, the placed objects
  (id, prefab, body, and the physical transform), the window and input settings,
  and menu state. Scale and spawn age are animation output, so they stay out of
  the digest. The visual pop box is not digest input. Use the digest in reports
  and regression checks.

## Where the code lives

- `src/harness/`: CLI, scenario compiler, commands, session, runner, socket, PNG.
- `src/harness/capture.odin`: the capture result, target, format, and file write.
- `src/harness/capture_stats.odin`: the capture statistics and pixel hash.
- `src/harness/capture_steps.odin`: the visibility-band step metric.
- `src/harness/capture_command.odin`: the capture target/format parser.
- `src/harness/capture_region.odin`: the region, crop, and histogram.
- `src/harness/capture_profile.odin`: the edge profile and its 10%-90% width.
- `src/harness/analysis_bands.odin`: the identical-run band metric.
- `src/harness/scenario_file.odin`: read one scenario once, parse it per sweep
  value.
- `src/harness/scenario_inherit.odin`: the `extends` merge.
- `src/harness/scenario_parameters.odin`: the `parameters` block and overrides.
- `src/harness/scenario_substitute.odin`: `${name}` substitution.
- `src/harness/sweep.odin`: the `--param` parse, combinations, and labels.
- `src/harness/sweep_run.odin`: the sweep runner and `sweep.json`.
- `src/harness/session_rows.odin`: the HUD and menu row dump.
- `src/harness/session_repro.odin`: the `repro` command, which writes a scene
  snapshot and sets the notice.
- `src/harness/session_displays.odin`: the scripted display list.
- `src/harness/session_draw.odin`: the frame draw and the capture dispatch.
- `src/harness/ab_command.odin`: the `ab` wrapper over `tools/ab.sh`.
- `src/harness/run_backend.odin`: the lazy run backend.
- `src/harness/run_paths.odin`: the tag-aware run directory.
- `src/harness/session_settle.odin`: the convergence wait.
- `src/harness/state_schema.odin`: the reflection walk over `State` that resolves
  check paths. `State` and its `json` tags are the schema.
- `src/harness/cli_override.odin`: the CLI renderer override.
- `src/harness/perf_run.odin`: the perf run and its prime loop.
- `src/harness/perf_report.odin`: the perf report types and fill.
- `src/harness/perf_command.odin`: the perf command parser.
- `src/harness/session_state.odin`: the session's renderer snapshot.
- `src/harness/editor_command.odin`: the `editor` command and its parser.
- `src/harness/editor_camera_command.odin`: the debug camera parser.
- `src/harness/editor_object_command.odin`: the object editing fields.
- `src/harness/editor_light_command.odin`: the light fields.
- `src/harness/state_light.odin`: the object light and light budget state.
- `src/harness/session_editor.odin`: the `editor` command execution.
- `src/harness/session_debug.odin`: the renderer debug gate and overrides.
- `src/harness/renderer_debug_command.odin`: the override parser.
- `src/harness/analysis.odin`: the analysis config, summary, and period.
- `src/harness/analysis_report.odin`: the analysis file.
- `src/harness/analysis_images.odin`: PNG decode and the analysis maps.
- `src/harness/check_capture.odin`: capture checks and the check window.
- `src/harness/check_analysis.odin`: analysis check fields.
- `src/harness/report.odin`: the run report and summary types.
- `src/harness/report_setup.odin`: the run's setup block.
- `src/harness/compare.odin`: the compare CLI, report, and table.
- `src/harness/run_data.odin`: the shared run metadata and capture loader.
- `src/harness/compare_pairs.odin`: the pair filter and builders.
- `src/harness/compare_panel.odin`: the labeled panel layout.
- `src/harness/compare_text.odin`: the CPU label blitter.
- `src/harness/compare_image.odin`: the canvas, border, and scaled blit.
- `src/harness/schema.odin`, `schema_types.odin`, and `schema_paths.odin`: the
  schema command, field reflection, and state-path walk.
- `src/harness/capture_group.odin` and `capture_options.odin`: the capture group
  parser and its option blocks.
- `src/harness/capture_write.odin`: the one PNG writer shared by captures and
  analysis maps.
- `src/harness/compare_cli.odin`: the compare options and help.
- `src/harness/suite.odin`: the suite manifest and entries.
- `src/harness/suite_run.odin`: the suite CLI and report types.
- `src/harness/suite_execute.odin`: the suite runner and list.
- `src/harness/suite_report.odin`: the suite table and JSON.
- `src/harness/suite_paths.odin`: repository-root discovery for suites and
  scenarios.
- `src/frame/scene.odin`: the scene type, the live capture, and the JSON text.
- `src/frame/scene_write.odin`: the scene snapshot file writer that the key and
  the harness share.
- `src/harness/scene_command.odin`: the scene command and its blocks.
- `src/harness/scene_objects.odin`: scene objects, lights, and displays.
- `src/harness/session_scene.odin`: applies a scene to a session.
- `repro.odin`: the `F5` key wrapper over the scene snapshot writer.
- `suites/renderer.json`, `suites/offscreen.json`, and `suites/ui.json`: the
  first manifests.
- `src/digest/digest.odin`: FNV-1a for the state and render digests.
- `src/perf/`: the perf sample, ring, statistics, and text formatting.
- `src/renderer/timing.odin`: the timestamp pools, the pass boundaries, and the
  read.
- `src/renderer/debug.odin`: the debug gate, overrides, and shadow phase.
- `src/renderer/lights.odin`: the point-light type, instance masks, synthetic
  lights, and upload.
- `src/renderer/state.odin`: the renderer report and setup.
- `src/renderer/render_digest.odin`: the render digest.
- `src/renderer/shader_digest.odin`: the embedded SPIR-V digest.
- `src/renderer/sky_draw.odin`: the sky pass and its pipeline.
- `src/renderer/text_shaper.odin`: FreeType and HarfBuzz shaping for the 2D layer.
- `src/renderer/capture.odin`: the target copy and RGBA f32 decode.
- `src/frame/`: shared scene assembly and draw for the game and the harness.
- `src/game/prefabs.odin`: the placed-object body modes, prefab catalog, and
  starting crate layout.
- `src/game/objects.odin`: the placed-object list and the create, remove, move,
  yaw, convert, and reset API.
- `src/game/lights.odin`: the light type, the colour cycle, the intensity and
  range steps, the eight-nearest selection, and the light count.
- `src/game/debug_light_tools.odin`: the keyboard and harness light edit target.
- `src/game/edit_action.odin`: the action dispatcher and `edit_apply`.
- `src/game/edit_types.odin`: the action union, results, and reasons.
- `src/game/edit_palette.odin`, `edit_object.odin`, `edit_pointer.odin`, and
  `edit_placement.odin`: the palette, selection, pointer, and placement rules.
- `src/renderer/pass.odin`: the one pass value and `record_pass`.
- `src/renderer/pass_builders.odin`: the builders for every pass kind.
- `src/renderer/render_input.odin`: the one frame input.
- `src/harness/command_registry.odin`: one row per harness command.
- `src/harness/command_execute.odin`: the row execute procs.
- `src/harness/session_check.odin`: the partial-state check command.
- `src/game/object_records.odin`: the object record and snapshot capture, the
  restore path, and the one placed-object spawn path.
- `src/game/object_history.odin`: the 64-entry heap snapshot stack and its undo
  and redo.
- `src/game/hud_debug.odin`: the debug inspector, placement rows, and their fixed
  number fields.
- `src/game/spawn_pop.odin`: the pop curve, the spawn age and scale, the visual
  box, and the settled restore path.
- `src/game/palette.odin`: the object palette state and the debug palette API.
- `src/game/placement.odin`: the armed placement state, the ray anchor, the
  ghost transform, the height and yaw steps, the snap, and place.
- `src/game/oriented_box.odin`: the oriented box corners and the AABB half
  extents.
- `src/game/debug_draw_ghost.odin`: the ghost outline, footprint, and height
  guide lines.
- `src/game/debug_sun.odin`: the sun placement mode, the sky dome projection,
  the direction from the position, and the default sun.
- `src/game/debug_draw_sun.odin`: the sun ring, cross, and dashed line.
- `src/game/debug_ray.odin`: the shared debug aim ray and its fallback point.
- `src/game/box_body.odin`: the one Box3D box-body creation path for the static
  arena and the placed objects.
- `src/game/menu.odin`: the menu rows, settings text, and control list.
- `src/game/notice.odin`: the transient notice state, its copy, and its hold.
- `src/game/menu_hints.odin`: the control legend for the normal and debug modes.
- `src/game/menu_input.odin`: the pure slider drag state machine.
- `src/game/settings.odin`: the runtime window and input-mode settings.
- `src/display/`: the display list, mode ordering, and window settings types.
- `src/renderer/`: `Target` and `Platform` ports, swapchain/offscreen targets,
  TAA, HUD and menu overlay.
- `src/ui/notice_layout.odin`: the notice box, text column, and baseline.
- `src/renderer/hud_notice.odin`: the notice box, ring, and text draw.
- `src/platform/`: SDL and headless adapters. `display.odin` queries displays and
  applies the window state.
- `tests/harness/` (including `analysis.odin`, `renderer_debug.odin`,
  `renderer_state.odin`, `suite.odin`, `scene.odin`, and `compare.odin`), `tests/frame/`, `tests/display/display.odin`,
  `tests/renderer/` (including `target.odin`, `render_digest.odin`,
  `capture_values.odin`, and `debug.odin`).
- `scenarios/smoke.json`, `scenarios/taa-static.json`,
  `scenarios/taa-motion.json`, `scenarios/settings-menu.json`,
  `scenarios/window-settings.json`, `scenarios/renderer-state.json`,
  `scenarios/renderer-reset.json`, `scenarios/capture-targets.json`,
  `scenarios/renderer-debug.json`, `scenarios/renderer-debug-converge.json`,
  `scenarios/renderer-debug-jitter.json`, `scenarios/capture-free.json`,
  `scenarios/editor-ghost.json`, `scenarios/editor-sun.json`,
  `scenarios/editor-object.json`, `scenarios/editor-lamps.json`,
  `scenarios/debug-pop.json`, `scenarios/type-weight.json`,
  `scenarios/repro-notice.json`, `scenarios/sky-ao.json`,
  `scenarios/stairs-ao.json`, `scenarios/ramp-shadow.json`,
  `scenarios/ramp-shadow-crouch.json`,
  `scenarios/shadow-angle.json`, `scenarios/room-lighting.json`,
  `scenarios/perf-crates.json`, and
  `scenarios/perf-lamps.json`.

## Adding a command

Change:

- `Command_Kind` and its payload in `src/harness/command.odin`.
- One row in `COMMANDS` in `src/harness/command_registry.odin`: name, parse,
  execute, record policy, destroy, and backend policy.
- A parser in `src/harness/command_parsers.odin` or a command file, and an
  `execute_*` in `src/harness/command_execute.odin` or a `session_*.odin`
  helper.
- A scenario block when the command is a setup step: parse it into the same
  command and append it before the commands. `renderer_debug` is the example.
- README and, for a new domain word, `GLOSSARY.md`.
- A section in this page when the command needs more than a line of
  explanation. `capture` and `renderer_debug` are the examples.
- A row test in `tests/harness/registry.odin` and a JSONL test.

The parser and dispatcher, the name lookup, the recorder, and the destroy path
read the row. A missing row panics, and the registry test catches it before a
run. Command errors are allocated with `context.allocator`; the dispatcher frees
the row's error after copying it into the reply, so no command sets an ownership
flag.

`backend` is `None`, `Optional`, or `Required`. The batch run and the live
session use the same policy through `Session.backend_provider`; a capture with
rendering disabled is skipped in both. A `Required` command without rendering
fails in its own execute proc, so CPU-only `perf` still works.

## Checks

```sh
tools/make.sh check
tools/make.sh test
tools/make.sh build
```

`make smoke` runs the smoke scenario with the normal agent and needs no
validation layer. `make shot SCENARIO=...` runs one scenario and prints the
capture paths. `make ui` runs `suites/ui.json` into `runs/ui/<entry>`.

`make validate` builds the agent with validation enabled and runs
`scenarios/smoke.json` offscreen, then with `--present` when a display is
available. Both validation targets accept `SCENARIO=...` (one path, one stem,
or a list) and `AGENT_FLAGS=...`; each scenario gets its own output directory.
`make validate-offscreen` is the headless target: it runs
`suites/offscreen.json` offscreen, each entry into its own directory, and exits
with the highest entry code. `SCENARIO=...` replaces the manifest entries:

```sh
make validate-offscreen SCENARIO=renderer-debug AGENT_FLAGS=--debug-renderer
```

`make shot SCENARIO=scenarios/ui.json` builds, runs, and prints the capture
paths. `make ui` runs `suites/ui.json` into `runs/ui/<entry>`. `make suite
SUITE=renderer` runs a suite with the normal agent. `make smoke` is the short
end-to-end gate and needs no validation layers. `make validate-demo` runs the
game with validation enabled.

## Keep the harness current

The harness is part of the product. When you add or change a feature, update the
harness in the same change. Do not leave the automation behind the game.

- New edit intent: add one variant to `game.Edit_Action`, one case in
  `edit_apply`, the keyboard adapter, the `editor` parser, a harness test, and
  this page. Do not add a second rule outside `edit_apply`.

- New simulation input: add it to `game.Input_Snapshot`, the `input` command,
  and `tests/harness`.
- New state field: add it to the `State` struct with its `json` tag and fill it
  in `state_build_sections`. The JSON, the check resolver, and the digest read
  the same field. Add `digest:"-"` when it must not enter the simulation digest.
  Add the section to `check_sections` when it is a new namespace.
- New setting or menu row: add it to `Settings` and `DEFAULT_SETTINGS`, then
  `Menu_Item`, `MENU_ITEM_COUNT`, `MENU_ITEM_NAMES`, `menu_view`, and
  `menu_change_setting`. Add it to `Settings_State` or `Menu_State`, the digest,
  and the docs.
- New window setting: add it to `display.Window_Settings` and apply it in
  `platform.apply_window_state`.
- New view toggle: add it to the `view` command, `frame.Options`, the README, and
  this page.
- New CPU phase or GPU pass: add it to the `perf` enums, `perf.PASS_ORDER`, a
  builder in `pass_builders.odin`, the formatters, the pass-order test, and this
  page. The recorder owns begin, end, and viewport.
- New perf field: add it to the perf report struct, the reply, the run report,
  the trace, and this page.
- New command: follow **Adding a command**, add the registry row test, a JSONL
  test, and a scenario example when it changes a normal workflow.
- New capture target or format: add it to `Capture_Target` or `Capture_Format`,
  the name/parse and extension helpers, `target_image`, `record_capture_copy`,
  `read_capture_target`, and `capture_values`. Add it to the capture parser,
  the README, this page, and a scenario. An unread target is not a tool.
- New analysis field: add it to the `Analysis_*` types, `analysis_field`, the
  analysis report, the docs, and a unit test. `analysis_bands.odin` owns the
  flat-run metric.
- New capture block: add it to `Capture_Command`, `Capture_Request`,
  `Pending_Capture`, the backend, `capture_field`, the docs, and a synthetic
  image test. A block that writes no file must still be readable by a check. A check must read the same value
  the file records.
- New render input: add the field to `Render_Input`, one row to
  `RENDER_DIGEST_FIELDS` (hashed, or an explicit exclusion with the reason), the
  recorder fill, and the reflection test. The uniform reads the same input.
- New renderer report field: add the field and tag to `Renderer_Report` or
  `Debug_Report`. The State reflection walk covers the JSON and check paths;
  there is no separate report table.
- New renderer debug override: add it to `Renderer_Debug`, `set_renderer_debug`,
  the resolve push constants and shader, `renderer_debug_fields`, the renderer
  state, the docs, and the gate test. Do not make it reachable without the
  gate.
- New point light input: add it to `Light`, the light buffer upload, the scene
  shader loop, `Render_Input`, and its digest row. Add a test to
  `tests/renderer/lights.odin`.
- New scenario key or run option: add it to `scenario_parse` and its allowed
  key set, the CLI parser, the README, this page, and a parser test. A new
  top-level key also joins `scenario_build` and the inheritance merge.
- New state object: one field in `State` with a `json` tag. The reflection walk
  covers it, and `tests/harness/schema.odin` fails when a leaf does not resolve.
- New capture or analysis namespace: add it to `check_field`; the state
  namespaces come from the `State` struct.
- Render state is not simulation state: render fields do not go into
  `state_digest`. Put them in the render digest and `Renderer_State` instead.
- New renderer pass or target: keep it behind `Target` or `Render_Input`. Add a
  `Pass` builder, a barrier proc on that pass, a pass-order test, and an
  offscreen test when the pass must match the game.
- New screenshot or evidence path: update the README and this page.
- New prefab: add it to `Prefab_Id` and `PREFABS` in `src/game/prefabs.odin`,
  including its `short_name` for the palette card, and its `light` defaults when
  it is a lamp. The renderer, the game API, and the harness read the catalog
  generically.
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
