# Agent harness

`bin/harbagsa-agent` drives the simulation, runs checks, and writes exact
screenshots. It needs no window, compositor, cursor capture, or `grim`.

The user-facing command reference is `README.md` under **Agent harness**. This
page is the short operational guide for agents.

## Quick start

Run `./bin/harbagsa-agent schema` first. It prints every scenario command and
its fields, the capture targets and formats, the check operators and paths, and
the state tree as JSON. `schema capture --text` prints one command alone. This
page explains how to use them.

Five recipes. Each writes a run directory; read `report.json` for the result.
For a visual bug, start with `make shot`; it builds, runs, and prints the capture
paths. `make quick` runs the short suite, and `make test-simulation` is the
narrow simulation gate. `run -` reads a scenario from standard input, and
`--tag before` keeps a repeat beside the first run:

```sh
printf '%s\n' '{"cmd":"step","frames":2}' |
  ./bin/harbagsa-agent run - --tag probe --out runs/probe
```

1. Capture the HUD:

   ```sh
   make shot SCENARIO=hud OUT=runs/ui/hud
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

Read `runs/smoke/report.json`. Use the absolute paths in `captures`. Exit
code 0 means every check passed.

Use `tools/make.sh` when another agent may build in the same checkout. It
serializes Make with `flock`.

## Surface map

| Task | Read |
| --- | --- |
| drive the simulation | **Scenario format** and **Commands** |
| place or remove one object without debug mode | **Place and remove** |
| drive the object palette, placement, object edits, and history | **Editor** |
| capture the final image | **Capture targets** (`color` + `png`) |
| read velocity, history, depth, or scene color | **Capture targets** |
| read numeric image statistics | **Capture targets** (`stats`) |
| read renderer state, the debug vertex counts, or the render digest | **Renderer state** |
| change a renderer input for a diagnosis | **Renderer debug overrides** |
| inspect the static arena boxes | `harbagsa-agent boxes` or **Interior room** |
| read the probe layout and its gaps | `harbagsa-agent probes` or **Probe map** |
| read every check gate and margin | `harbagsa-agent checks runs/<stem>` |
| run a scenario on two builds and write a panel | **Visual A/B** |
| check the sky and the direct-light occlusion | **Sky and ambient occlusion** |
| compare the probe field with a path-traced reference | **Path-traced reference** |
| test lighting inside the closed room | **Interior room** |
| measure image stability or the period | **Analysis** |
| compare two builds or revisions | **Cross-run diff** and **Cross-run compare** |
| discover command fields and check paths | `harbagsa-agent schema` |
| script the display list | **Commands** (`displays`) |
| dump the HUD and menu rows | **Commands** (`rows`) |
| resolve one state field | **Live session** (`get`) |
| measure an edge or a gradient | **Capture targets** and **Analysis** |
| compare two builds | **Performance** and `ab` |
| measure frame time | **Performance** |
| prove a capture-free sequence is deterministic | **Screenshots** and `scenarios/capture-free.json` |
| reproduce a live view | **Live session** and `docs/adr/0025` |
| understand a design choice | `docs/adr/0008` to `docs/adr/0035` |

## What one run writes

`runs/<scenario-stem>/`

- `report.json`: `ok`, `exit_code`, `scenario` (`path`, `hash`, and the
  effective `parameters`), `run_dir`, `frame`, `state`, `setup`, `captures`,
  `checks`, `failures`, `digest`, `error`, `perf` (a list of named reports) when
  perf ran, `trace` when the run wrote a perf trace, and `analysis` when the run
  wrote an analysis report. A `captures` entry carries `name`, `note`, `target`,
  `format`, and `png`, plus `path` when it wrote a file, the `render_digest`,
  and the `renderer` report of the frame that wrote it. `scenario.note` echoes
  the scenario-level note.
- `analysis.json`: the per-run image analysis. See **Analysis**.
- `frames/analysis-diff.png` and `frames/analysis-variance.png`: the optional
  analysis maps.
- `trace.jsonl`: one JSON object per measured frame, when the perf command asks
  for a trace. A run holds one trace.
- `state.json`: the final state alone. It holds the player, camera, placed
  objects, window and input settings, the debug mode, menu, rows, settle, frame,
  renderer, render digest, and simulation digest. Each object carries `id`,
  `name`, `prefab`, `body`, `position`, `rotation`, `scale`, `spawn_age`, and
  `light` (`active`, `color`, `intensity`, `range`). `static_boxes` carries the
  immutable arena geometry: `center`, `half_extents`, `color`, `rotation`,
  `emissive`, and `visual_only`. The debug mode carries the palette,
  the placement tool, the inspector, the light budget, and the history.
- `frames/<name>.png`, `.f32`, or `.bin`: captures. A color capture is a PNG;
  `float` and `raw` write the intermediate target.
- `<name>-reference.json`, `<name>-reference.csv`, and
  `frames/<name>-reference.png`: one path-traced comparison per `reference`
  command. `report.json.references` carries the same numbers.
- Each color PNG capture carries `delta_mean`, `delta_max`, and `delta_over_16`
  against the previous capture. The first capture has zeros.
- `run.log`: log lines from the renderer, the session, and the runner.

Standard output is one JSON summary. Standard error holds logs. `--summary`
writes the check table and every capture to standard error; `--verbose` adds
the setup and perf reports. The summary counts blocking misses in
`checks_failed` and advisory misses in `checks_advisory`, so a run can exit 0
with an advisory miss.

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
  `eq` and `ne`. A tolerance on an ordering op or a non-number is an error.
  `"advisory": true` records a miss without failing the run. Examples: `player.position.y`, `player.stance`, `objects.count`, `settings.window_mode`,
  `settings.resolution`, `settings.sprint_mode`, `settings.type_weight`,
  `menu.open`, `debug.active`, `debug.palette.open`, `debug.placement.armed`,
  `debug.placement.prefab`, `debug.inspector.body`, `debug.inspector.size.x`,
  `debug.inspector.yaw_deg`,
  `debug.inspector.snap`, and `debug.history.depth`.
- An object check addresses a placed object by id or name: `objects.7.position.z`
  or `objects.room-a-lamp.position.z`. The fields are `name`, `prefab`, `body`,
  `position`, `rotation`, `scale`, and `spawn_age`. The id and the name are
  stable while the object exists. `objects.count` is the list length.
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
- A top-level `"note"` is echoed into `report.scenario.note`; a capture `note`
  is echoed into `captures[].note`. Use them to say why a run or a frame exists.
- A `shot` command is a scenario-only shorthand. It expands to an optional
  `camera`, a `settle`, and a `capture`, so a view is shorter. The expanded
  commands still run verbatim.
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
- `{"cmd": "capture", "name": "shot", "frame": 90, "alpha": 1.0, "note": "why"}`
- `{"cmd": "shot", "name": "lane", "camera": {...}, "settle": 40, "format": "stats"}`
- `{"cmd": "camera", "position": [0, 2, 12], "yaw_deg": 0, "pitch_deg": 0}`
- `{"cmd": "camera", "position": [0, 2, 12], "look_at": [0, 1, 0], "fov_deg": 75}`
- `{"cmd": "camera", "clear": true}`
- `{"cmd": "view", "hud": true, "debug": false, "hint": false, "perf": false}`
- `{"cmd": "displays", "set": [{"name": "Solo", "desktop": "1280x720", "modes": ["1280x720"]}]}`
- `{"cmd": "displays", "clear": true}`
- `{"cmd": "rows"}`
- `{"cmd": "scene", "camera": {...}, "objects": [...], "probe_volumes": [...], "settings": {...}, "view": {...}, "displays": [...]}`
- `{"cmd": "place", "prefab": "Lamp", "position": [13.5, 2.75, 10.5], "name": "key-lamp"}`
- `{"cmd": "remove", "name": "key-lamp"}`
- `{"cmd": "repro", "path": "runs/repro/live.json"}`
- `{"cmd": "debug_mode", "active": true}`
- `{"cmd": "editor", "open": true, "select": 4, "pick": true, "height": 0.5}`
- `{"cmd": "editor", "select": 8, "light_color": "cool", "light_intensity": 2.2, "light_range": 12}`
- `{"cmd": "editor", "camera": {"position": [0, 1.7, 14], "yaw_deg": 0, "pitch_deg": -34.3775}}`
- `{"cmd": "editor", "place": {"prefab": "Block", "position": [0, 0.5, 10], "body": "static"}}`
- `{"cmd": "menu", "open": true, "item": "Type weight", "activate": true, "direction": -1}`
- `{"cmd": "menu", "open": true, "set": 900}`
- `{"cmd": "check", "field": "player.position.y", "op": "gt", "value": 0}`
- `{"cmd": "check", "field": "capture.1.stats.mean.y", "op": "gt", "other": "capture.0.stats.mean.y"}`
- `{"cmd": "perf", "frames": 120, "warmup": 60}`
- `{"cmd": "renderer_debug", "jitter": false, "shadow_phase": 12}`
- `{"cmd": "renderer_debug", "light_shadows": false, "synthetic_lights": 8}`
- `{"cmd": "renderer_debug", "sky": false, "ao": false}`
- `{"cmd": "renderer_debug", "ao_radius": 2.0, "ao_strength": 0.25, "clip_height": 2.0}`
- `{"cmd": "reference", "name": "chamber", "gi": "chamber-gi", "direct": "chamber-direct", "samples": 48, "bounces": 3, "stride": 16}`
- `{"cmd": "record", "path": "runs/walk.json"}`
- `{"cmd": "record"}`
- `{"cmd": "replay", "path": "runs/walk.json"}`
- `{"cmd": "quit"}`

`camera` accepts `look_at` instead of `yaw_deg`/`pitch_deg`, and `fov_deg` in
degrees (1..170). Both angle forms together are an error, and so is a `look_at`
equal to the position. `state.camera` reports the effective view and whether an override
is active.

`settle` also takes `{"cmd":"settle","until":"converged"}`. It renders until the
convergence count reaches the 512 cap and reports `settle.frames` and
`settle.converged`. It needs a renderer.

A `shot` is only valid in a scenario. It expands in order to the `camera`, the
`settle` (a frame count or an object), and one `capture` that takes every other
shot key. `scenarios/shot.json` is the worked example.

A `scene` command applies one exact scene. Its blocks are `camera`, `objects`,
`probe_volumes`, `settings`, `view`, `displays`, and `renderer_debug`, and every
block is optional. A `settings` block may carry any
subset of its fields; an omitted field keeps the live value. A `view` block may
carry any subset of its four flags. A `renderer_debug` block uses the same keys
as the command and needs the same gate. A `probe_volumes` block adds interior
volumes after the room volume and before the arena strips; each entry carries
`name`, `min`, `spacing`, and `counts`. This is the scenario-owned test data:
the production scene keeps no sealed-pair probes. The camera source is `player`,
`debug`, or `override`; a player source
carries a `player` block with the feet position, yaw, pitch, stance, velocity,
grounded state, step smoothing, and eye height. An object carries its id,
optional name, prefab, body, position, rotation quaternion, colour, and light. The settings
carry the window mode, display index, windowed resolution, input modes, and type
weight. The display list replaces the menu list. `F5` writes one scene, and
`record` starts with one, so a live view replays as a normal scenario. A scene
snapshot writes every effective renderer override field and the custom probe
volumes, so a repro restores the exact debug state. A scene load closes the
settings menu.

`repro` writes the same scene snapshot the `F5` key writes and sets the same
notice. `path` is required and holds at most 160 bytes, so the notice can name
the file. A write failure returns `ok: false` and leaves the failure notice set.
The reply's `written` field carries the absolute path.

`displays` replaces the harness display list for the rest of the run. A display
with no `desktop` and no modes gives the menu a zero-mode display, which blocks
the Resolution row. `clear` restores the fallback list.

`rows` returns the HUD and menu rows that the renderer would draw: `kind`,
`label`, `value`, `blocked`, `ratio`, and `ticks`.

A past capture frame is an error. A future capture frame queues. Unknown keys,
wrong types, and out-of-range values are per-command errors; the session stays
usable. A `step` or `settle` while the menu is open is an error, because the
game pauses. A settle renders every frame and writes no screenshot. An open menu renders even when the `view` HUD flag is off. Opening the menu closes the object palette and cancels placement.
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
to each entry. `--only NAME,...` and `--skip NAME,...` select entries by
scenario, scenario stem, or label; repeat either flag to add a filter. A filter
that matches no entry is an error. Suite names and scenario names resolve from
the repository root, so the command works from any directory.

`suites/fast.json` is the short loop: the advisory check, smoke, the interior
room, the stairs AO, and the lamp wall plane. `make quick` builds the agent and runs it.
The full suites stay the final gate.

`harbagsa-agent suite offscreen` is the validation target. `make
validate-offscreen` builds the validation agent and runs
`suites/offscreen.json`; `make ui` runs `suites/ui.json`; `make lighting` runs
`suites/lighting.json`; `make suite SUITE=renderer` uses the normal agent. Positional selectors replace the
manifest entries, so `make validate-offscreen SCENARIO=renderer-debug` still
runs one scenario.

`harbagsa-agent schema` prints the command fields, units, scenario and suite
keys, capture targets and formats, check fields, and the state field tree as
JSON. `schema capture --text` prints one command; `schema --text` prints the
command table. `run`, `session`, `diff`, `compare`, `suite`, and `ab` accept
`-h`/`--help`; `help <command>` prints the same options for a CLI command, or
the field table for a scenario command such as `capture`.

## Place and remove

`place` is the scene-setup path. It creates one object without entering debug
mode, so a lighting scenario draws no ghost or inspector outline.
`prefab` and `position` are required. `yaw_deg`, `body`, and `name` are
optional; `body` defaults to the prefab's body. A name is unique in the scene,
uses at most 31 letters, digits, `-`, or `_`, and is neither all digits nor
`count`. A `light` block is allowed only for a prefab with a light, and its
omitted fields keep the prefab defaults:

```json
{"cmd":"place","prefab":"Lamp","position":[13.5,2.75,10.5],"body":"static",
 "name":"key-lamp","light":{"color":"warm","intensity":1.5,"range":8}}
```

`remove` deletes one object by id or by name:

```json
{"cmd":"remove","name":"key-lamp"}
```

`place` replies with the new id in `placed`. The name survives undo and a scene
snapshot, so a check and a later command can address the object without
depending on placement order. The editor still owns palette selection, armed
placement, undo and redo, and the inspector; use `place` and `remove` when a
scenario needs a fixed scene rather than an edit.

## Editor

The `editor` command drives the debug placement tool and the lamp light. It
needs debug mode; send `{"cmd": "debug_mode", "active": true}` first. Every
field is optional, and one command may combine fields. They apply in this order:
`camera`, `open`, `select`, `palette_step`, `palette_number`, `select_object`,
`body`, `flip_body`, `height`, `yaw_deg`, `snap`, `snap_toggle`,
`light_color`, `light_intensity`, `light_range`, `pick`, `cancel`, `place`,
`move`, `rotate_deg`, `turn`, `wheel`, `primary`, `secondary`, `drag_move`,
`drag_release`, `delete`, `duplicate`, `undo`, `redo`.

The keyboard and the harness both build `game.Edit_Action` values and call
`game.edit_apply`; the rules live there once. A rejected edit returns `ok: false`
and a stable reason, such as no selection, not a lamp, the scene is full, the
menu is open, or the palette or placement mode owns the input. `cancel` with no
active mode is a no-op.

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
| `primary` | left mouse press: select and start a drag or place the ghost |
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
| `select_object` | placed object id or name; 0 clears the selection |
| `move` | `[x, y, z]` centre for the selected object; y clamps above the floor |
| `rotate_deg` | degrees to turn the selected object; negative turns the other way |
| `delete` | remove the selected object |
| `duplicate` | copy the selected object one half extent along +X, select the copy, and play the pop; a no-op at the cap |
| `undo` | restore the previous object-list snapshot |
| `redo` | restore the next object-list snapshot |

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
object ids, and skip the spawn pop. A new edit clears redo. Camera, palette, and
placement state are not undoable.

The state carries `debug.palette` (`open`, `selected`, `body`),
`debug.placement` (`armed`, `prefab`, `position`, `height`, `yaw_deg`, `snap`,
`light`), `debug.inspector` (`prefab`, `body`, `size`, `position`, `yaw_deg`,
`snap`, `light`), `debug.lights` (`active`, `lamps`), and `debug.history`
(`depth`, `redo`). Every angle field ends in `_deg` and is in degrees. A light
value carries `active`, `color`, `intensity`, and `range`. `debug.selection` is
`none` or `object`, and `debug.selected_id` is the selected placed object's id
or 0. `debug.inspector` reports zeroes and empty strings when nothing is
selected. `debug.history.depth` is the undo count, from 0 to 64, and
`debug.history.redo` is the redo count. `debug.placement.height` is metres,
`debug.placement.yaw_deg` is degrees, and `debug.placement.position` is the ghost
centre (zero when not armed). The ghost is drawn as debug lines while armed: the
oriented box, the footprint on the surface, and the height guide.

The palette and the object placement are mutually exclusive. The settings menu
cancels the placement when it opens.

`scenarios/editor-ghost.json` captures the armed ghost on the floor and raised,
then places a block at an exact transform. `scenarios/debug-palette.json` opens
the palette, captures the Platform preview, selects the Ramp, and captures its
pitched preview. Run it with `--size 800x600` to check the dock fits the smallest
supported window. `scenarios/editor-object.json` selects an object, moves,
rotates, and converts it, duplicates it, then captures the inspector and the
undo and redo restores.
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
the point-light shadows therefore follow the pop. A pop keeps the box count, so the
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

`get FIELD` resolves one state, capture, or analysis path and replies with a
typed `value`:

```sh
printf '%s\n' '{"cmd":"get","field":"notice.text"}' '{"cmd":"quit"}' |
  ./bin/harbagsa-agent session --no-render
```

`get objects.count` returns a number, `get renderer.taa` a boolean, and
`get objects.1.prefab` a string. It builds only the state sections the path
needs and never appends a check.

`record PATH` starts recording. A second `record` with no path stops and writes
the scenario. Recording starts with `reset`, one `scene` snapshot of the current
state, and the current `input`. `"actions": true` omits the scene snapshot and
keeps the reset, so only the action sequence matters. Send the actions after the
start command if you want them in the scenario. A capture keeps every option and
its frame is relative to the record start; a capture group keeps its outputs.
`replay PATH` resets and runs the scenario.

The game has no control socket. `F5` writes
`runs/repro/repro-<unix-ms>.json`, logs its absolute path, and shows
`Scene snapshot · <path>` in the top-right for two seconds. A failed write shows
`Scene snapshot failed · <path>` instead. The file is a normal scenario with one
`scene` command, so `bin/harbagsa-agent run runs/repro/repro-....json` is the
whole repro step. A scene with renderer debug overrides carries its own
`"requires": {"renderer_debug": true}`. `--repro-dir DIR` or
`HARBAGSA_REPRO_DIR` moves the directory. The `repro` command writes the same
file and sets the same notice, so a scenario can capture what the player sees.
A relative `repro` path joins the run directory (or the `session --out`
directory), so `"path": "live.json"` lands at `runs/<run>/live.json`; an absolute
path stays absolute. The notice names the path as written, and the reply's
`written` field is the absolute file. The key writes a file only; it does not
open a command channel.

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
The statistics cover the region. Add `"unit": "normalized"` to the object form
to give `x`, `y`, `w`, and `h` as fractions of the frame; the same scenario then
works at 1280x720 and 2560x1440. The report echoes the resolved pixel region.
`"histogram": 8` adds per-channel bin counts for the region or the whole image.
`capture.stats.region.*` and `capture.histogram.*` read them.

Every statistics block is an object named `x`, `y`, `z`, `w`, so
`capture.stats.mean.y` reads green in both JSON and a check. A
`"color_key": {"r","g","b","tolerance"}` block counts the pixels within the
per-channel tolerance of one 0..255 colour. It needs the color target and
`format: "stats"`; the result is `capture.stats.color_key.matches` and
`.fraction`. `scenarios/ddgi-arena.json` uses it to count black pixels in the
room shade.

`"coverage": {"black": 1.0, "lit": 16.0}` adds coverage fractions to the
statistics. `capture.stats.coverage.zero_fraction` is always present and counts
the pixels whose RGB is exactly zero. `black_fraction` counts the pixels with
Rec. 709 luma at or below `black`; `lit_fraction` counts the pixels at or above
`lit`. A threshold is in the target's own values, so a color capture uses 0..255
levels and a `scene_color` float capture uses linear radiance. A threshold you
omit leaves its fraction out of the report. A float capture can gate a missing
indirect term with `zero_fraction` alone.

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
The statistics cover the region and the report echoes the resolved pixels; a
check reads `capture.stats.region.x` and the other region fields. A normalized
region uses the same keys plus `"unit": "normalized"`. Add `"histogram": 8` for
per-channel bin counts in `capture.histogram.x`, `.y`, `.z`, and `.w`.

A stats capture with a region also reports `capture.stats.steps`. It
box-filters the luma 9x9 by default, which removes the output dither and the
sample noise, then counts adjacent jumps above half a level and below 8 levels.
A soft shadow gradient reports no steps; a ray-count step leaves a run of them.
Keep the region at least four pixels inside a flat boundary, because the filter
reads that margin. `"steps": {"blur": 9, "min": 0.5, "max": 8}` tunes the kernel
and thresholds; `blur` is an odd kernel size in [1, 31]. The result echoes
`blur`, `min`, and `max_levels`. `over_cap` counts jumps at or above the cap,
so a geometry edge is visible without polluting the band count. `top` holds the
eight largest counted jumps with `x`, `y`, `axis` (`x` or `y`), and `levels`;
`top.0` is the largest. `scenarios/ramp-shadow.json` and
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
`format`, `png`, `region`, `profile`, `crop`, `histogram`, `steps`,
`color_key`, and `coverage`, plus an optional `name`; `frame` and `alpha` belong to the group. The outputs share the
frame, so a PNG, history statistics, and a linear profile describe the same
pixels. A group holds at most eight outputs and a name must be unique in the
group and the run. `scenarios/capture-group.json` covers all six output forms.

`png` with an intermediate target, or `float`/`raw` with color, is a scenario
error. Capture deltas compare color PNG captures only; another target does not
move the baseline.

A named capture also exposes the renderer report of its own frame:
`capture.named.idle.renderer.debug_vertices.world` is the world line count that
frame drew, not the last frame of the run. The group attaches the report after
the render and before the capture joins the list.

A check reads the last capture in its window: `capture.target`,
`capture.format`, `capture.note`, and `capture.stats.min.x`, `capture.stats.max.x`,
`capture.stats.mean.x`, `capture.stats.stddev.x`, `capture.stats.gradient.x`,
`capture.stats.coverage.zero_fraction`,
`capture.stats.coverage.black`, `capture.stats.coverage.black_fraction`,
`capture.stats.coverage.lit`, `capture.stats.coverage.lit_fraction`,
`capture.stats.steps.count`, `capture.stats.steps.pairs`,
`capture.stats.steps.max`, `capture.stats.steps.over_cap`,
`capture.stats.steps.blur`, `capture.stats.steps.min`,
`capture.stats.steps.max_levels`, `capture.stats.steps.top.N.x`,
`.top.N.y`, `.top.N.axis`, `.top.N.levels`,
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
analysis object to keep a flat patch or an overlay out of the metric, or add
`"unit": "normalized"` to use fractions of the analyzed frame; checks read
`analysis.bands.region.*` as the resolved pixels. `scenarios/banding.json` gates
the sky at `longest_run < 64`.

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
{"cmd": "capture", "name": "edge-stats", "format": "stats", "png": true,
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

### Diagnose banding

A band is a step that survives the 8-bit write. To separate a real visibility
step from a TAA or dither artifact, measure the same view against a phase
average.

1. Replay the view, or run the scenario that shows the band.
2. Settle the normal view for 600 frames, then capture the color PNG and a
   `stats` capture over the band region. The stats capture names the step count.
3. Capture 32 frozen sample phases with TAA off. `scenarios/banding-phase.json`
   is the template: it takes a `phase` parameter, sets
   `{"taa": false, "freeze_shadow_phase": true, "shadow_phase": "<phase>"}`,
   and writes `scene_color` as `float`.
4. Run the 32 phases:

   ```sh
   for phase in $(seq 0 31); do
     ./bin/harbagsa-agent run scenarios/banding-phase.json \
       --param phase=$phase --out runs/banding/phase=$phase
   done
   ```

5. Average the `.f32` files and contrast-stretch the mean. Each file holds
   `width * height * 4` little-endian `f32` values in RGBA order:

   ```sh
   python3 - <<'PY'
   import glob, struct

   paths = sorted(glob.glob("runs/banding/phase=*/frames/phase.f32"))
   frames = []
   for path in paths:
       raw = open(path, "rb").read()
       frames.append(struct.unpack("<%df" % (len(raw) // 4), raw))
   count = len(frames[0])
   mean = [sum(values[i] for values in frames) / len(frames) for i in range(count)]

   # The phase average is linear; stretch the luma to 0..1 to see the band.
   luma = sorted(mean[i] * 0.2126 + mean[i + 1] * 0.7152 + mean[i + 2] * 0.0722
                 for i in range(0, count, 4))
   low, high = luma[len(luma) // 100], luma[-len(luma) // 100]
   stretched = [min(max((v - low) / (high - low), 0.0), 1.0) for v in luma]
   out = bytearray()
   for value in stretched:
       out += struct.pack("<4f", value, value, value, 1.0)
   open("runs/banding/average.f32", "wb").write(out)
   PY
   ```

A band that survives the phase average is a real visibility step. A band that
only appears in one phase is the temporal filter or the output dither; compare
`renderer.taa_enabled`, the history weight, and the step count. The design
background is in `docs/adr/0027-32-bit-taa-history.md`.

## Visual A/B

```sh
./bin/harbagsa-agent ab --visual \
  --ref origin/main --scenario scenarios/editor-lamps.json --out runs/visual-ab
```

`ab --visual` delegates to `tools/visual-ab.sh`. It builds the ref and the
current tree with `make agent`, runs the same scenario into `base/` and `head/`,
then calls `compare --delta` into `compare/`. `--keep` leaves the base worktree.
Omit `--size` when the scenario declares its own size. A side that fails still
leaves a report and any captures, so the panel and exit code show the difference.

`compare --delta` is the labeled before/after/delta panel. Use it directly
when the two runs already exist.

## Cross-run diff

```sh
./bin/harbagsa-agent diff runs/before runs/after
./bin/harbagsa-agent diff runs/before runs/after --max-pixels 0 --json
```

`diff` reads each run's `report.json` and pairs the `captures` entries by
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
| `shadow_phase` | the occlusion sample phase the last frame used |
| `light_count` | the point lights the last frame uploaded |
| `cluster_overflow` | lights a cluster kept beyond its 256-index stride |
| `probe_volume_count` | probe volumes the scene supplied; 6 in the default scene |
| `probe_count` | probes in the live atlas; 2205 in the default scene and 2301 with the sealed pair |
| `probe_frame` | probe-update frames since the atlas was created |
| `probe_energy` | mean linear RGB irradiance across the probe atlas |
| `atlas_weight` | the type weight the active coverage atlas holds |
| `text_truncated_runs` | text runs cut at the 128-glyph cap |
| `text_font_drops` | HarfBuzz fonts dropped at the 8-font cap |
| `debug_vertex_count` | the debug line vertices the last frame prepared, world and editor |
| `debug_vertices.world` | world bounds and contacts from the F1 debug draw |
| `debug_vertices.selection` | the selected object's outline |
| `debug_vertices.placement` | the placement ghost, footprint, and guide |

The state also carries a `camera` object: `position`, `yaw_deg`, `pitch_deg`,
`fov_deg`, `source`, and `overridden`. Every angle is in degrees. It reports
the view the renderer uses. `source` is `player`, `debug`, or `override`;
`overridden` is true whenever that view is not the player. A `camera` command
sets the override; `clear` drops it and restores the player or debug view. The
`settle` object carries the last wait's `frames` and `converged`. The `rows` object carries the HUD and menu
rows. The `menu` object carries `status` and `blocked` beside `open`, `selected`,
and `item`; the status stays until the next setting change, so a check can read
the note after the frame that drew it. The `notice` object carries `text`, which
is empty when no notice is showing; it stays out of the simulation digest.
The reset reasons are `none`, `create`, `extent`, `toggle`, `teleport`,
`scene_change`, `debug_override`, `player_reset`, and `scene_reset`.

The nested `debug` object repeats the active override values: `taa`, `jitter`,
`history_weight`, `clamp`, `depth_trust`, `freeze_shadow_phase`,
`shadow_phase`, `light_shadows`, `synthetic_lights`, `sky`, `gi`, and `ao`.

The render digest is FNV-1a over the target extent, the effective camera, every
box, the box emissive strengths, the point lights, the probe volumes, the
jitter, the shadow phase, the applied atlas weight, the sky, GI, and AO flags,
and the view flags. It changes when any of those change and stays the
same when they do not. It is separate from the simulation digest: read
`render_digest` for the render inputs and `digest` for the simulation.

`report.json` carries a `setup` block: the target kind (`offscreen`,
`swapchain`, or `none`), the extent, the view flags, the renderer debug gate,
the device name, the frame count in flight, the TAA state, the jitter,
history, and sample caps, and the AO sample count, radius, and strength. The
AO values are the build defaults; `state.renderer.debug` reports the effective
override when one is active. Use the setup block to compare two runs before you
compare their pixels.

`scenarios/renderer-state.json` checks the steady state. `scenarios/renderer-reset.json`
checks a teleport reset. A capture copies this report into
`captures[].renderer`, so a later frame cannot change what the capture check
reads.

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
| `freeze_shadow_phase` | freeze the occlusion sample phase |
| `shadow_phase` | set a phase in [0, 63] and freeze it |
| `light_shadows` | enable or disable the point-light shadow rays |
| `synthetic_lights` | replace the frame's lights with a generated test field of any non-negative count |
| `sky` | draw the sky pass; the sky is a background for the camera and a probe miss source |
| `gi` | add the probe indirect term to the lit pass |
| `ao` | trace the occlusion rays; they scale the point lights |
| `ao_radius` | set the occlusion ray length in [0.01, 50] m |
| `ao_strength` | set the occlusion mix in [0, 1] |
| `clip_height` | discard fragments above this world height in [0, 1000] m; a plan view |
| `clear` | reset every override and turn TAA, the sky, GI, and the AO on |
| any field set to `null` | restore that field's default |

An override starts from the current state. Set one field to `null` to restore
that field's default without clearing the others: `{"history_weight": null}`
returns the automatic weight and leaves TAA, sky, GI, AO, and the rest alone. `clear`
still resets every field. A scenario can put the same fields in a top-level
`renderer_debug` object; it compiles to the command before the commands.

Every change to the override resets the history with reason `debug_override`,
including a new shadow phase, a light change, and a reset.

`scenarios/renderer-debug.json` sets every override and clears it.
`scenarios/renderer-debug-converge.json` turns jitter off and freezes the phase,
so the image converges. `scenarios/renderer-debug-jitter.json` freezes the phase
and lets jitter cycle, so the analysis can find the period.
`scenarios/lamp-wall-plane.json` aims the debug camera at the wall, arms the
Lamp, and clicks the ghost. A wall gradient check gates the fan of shadows that
appears when the shadow ray counts the wall the light sits on, so no
before/after pair is needed. A crate capture with `light_shadows` on and off
still proves the point light casts.
`scenarios/perf-lamps.json` injects a synthetic light field, measures shadows on,
then disables the point-light shadows and measures again. It writes one trace per
side.

## Sky and ambient occlusion

The sky is an analytic gradient. It draws after the lit pass and shades only the
background pixels. It is not a direct light: the probe field uses it as the
environment for a ray that escapes the scene.

The lit pass traces eight occlusion rays per fragment and scales the point-light
sum by the visible fraction, out to 1.5 m. The strength is 0.5. A lit corner
darkens; a surface with no light stays black. Both the sky pass and
the occlusion are debug overrides. `ao_radius` and `ao_strength` tune the
contact darkening without a rebuild; the render digest covers both. `{"cmd": "renderer_debug", "sky": false}`
removes the sky pass and leaves the clear colour. `{"cmd": "renderer_debug",
"ao": false}` drops the occlusion and keeps the direct light. `clear` turns
both back on.

`scenarios/sky.json` captures the sky at the zenith and the horizon with the sky
pass on and off. The horizon capture reads the top half of the frame, so the
black walls below the horizon do not enter the mean.
`scenarios/stairs-ao.json` places a lamp above the dive stairs, captures the
stairs with the AO on and off, and checks that the AO darkens the lit floor and
the shade. It declares `requires.renderer_debug`.
`scenarios/ramp-shadow.json` looks at the dark floor below the 20 degree ramp
and gates the visibility band metric. A partial ray count is offset inside its
own step, so a contact band does not show 1/8 or 1/16 contour bands; the full
and empty counts stay exact.
`scenarios/ramp-shadow-crouch.json` repeats the gate from the crouched view
under the ramp; it also needs the 32-bit TAA history, because a 16-bit history
rounds the accumulated update away and keeps the steps.
`scenarios/room-lighting.json` proves the dark base in the room. The chamber
mean stays at the output dither floor before a lamp exists, and a placed lamp is
the only light inside. The render digest covers both flags because they change
the image. The design is in
`docs/adr/0028-direct-light-with-surface-occlusion.md`; the count dither is in
`docs/adr/0024-visibility-count-dither.md`; the history width is in
`docs/adr/0027-32-bit-taa-history.md`.

## Path-traced reference

`{"cmd": "reference"}` compares the probe indirect term with a CPU path tracer.
It reads two `scene_color` float captures of the same view that differ only in
the gather toggle, traces a fixed grid of pixel centres with cosine-weighted
diffuse bounces, and writes the comparison:

```json
{"cmd": "reference", "name": "chamber",
 "gi": "chamber-gi", "direct": "chamber-direct",
 "samples": 48, "bounces": 1, "stride": 16,
 "tolerance": {"ratio_min": 0.8, "ratio_max": 1.25, "error_max": 0.3,
               "colour_max": 0.1, "zero_fraction_max": 0.01}, "advisory": false}
```

Rules:

- The two captures must be `scene_color` float captures with the same extent,
  and they must precede the command. The direct term cancels in their
  difference, so the comparison isolates `albedo * probe_indirect`.
- `renderer_debug` must set `taa`, `jitter`, and `ao` off. The reference has no
  temporal filter and no AO term. The sky, the point-light shadows, the HUD, and
  the menu must be in the state the estimator models; the command rejects a run
  that is not.
- `samples` is the paths per sample point, `bounces` the diffuse bounces after
  the camera hit (1..8), and `stride` the pixel grid step. One bounce matches the
  probe update; more bounces report the missing transport. Bounce vertices use
  the same point-light direct term as `probe_ray.comp`.
- The estimator is deterministic. The seed names the grid index and the path
  index, so a repeat run gives the same metrics.
- The command writes `frames/<name>-reference.png` (the headless target at the
  grid extent), `<name>-reference.json`, and `<name>-reference.csv` in the run
  directory. Both scene reports join `report.json.references`.
- A metric outside `tolerance` joins `report.json.failures` and the run exits 1,
  unless the command has `"advisory": true`. An advisory report still writes its
  files and records `ok: false`; it does not fail the run. The command itself
  still succeeds, so one run compares every scene it declares.

`scenarios/ddgi-reference.json` is the worked example: the `ddgi` chamber with
one lamp, then the room lane with a second lamp. `scenarios/ddgi-platform.json`
adds the dive platform under a point lamp; its shaded face, tunnel corner, and
contact gate the probe visibility. `make reference` runs both. The estimator, the scene, the tolerance, and the
current numbers are in
[`docs/evidence/ddgi-reference.md`](../evidence/ddgi-reference.md).

The unit tests in `tests/reference` cover the estimator without a GPU: a cosine
furnace plane, the point-light term, the lamp shadow mask, the camera basis, the
sky miss, and the comparison math.

## Interior room

`scenarios/room-lighting.json` drives the closed room in the arena's +x/+z
corner. The room is static arena geometry, not a placed object. It is 11 m
square with a 3 m clear height and one west door. The door opens into a
four-turn light lock: east, south, west, south, and east into the chamber.

The short level recipe:

```sh
make shot SCENARIO=room-lighting OUT=runs/room-lighting
jq -r '.captures[] | select(.name | test("chamber")) | [.name, .stats.mean.y] | @tsv' \
  runs/room-lighting/report.json
```

A depth capture with `max < 0.999` proves no sky pixel is visible in the room.
Use `harbagsa-agent boxes` when the question is the plan rather than the light.

The scenario:

1. captures the outside and the chamber;
2. checks that the chamber mean stays at the output dither floor and that the
   depth target contains no sky pixel;
3. places a warm lamp with `place` (no debug mode), then removes it and checks
   that the chamber returns to the dither floor.

The lamp intensity and lamp range are scenario parameters. Change them with
`--param` without editing the file:

```sh
./bin/harbagsa-agent run scenarios/room-lighting.json \
  --param lamp_intensity=3
```

The scenario sets `"analysis": false` because its captures are different views,
not a steady series. `make lighting` runs it with the sky, AO, ramp, sealed-pair,
and arena coverage scenarios.

`scenarios/ddgi.json` isolates the probe term. It puts the camera in the chamber,
places one lamp, and captures the same view with the probe indirect on and off. It checks the probe count, the volume count,
the atlas energy, and that the on frame is brighter. The off frame still shows
the direct lamp, so the difference is the bounce.

`scenarios/ddgi-sealed.json` builds a sealed two-room pair from static placed
Walls and Platforms at (-10, -8). The scenario supplies its own two 1 m probe
volumes in a `scene` block, so the production scene keeps no test-room probes.
Every placed wall and roof has a name. A lamp sits in room A and the camera in
room B behind a solid shared wall. The wall capture stays at the dither floor
before and after the lamp, and a depth capture proves the wall is in front of
the camera. The scenario then removes `shared-north`, the door segment of the
shared wall, by name in the same run. The doorway view brightens, and a view of
the far wall is dimmer than the doorway. The opening is transport; the solid
wall is the leak gate. `scenarios/ddgi-door.json` still looks through the room's
static west door, and `scenarios/ddgi-move.json` moves the lamp with the editor
and checks both views stay lit.

`scenarios/ddgi-arena.json` covers the open arena and the room exterior. It uses
the `outside` camera from `room-lighting`, captures the whole frame, and measures
the room's west face, which no direct light reaches. The face mean must clear
the old black level and its pure-black colour-key fraction must fall below 0.1. A second
view at the chamber camera proves the sealed room stays at the dither floor and
that its depth target holds no sky pixel. The default scene supplies six probe
volumes: the room first, a roof volume, and four perimeter volumes that meet
the room's inner faces. The room volume wins the sampler for the interior, and
the perimeter volumes own the wall thickness, the door threshold, and the open
floor. `scenarios/ddgi-sealed.json` adds its two pair volumes after the room and
before the arena strips, which gives that run eight volumes and 2301 probes.
`tests/frame/probe_volumes.odin` keeps the default ordering and bounds in the
build; `tests/harness/probe_map.odin` parses the sealed scenario and checks its
eight volumes, 2301 probes, names, and ownership.

The chamber is black, not merely shaded, before the lamp exists. The depth check
proves the room is closed. With the lamp on, the probe volume adds one diffuse
bounce and the occlusion term darkens the direct corners. `scenarios/ddgi.json` captures the
same lamp view with the probe indirect term on and off; the on frame is brighter
on the floor and the far wall, where no lamp ray reaches.

### Probe map

```sh
./bin/harbagsa-agent probes
./bin/harbagsa-agent probes scenarios/ddgi-sealed.json --coverage
./bin/harbagsa-agent probes --point 12,1.5,9 --json
```

`probes` prints the effective layout: each volume's name, bounds, spacing,
counts, probe count, and first atlas index. Without a scenario it prints the
production scene. With a scenario it reads the last `scene` block's
`probe_volumes` and composes the run's list without a renderer; it reads the
last scene block and does not run the commands. With no
`--point`, it samples each volume's centre and reports the volume that owns it.
`--point X,Y,Z` asks for one point; repeat it. `--coverage` samples the visible
faces of every static arena box and reports the points that no volume owns.
Faces on the floor, inside another box, within 0.25 m of a face edge, outside
the arena walls, or above the wall height are excluded: they are hidden or a
boundary case. A
non-zero `outside` count is the cheap signal that a surface has no probe. It is
the layout gate that the ULP bound bug needed.

`--step M` sets the coverage sample spacing (default 0.5 m, minimum 0.1). The
JSON form carries `{scenario, count, probe_count, volumes, points, coverage}`.
`probes` exits 0; it reports, it does not fail. Add a scenario gate when the
layout must be fixed.

### Plan view and static boxes

`harbagsa-agent boxes` prints the immutable arena boxes without a renderer;
`--json` writes `{count, boxes}`. A check reads the same list as
`static_boxes.count` and `static_boxes.N.center.x`, `.half_extents.z`,
`.color.r`, `.rotation.w`, `.emissive`, and `.visual_only`. The list is 63
boxes: the floor and four walls, the props, and the room. This is the cheap way
to check a door gap or a room plan.

For a picture, add `"renderer_debug": {"clip_height": 2.0}` and put the camera
above the arena looking down. The clip discards the roof and the upper walls.
`scenarios/box-plan.json` is the worked example; run it with
`make shot SCENARIO=box-plan OUT=runs/box-plan`.

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
  completed frame, two frames behind the recording frame. The cluster
  assignment, the probe update, the depth prepass, the lit scene, and the sky are
  separate passes; the lit pass does not include the depth prepass, the cluster
  assignment, or the probe update. Both sky timestamps are written even when the sky is off, so
  that pass reads near zero and the set is always complete.
- The `--verbose` line labels the frame interval (wall clock) and, when the
device supplies timestamps, the GPU total. `ab.sh` labels both columns in its table. Use the
  interval for throughput and the GPU total for the render cost; do not mix
  them.
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
receive no direct light. Run either at the same size on two builds to compare.
The before/after is in `docs/evidence/perf-scene-pass.md`.

`scenarios/perf-crates.json` places 60 objects in a grid with the Crate prefab
and measures them, so the box count is part of the probe.

`scenarios/perf-lamps.json` measures the point-light path. The top-level
`renderer_debug` block injects synthetic lights, the first `perf` command
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
  placement return to their defaults.
- `look` uses the game sensitivity and pitch clamp. `face` sets yaw and pitch
  directly.
- Capture alpha defaults to 1.0 (post-step), so a capture matches `state` at the
  same frame.
- The digest is FNV-1a over frame, player, the placed objects
  (id, prefab, body, and the physical transform), the window and input settings,
  and menu state. Scale and spawn age are animation output, so they stay out of
  the digest. The visual pop box is not digest input. Use the digest in reports
  and regression checks.

## Where the code lives

- `src/harness/`: CLI, scenario compiler, commands, session, runner, socket, PNG.
- `src/harness/capture.odin`: the capture result, target, format, and file write.
- `src/harness/capture_stats.odin`: the capture statistics and pixel hash.
- `src/harness/capture_color_key.odin`: the colour key count.
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
- `src/harness/ab_command.odin`: the `ab` wrapper over `tools/ab.sh` and `tools/visual-ab.sh`.
- `src/harness/boxes.odin`: the `boxes` command over `game.arena_static_boxes`.
- `src/harness/probes.odin`: the `probes` CLI, scenario-volume load, and print.
- `src/harness/probe_map.odin`: the probe map report, ownership samples, and
  static-box coverage.
- `src/harness/checks.odin`: the `checks` table over a run's `report.json`.
- `src/harness/shot_command.odin`: the scenario-only `shot` shorthand.
- `src/harness/run_backend.odin`: the lazy run backend.
- `src/harness/run_paths.odin`: the tag-aware run directory.
- `src/harness/run_stages.odin`: the five run stages, their results, and the
  state they share.
- `src/harness/run.odin`: the run orchestrator and its exit-code precedence.
- `src/harness/session_settle.odin`: the convergence wait.
- `src/harness/state_schema.odin`: the reflection walk over `State` that resolves
  check paths. `State` and its `json` tags are the schema.
- `src/harness/state_sections.odin`: the one table of conditional state
  sections, their builders, and the field-to-section map.
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
- `src/harness/renderer_debug_command.odin`: the table-driven override parser,
  the reset patch, and the key list.
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
- `src/harness/scene_probe_volumes.odin`: the scene `probe_volumes` parser.
- `src/harness/scene_objects.odin`: scene objects, lights, and displays.
- `src/harness/session_scene.odin`: applies a scene to a session.
- `src/harness/session_probe_volumes.odin`: composes the run's probe list and
  frees the scene extras.
- `src/harness/object_name.odin`: the inline placed-object name a command
  carries.
- `repro.odin`: the `F5` key wrapper over the scene snapshot writer.
- `suites/renderer.json`, `suites/offscreen.json`, and `suites/ui.json`: the
  first manifests.
- `src/digest/digest.odin`: FNV-1a for the state and render digests.
- `src/perf/`: the perf sample, ring, statistics, and text formatting.
- `src/renderer/timing.odin`: the timestamp pools, the pass boundaries, and the
  read.
- `src/renderer/debug.odin`: the debug gate, overrides, and shadow phase.
- `src/renderer/frame_targets.odin`: the depth, scene-colour, and velocity
  attachments and their lifecycle.
- `src/renderer/lights.odin`: the point-light type, instance masks, synthetic
  lights, and upload.
- `src/renderer/state.odin`: the renderer report and setup.
- `src/renderer/render_digest.odin`: the render digest.
- `src/renderer/shader_digest.odin`: the embedded SPIR-V digest.
- `src/renderer/sky_draw.odin`: the sky pass and its pipeline.
- `src/renderer/text_shaper.odin`: FreeType and HarfBuzz shaping for the 2D layer.
- `src/renderer/capture.odin`: the target copy and RGBA f32 decode.
- `src/frame/`: shared scene assembly and draw for the game and the harness.
- `src/frame/probe_volumes.odin`: the room, roof, and open-arena probe volumes,
  the first-match helpers, and the scene-extra composition.
- `src/game/prefabs.odin`: the placed-object body modes, prefab catalog, and
  starting crate layout.
- `src/game/objects.odin`: the placed-object list and the create, remove, move,
  yaw, convert, reset, and name API.
- `src/game/lights.odin`: the light type, the colour cycle, the intensity and
  range steps, the active light collection, and the light count.
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
- `src/game/oriented_box.odin`: the oriented box corners, the AABB half
  extents, and the point-inside test the coverage sampler uses.
- `src/game/debug_draw_ghost.odin`: the ghost outline, footprint, and height
  guide lines.
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
  `renderer_state.odin`, `suite.odin`, `scene.odin`, `probe_map.odin`,
  `object_names.odin`, `coverage.odin`, and `compare.odin`),
  `tests/frame/`, `tests/display/display.odin`,
  `tests/renderer/` (including `target.odin`, `render_digest.odin`,
  `capture_values.odin`, and `debug.odin`), and `tests/docs/harness.odin` for
  the registry-to-docs check.
- `scenarios/smoke.json`, `scenarios/taa-static.json`,
  `scenarios/taa-motion.json`, `scenarios/settings-menu.json`,
  `scenarios/window-settings.json`, `scenarios/renderer-state.json`,
  `scenarios/renderer-reset.json`, `scenarios/capture-targets.json`,
  `scenarios/renderer-debug.json`, `scenarios/renderer-debug-converge.json`,
  `scenarios/renderer-debug-jitter.json`, `scenarios/capture-free.json`,
  `scenarios/box-plan.json`, `scenarios/shot.json`,
  `scenarios/editor-ghost.json`, `scenarios/editor-object.json`,
  `scenarios/editor-lamps.json`,
  `scenarios/debug-pop.json`, `scenarios/type-weight.json`,
  `scenarios/repro-notice.json`, `scenarios/sky.json`,
  `scenarios/stairs-ao.json`, `scenarios/ramp-shadow.json`,
  `scenarios/ramp-shadow-crouch.json`, `scenarios/banding.json`,
  `scenarios/banding-phase.json`, `scenarios/lamp-wall-plane.json`,
  `scenarios/room-lighting.json`,
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
session use the same policy through `Session.render.provider`; a capture with
rendering disabled is skipped in both. A `Required` command without rendering
fails in its own execute proc, so CPU-only `perf` still works.

## Checks

```sh
tools/make.sh check
tools/make.sh test
tools/make.sh build
```

`make test-<package>` runs one test package:
`test-display`, `test-platform`, `test-input`, `test-physics`,
`test-simulation`, `test-frame`, `test-perf`, `test-harness`,
`test-renderer`, or `test-docs`. `make test` runs all of them.

Odin's test runner counts any log at `error` or `fatal` as a failed test, even
when the test asserts the error. Return the error from the library code and let
the outer layer log it; do not log an expected failure inside a test.

`make smoke` runs the smoke scenario with the normal agent and needs no
validation layer. `make shot SCENARIO=... OUT=...` builds, runs one scenario,
and prints the capture paths; use it for every visual loop. `make ui` runs
`suites/ui.json` into `runs/ui/<entry>`; `make lighting` runs
`suites/lighting.json` into `runs/lighting/<entry>`; `make quick` runs
`suites/fast.json` into `runs/fast/<entry>`.

`harbagsa-agent checks runs/<stem>` prints every check with its gate, actual
value, and margin, including the checks that passed. `--json` writes the same
rows. A positive margin is the distance from the gate in the pass direction;
the command exits 1 when a blocking check failed. An advisory miss prints
`ADVISE` and does not fail the command. Use it instead of a hand-written `jq`
table when re-baselining.

`harbagsa-agent probes [scenario]` prints the effective probe layout and its
coverage without a renderer; see **Probe map**. It is the cheap layout gate
beside `boxes`.

`scenarios/advisory.json` runs one advisory miss and one pass. The run exits 0,
the report carries `advisory: true` on the miss, and `checks` prints `ADVISE`.
An advisory check that cannot resolve its field is still an error and fails the
run; the flag suppresses a miss, not a broken gate.
`scenarios/ddgi-arena.json` gates a color `black_fraction` and `lit_fraction`
and a float `zero_fraction` from the same `coverage` block.

`tests/docs/harness.odin` reads the command registry and fails when the README
or this page stops naming a command, capture target, format, or check operator.
Run `make test-docs` after a rename or a removal.

`make check-references` scans every Markdown page and suite for a missing
`scenarios/*.json` or `suites/*.json` reference. Run it after a rename. Test
binaries land in `build/test/`, so a failed test leaves no `.bin` in the root.

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

`make suite SUITE=renderer` runs a suite with the normal agent. `make smoke` is
the short end-to-end gate and needs no validation layers. `make validate-demo`
runs the game with validation enabled.

## Keep the harness current

The harness is part of the product. When you add or change a feature, update the
harness in the same change. Do not leave the automation behind the game.

- New edit intent: add one variant to `game.Edit_Action`, one case in
  `edit_apply`, the keyboard adapter, the `editor` parser, a harness test, and
  this page. Do not add a second rule outside `edit_apply`.

- New simulation input: add it to `game.Input_Snapshot`, the `input` command,
  and `tests/harness`.
- New state field: add it to the `State` struct with its `json` tag. A field in
  an existing conditional section is filled by that section's builder in
  `STATE_SECTION_ROWS`; a new namespace is one row in `STATE_SECTION_ROWS`. The
  build, the check resolver, and the digest set read the table. Add `digest:"-"`
  when it must not enter the simulation digest.
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
- New capture target or format: add the target to `Capture_Target`,
  `target_image`, and `record_capture_copy`. Add the harness format to
  `CAPTURE_FORMAT_INFO` (name, parser, and extension in one row). Add the
  Vulkan format and its decode kind to `CAPTURE_FORMATS`; `capture_values`
  dispatches on that kind. Add it to the capture parser, the README, this page,
  and a scenario. An unread target is not a tool.
  `tests/renderer/capture_format.odin` checks that every Vulkan row has a
  decoder and fits `MAX_CAPTURE_TEXEL_BYTES`.
- New analysis field: add it to the `Analysis_*` types, `analysis_field`, the
  analysis report, the docs, and a unit test. `analysis_bands.odin` owns the
  flat-run metric.
- New capture block: add it to `Capture_Spec`, the backend, `capture_field`,
  the docs, and a synthetic image test. A block that writes no file must still
  be readable by a check. A check must read the same value the file records.
  `color_key` and `coverage` are the worked examples: parser, builder, report
  field, check field, schema path, and a unit test.
- New scene block: add it to `SCENE_KEYS`, `Scene_Command`, the parser, the
  session apply, `Scene`, the snapshot writer and destroy, the docs, and a
  scenario test. `probe_volumes` is the worked example: it is also composed by
  `session_set_probe_volumes` and read by the `probes` command.
- New placed-object field: add it to `Placed_Object`, `Object_Record`,
  `Object_Spawn`, the snapshot copy and restore, the scene object, the state,
  the digest exclusion when it is not behaviour, and the docs. `name` is the
  worked example.
- New scenario shorthand: compile it to explicit commands in
  `scenario_commands`, not to a new session command, so a live session and a
  recorded scenario cannot depend on it. `shot` is the example.
- New report field on a capture: add it to `Capture_Result` and set it in
  `session_draw_group`; that is where the frame's renderer report is copied.
- New render input: add the field to `Render_Input`, one row to
  `RENDER_DIGEST_FIELDS` (hashed, or an explicit exclusion with the reason), the
  recorder fill, and the reflection test. The uniform reads the same input.
- New renderer report field: add the field and tag to `Renderer_Report` or
  `Debug_Report`. The State reflection walk covers the JSON and check paths;
  there is no separate report table.
- New renderer debug override: add it to `Renderer_Debug`, its default,
  `Renderer_Debug_Patch`, `renderer_debug_patch`, `renderer_debug_apply_patch`,
  one `RENDERER_DEBUG_FIELD_ROWS` row, the `debug_patch_set_*` arm, the reset
  arm in `renderer_debug_reset_patch`, the resolve push constants and shader,
  the renderer state, the docs, and the gate test. The parser, the key list, and
  the scene snapshot read the same patch and table. Do not make it reachable
  without the gate.
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
  offscreen test when the pass must match the game. A frame-sized attachment
  belongs in `Frame_Targets`, so create, destroy, and resize stay in
  `frame_targets.odin`.
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
- A test scene owns its probe volumes. Do not put the sealed pair or another
  test room in `PROBE_VOLUMES`; that gives every run probes for a room it does
  not have. Use a `scene` block and `probes --coverage`.
- Do not make a renderer debug override reachable without the define or
  `--debug-renderer`.
- Do not widen a capture target without a readback path; an unread target is not
  a tool.
