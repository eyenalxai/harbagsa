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
| drive the object palette and placement tool | **Editor** |
| capture the final image | **Capture targets** (`color` + `png`) |
| read velocity, history, depth, or scene color | **Capture targets** |
| read numeric image statistics | **Capture targets** (`stats`) |
| read renderer state or the render digest | **Renderer state** |
| change a TAA or light input for a diagnosis | **Renderer debug overrides** |
| measure image stability or the period | **Analysis** |
| compare two builds or revisions | **Cross-run diff** |
| script the display list | **Commands** (`displays`) |
| dump the HUD and menu rows | **Commands** (`rows`) |
| measure an edge or a gradient | **Capture targets** and **Analysis** |
| compare two builds | **Performance** and `ab` |
| measure frame time | **Performance** |
| prove a capture-free sequence is deterministic | **Screenshots** and `scenarios/capture-free.json` |
| understand a design choice | `docs/adr/0008` to `docs/adr/0019` |

## What one run writes

`runs/<scenario-stem>/`

- `report.json`: `ok`, `exit_code`, `scenario` (`path` and `hash`), `run_dir`,
  `frame`, `state`, `setup`, `screenshots`, `checks`, `failures`, `digest`,
  `error`, `perf` (a list of named reports) when perf ran, `trace` when the run
  wrote a perf trace, and `analysis` when the run wrote an analysis report.
- `analysis.json`: the per-run image analysis. See **Analysis**.
- `frames/analysis-diff.png` and `frames/analysis-variance.png`: the optional
  analysis maps.
- `trace.jsonl`: one JSON object per measured frame, when the perf command asks
  for a trace. A scenario with more than one traced perf command writes one file
  per command; `report.trace` names the last.
- `state.json`: the final state alone. It holds the player, placed objects,
  window and input settings, menu, debug palette and placement, frame, renderer,
  render digest, and simulation digest. Each object carries `id`, `prefab`,
  `body`, `position`, `rotation`, `scale`, and `spawn_age`.
- `frames/<name>.png`, `.f32`, or `.bin`: captures. A color capture is a PNG;
  `float` and `raw` write the intermediate target.
- Each screenshot entry carries `delta_mean`, `delta_max`, and `delta_over_16`
  against the previous capture. The first capture has zeros.
- `run.log`: log lines from the renderer, the session, and the runner.

Standard output is one JSON summary. Standard error holds logs. `--verbose` (or
`--summary`) adds a human summary to standard error: the setup revision and
dirty flag, every capture, every check result, every failure, and every named
perf result. The JSON line on standard output does not change.

`run -` reads the scenario from standard input. `--tag NAME` appends a directory
to the run path, so `runs/smoke/before` and `runs/smoke/after` coexist.
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

- The scenario has one body form: `commands`. It runs verbatim, and `record`
  writes the same form.
- `step` advances one `SIMULATION_STEP` (1/60 s) per frame. The harness does not
  use wall-clock time.
- `look` applies once. `input` persists until the next `input`; `jump` is an
  edge on the next step.
- Only a `capture` command captures. A scenario with no `capture` and no perf
  run does not create a renderer unless `--present` asks for the window.
- A check uses the `state.json` shape. Operators: `eq`, `ne`, `lt`, `le`, `gt`,
  `ge`. Examples: `player.position.y`, `objects.count`, `settings.window_mode`,
  `settings.resolution`, `settings.sprint_mode`, `menu.open`, `debug.active`,
  `debug.palette.open`, `debug.placement.armed`, and
  `debug.placement.prefab`.
- An object check addresses a placed object by id: `objects.7.position.z`,
  `objects.7.rotation.w`, `objects.7.prefab`, `objects.7.body`,
  `objects.7.scale`, and `objects.7.spawn_age`. The id is stable while the object
  exists. `objects.count` is the list length.
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
- A top-level `"size": "1280x720"` pins the extent. `--size` with a declared
  size is an error.
- A top-level `"extends": "base.json"` merges the base object and lets the child
  win; a relative path resolves against the extending file. A `parameters` block
  substitutes `${name}` in any command value. A parameter must be a string,
  number, or boolean.
- A check compares with `value` or with `other`:
  `{"cmd":"check","field":"capture.1.stats.mean.y","op":"gt","other":"capture.0.stats.mean.y"}`.
  `capture.N.*`, `capture.first.*`, and `capture.last.*` name one capture.

## Commands

- `{"cmd": "reset"}`
- `{"cmd": "look", "dx": 220, "dy": 0}`
- `{"cmd": "face", "yaw": 0, "pitch": 0}`
- `{"cmd": "input", "forward": 1, "right": 0, "jump": false}`
- `{"cmd": "step", "frames": 60}`
- `{"cmd": "settle", "until": "converged"}`: wait for the 512-sample cap; the
  reply and `state.json` report `settle.frames` and `settle.converged`.
- `{"cmd": "settle", "frames": 300}`
- `{"cmd": "state"}`
- `{"cmd": "rows"}`
- `{"cmd": "capture", "name": "shot", "frame": 90, "alpha": 1.0}`
- `{"cmd": "camera", "position": [0, 2, 12], "yaw": 0, "pitch": 0}`
- `{"cmd": "camera", "position": [0, 2, 12], "look_at": [0, 1, 0], "fov": 75}`
- `{"cmd": "camera", "clear": true}`
- `{"cmd": "view", "hud": true, "debug": false, "hint": false, "perf": false}`
- `{"cmd": "sun", "azimuth": 52.1, "elevation": 15, "diameter": 0.53}`
- `{"cmd": "sun", "clear": true}`
- `{"cmd": "sun", "clear": true}`
- `{"cmd": "crates", "reset": true}`
- `{"cmd": "crates", "clear": true}`
- `{"cmd": "crates", "add": {"position": [0, 0.5, 6]}}`
- `{"cmd": "crates", "add": {"origin": [0, 0.5, 6], "count": 60, "columns": 10, "spacing": [1, 0, 1]}}`
- `{"cmd": "crates", "remove": {"index": 3}}`
- `{"cmd": "displays", "set": [{"name": "Solo", "desktop": "1280x720", "modes": ["1280x720"]}]}`
- `{"cmd": "displays", "clear": true}`
- `{"cmd": "rows"}`
- `{"cmd": "displays", "set": [{"name": "Solo", "desktop": "1280x720", "modes": ["1280x720"]}]}`
- `{"cmd": "displays", "clear": true}`
- `{"cmd": "debug_mode", "active": true}`
- `{"cmd": "editor", "open": true, "select": 4, "pick": true, "height": 0.5}`
- `{"cmd": "editor", "camera": {"position": [0, 1.7, 14], "yaw": 0, "pitch": -0.6}}`
- `{"cmd": "editor", "place": {"prefab": "Block", "position": [0, 0.5, 10], "body": "static"}}`
- `{"cmd": "menu", "open": true, "select": 1, "activate": true, "direction": -1}`
- `{"cmd": "check", "field": "player.position.y", "op": "gt", "value": 0}`
- `{"cmd": "check", "field": "capture.1.stats.mean.y", "op": "gt", "other": "capture.0.stats.mean.y"}`
- `{"cmd": "perf", "frames": 120, "warmup": 60}`
- `{"cmd": "renderer_debug", "jitter": false, "shadow_phase": 12}`
- `{"cmd": "renderer_debug", "light_shadows": false, "synthetic_lights": 8}`
- `{"cmd": "record", "path": "scenarios/walk.json"}`
- `{"cmd": "record"}`
- `{"cmd": "replay", "path": "scenarios/walk.json"}`
- `{"cmd": "quit"}`

`camera` accepts `look_at` instead of `yaw`/`pitch`, and `fov` in degrees
(1..170). Both angle forms together are an error, and so is a `look_at` equal to
the position. `state.camera` reports the effective view and whether an override
is active.

`settle` also takes `{"cmd":"settle","until":"converged"}`. It renders until the
convergence count reaches the 512 cap and reports `settle.frames` and
`settle.converged`. It needs a renderer.

`sun clear` restores the default direction and angular diameter.

`displays` replaces the harness display list for the rest of the run. A display
with no `desktop` and no modes gives the menu a zero-mode display, which blocks
the Resolution row. `clear` restores the fallback list.

`rows` returns the HUD and menu rows that the renderer would draw: `kind`,
`label`, `value`, `blocked`, `ratio`, and `ticks`.

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

A capture names its target and format. See **Capture targets**. A region
limits the statistics to a rectangle, a profile measures an edge or a gradient,
a crop writes a scaled PNG, and a histogram counts the region's channels.

`displays` replaces the menu's display list. Each entry has a name, an optional
desktop size, and an optional mode list. A display with no modes blocks the
Resolution row, so the blocked menu state is scriptable. `clear` restores the
fallback list.

`rows` replies with the HUD and menu rows: kind, label, value, blocked, ratio,
and ticks. A check reads them as `rows.hud.N.*` and `rows.menu.N.*`.

The `sun` command moves the light or resizes its disk. `azimuth` is degrees from
`+z` toward `+x`, and `elevation` is degrees above the horizon; both describe
where the sun sits, not the direction its light travels. `diameter` is the angle
the sun disk subtends, in degrees, and sets the penumbra width. Omitted fields
keep their value, and `reset` restores the default sun. The state reports the
same three values under `sun.*`, so a check can assert the light a capture used.
Changing the sun resets TAA history with the `scene_change` reason.

## Editor

The `editor` command drives the debug placement tool. It needs debug mode; send
`{"cmd": "debug_mode", "active": true}` first. Every field is optional, and one
command may combine fields. They apply in this order: `camera`, `open`,
`select`, `body`, `height`, `yaw`, `snap`, `pick`, `cancel`, `place`.

| Field | Meaning |
| --- | --- |
| `open` | open or close the object palette |
| `select` | zero-based prefab index; a new prefab restores its default body |
| `body` | `static` or `dynamic` for the next placement |
| `pick` | arm the selected prefab, close the palette, cast the placement ray |
| `height` | offset above the surface in metres; clamped at 0 |
| `yaw` | rotation in degrees |
| `snap` | round the X/Z bottom anchor to a 0.25 m grid |
| `cancel` | clear the armed tool without placing |
| `camera` | `{"position", "yaw", "pitch"}` for the debug camera; yaw and pitch are radians |
| `place` | `{"prefab", "position", "yaw", "body"}` creates at an exact transform |

`select` follows the catalog order: Crate, Small crate, Wide crate, Block,
Platform, Ramp, Pillar, Wall. A pick casts a 100 m ray from the debug camera. A
hit puts the object's AABB bottom on the hit point; a miss puts it 3 m ahead of
the camera. The state reports the ghost centre as `debug.placement.position`.

`place` requires `prefab` and `position`. Its `yaw` defaults to 0 and its `body`
to the prefab default. It bypasses the ray and leaves the armed tool unchanged.
At the 128-object cap it creates nothing.

The state carries `debug.palette` (`open`, `selected`, `body`) and
`debug.placement` (`armed`, `prefab`, `position`, `height`, `yaw`, `snap`).
`debug.selection` is `none`, `object`, or `sun`, and `debug.selected_id` is the
selected placed object's id or 0. `debug.placement.height` is metres,
`debug.placement.yaw` is degrees, and `debug.placement.position` is the ghost
centre (zero when not armed). The ghost is drawn as debug lines while armed: the
oriented box, the footprint on the surface, and the height guide.

`scenarios/editor-ghost.json` captures the armed ghost on the floor and raised,
then places a block at an exact transform. `scenarios/debug-palette.json` opens
the palette, captures the Platform preview, selects the Ramp, and captures its
pitched preview. Run it with `--size 800x600` to check the dock fits the smallest
supported window.

## Spawn pop

A placement or a duplicate plays a 0.28 s spawn pop. The visual scale follows
`easeOutBack` with a back factor of 1.5: it peaks at about 1.08 and has a floor
of 0.01. The scale multiplies the box half extents and moves the centre so the
AABB bottom stays fixed. The physics body keeps its full size.

Initial crates and undo or redo restores are settled: scale 1 and spawn age 0.
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
pop does not reset TAA. `simulation_restore_object` is the settled create path
for a future undo or redo restore.

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
| `scenarios/debug-palette.json` | the open palette, its selection, and the cube and ramp previews |
| `scenarios/debug-pop.json` | the spawn pop at the start, overshoot, and settled frames |
| `scenarios/ui.json` | the settings panel with a numeric value selected, then an action row |
| `scenarios/settings-menu.json` | the settings round trip and the menu digest |
| `scenarios/blocked-note.json` | the blocked-change note and its clear on a successful change |
| `scenarios/window-settings.json` | the window rows after a display change |
| `scenarios/type-weight.json` | the Type weight slider at 400, 900, and 100 |

Read the evidence from a run directory:

```sh
./bin/harbagsa-agent run scenarios/hud.json --out runs/ui/hud
./bin/harbagsa-agent run scenarios/hud-debug.json --out runs/ui/hud-debug
./bin/harbagsa-agent run scenarios/settings-menu.json --out runs/ui/menu
./bin/harbagsa-agent run scenarios/blocked-note.json --out runs/ui/blocked-note
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
- `stats`: any target. Writes no file. The report holds per-channel `min`,
  `max`, and `mean`, and for `velocity` the median screen motion in texels over
  covered pixels.

A stats capture accepts `"region": {"x","y","w","h"}` or `"rect": [x,y,w,h]`.
The statistics cover the region and the report echoes it; a check reads
`capture.stats.region.x` and the other region fields. Add `"histogram": 8` for
per-channel bin counts in `capture.histogram.x`, `.y`, `.z`, and `.w`.

A color capture accepts a `profile` block and `"format": "profile"` for an
edge measurement, and a `crop` block to write a scaled PNG. A profile over a
PNG capture is allowed and reported beside the PNG.

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

`analysis.bands` measures the identical-luma runs down the columns of the last
analyzed frame: `longest_run`, `median_run`, `levels`, and `columns`. A gradient
that is continuous in 16-bit and bands after the 8-bit resolve shows a long run.
`scenarios/banding.json` gates the sky at `longest_run < 64`.

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
| `light_count` | the point lights the last frame uploaded, at most 8 |

The reset reasons are `none`, `create`, `extent`, `toggle`, `teleport`,
`scene_change`, `debug_override`, `player_reset`, and `scene_reset`. A change to
the sun direction or the sun angular diameter is a `scene_change`. A state
check reads the override values as `renderer.debug.*`, for example
`renderer.debug.sky` and `renderer.debug.ao`.

The nested `debug` object repeats the active override values: `taa`, `jitter`,
`history_weight`, `clamp`, `depth_trust`, `shadow_phase_frozen`,
`shadow_phase`, `light_shadows`, and `synthetic_lights`.

The render digest is FNV-1a over the effective camera, the sun direction, every
box, the box emissive strengths, the point lights, the jitter, the shadow phase,
and the view flags. It changes when any of those change and stays the same when
they do not. It is separate from the simulation digest: read `render_digest` for
the render inputs and `digest` for the simulation.

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

`{"cmd": "renderer_debug", ...}` changes TAA and point-light inputs without
editing source. It is diagnostic and gated. A build with
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
| `clear` | reset every override and turn TAA on |

An override starts from the current state. A scenario can put the same fields in
a top-level `renderer_debug` object; it compiles to the command before the commands.

Every change to the override resets the history with reason `debug_override`,
including a new shadow phase and a light change.

`scenarios/renderer-debug.json` sets every override and clears it.
`scenarios/renderer-debug-converge.json` turns jitter off and freezes the phase,
so the image converges. `scenarios/renderer-debug-jitter.json` freezes the phase
and lets jitter cycle, so the analysis can find the period.
`scenarios/perf-lamps.json` injects eight synthetic lights, measures shadows on,
then disables the point-light shadows and measures again. It writes one trace per
side.

## Sky and ambient occlusion

The sky is an analytic gradient. It draws after the lit pass and shades only the
background pixels. The lit pass traces eight ambient occlusion rays per fragment
and scales the ambient term by the visible fraction. Both features are on by
default. The design is in
`docs/adr/0017-sky-ambient-and-ray-traced-ambient-occlusion.md`.

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
phases, and six GPU pass times (the TLAS build, the depth prepass, the lit
scene, the sky, the TAA resolve, and the overlay). The game shows it on `F4`. A scenario can show
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
  completed frame, two frames behind the recording frame. The depth prepass, the
  lit scene, and the sky are separate passes; both sky timestamps are written
  even when the sky is off, so that pass reads near zero and the set is always
  complete.
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

`scenarios/perf-lamps.json` measures the point-light path. The top-level
`renderer_debug` block injects eight synthetic lights, the first `perf` command
measures them with hard shadows, then the command disables point-light shadows
and the second `perf` measures again. Both traces stay in the run directory:
`trace-shadows-on.jsonl` and `trace-shadows-off.jsonl`. It needs
`--debug-renderer` or the build define. The paired result is in
`docs/evidence/perf-lamps.md`.

## Determinism

- Fixed 60 Hz. Never sleep or use a wall-clock delta.
- A perf command is the one wall-clock exception. It never writes the state,
  the digest, or the pixel hash.
- `reset` creates a fresh `Simulation`. Placed objects return to spawn, the
  settings return to their defaults, the menu closes, and the debug palette and
  placement return to their defaults.
- `look` uses the game sensitivity and pitch clamp. `face` sets yaw and pitch
  directly.
- Capture alpha defaults to 1.0 (post-step), so a capture matches `state` at the
  same frame.
- The digest is FNV-1a over frame, player, the placed objects (id, prefab, body,
  and the physical transform), the window and input settings, and menu state.
  Scale and spawn age are animation output, so they stay out of the digest. The
  visual pop box is not digest input. Use the digest in reports and regression
  checks.

## Where the code lives

- `src/harness/`: CLI, scenario parser, commands, session, runner, socket, PNG.
- `src/harness/scenario.odin`: the one `commands` scenario form and the analysis config.
- `src/harness/diff.odin`: the pure pair comparison and the diff report types.
- `src/harness/diff_captures.odin`: run capture discovery and the frame fallback.
- `src/harness/diff_cli.odin`: the `diff` command and its table/JSON output.
- `src/harness/capture.odin`: the capture result, target, format, and file write.
- `src/harness/capture_stats.odin`: the capture statistics and pixel hash.
- `src/harness/capture_command.odin`: the capture target/format parser.
- `src/harness/capture_region.odin`: the region, crop, and histogram.
- `src/harness/capture_profile.odin`: the edge profile and its 10%-90% width.
- `src/harness/analysis_bands.odin`: the identical-run band metric.
- `src/harness/scenario_inherit.odin`: `extends` and `parameters`.
- `src/harness/session_rows.odin`: the HUD and menu row dump.
- `src/harness/session_displays.odin`: the scripted display list.
- `src/harness/ab_command.odin`: the `ab` wrapper over `tools/ab.sh`.
- `src/harness/run_paths.odin`: the tag-aware run directory.
- `src/harness/session_settle.odin`: the convergence wait.
- `src/harness/state_field_leaves.odin`: the leaf field resolvers.
- `src/harness/state_fields.odin`: the top-level state field table.
- `src/harness/cli_override.odin`: the CLI renderer override.
- `src/harness/perf_run.odin`: the perf run and its prime loop.
- `src/harness/perf_report.odin`: the perf report types and fill.
- `src/harness/perf_command.odin`: the perf command parser.
- `src/harness/session_state.odin`: the session's renderer snapshot.
- `src/harness/editor_command.odin`: the `editor` command and its parser.
- `src/harness/session_editor.odin`: the `editor` command execution.
- `src/harness/session_debug.odin`: the renderer debug gate and overrides.
- `src/harness/renderer_debug_command.odin`: the override parser.
- `src/harness/analysis.odin`: the analysis config, summary, and period.
- `src/harness/analysis_report.odin`: the analysis file.
- `src/harness/analysis_images.odin`: PNG decode and the analysis maps.
- `src/harness/check_capture.odin`: capture checks and the check window.
- `src/harness/check_analysis.odin`: analysis check fields.
- `src/harness/check_objects.odin`: placed-object check fields.
- `src/harness/report.odin`: the run report and summary types.
- `src/harness/report_setup.odin`: the run's setup block.
- `src/harness/build_info.odin`: the injected revision and dirty flag.
- `src/harness/run_summary.odin`: the `--verbose` run summary.
- `src/digest/digest.odin`: FNV-1a for the state and render digests.
- `src/perf/`: the perf sample, ring, statistics, and text formatting.
- `src/renderer/timing.odin`: the timestamp pools, the pass boundaries, and the
  read.
- `src/renderer/debug.odin`: the debug gate, overrides, and shadow phase.
- `src/renderer/lights.odin`: the point-light type, instance masks, synthetic
  lights, and upload.
- `src/renderer/state.odin`: the renderer report and setup.
- `src/renderer/render_digest.odin`: the render digest.
- `src/renderer/sky_draw.odin`: the sky pass, after the lit pass.
- `src/renderer/capture.odin`: the target copy and RGBA f32 decode.
- `src/frame/`: shared scene assembly and draw for the game and the harness.
- `src/game/prefabs.odin`: the placed-object body modes, prefab catalog, and
  starting crate layout.
- `src/game/objects.odin`: the placed-object list and the create, remove, move,
  yaw, convert, and reset API.
- `src/game/spawn_pop.odin`: the pop curve, the spawn age and scale, the visual
  box, and the settled restore path.
- `src/game/palette.odin`: the object palette state and the debug palette API.
- `src/game/placement.odin`: the armed placement state, the ray anchor, the
  ghost transform, the height and yaw steps, the snap, and place.
- `src/game/oriented_box.odin`: the oriented box corners and the AABB half
  extents.
- `src/game/debug_draw_ghost.odin`: the ghost outline, footprint, and height
  guide lines.
- `src/game/box_body.odin`: the one Box3D box-body creation path for the static
  arena and the placed objects.
- `src/game/menu.odin`: the menu rows, settings text, and control list.
- `src/game/menu_input.odin`: the pure slider drag state machine.
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
  `scenarios/taa-motion.json`, `scenarios/settings-menu.json`,
  `scenarios/window-settings.json`, `scenarios/renderer-state.json`,
  `scenarios/renderer-reset.json`, `scenarios/capture-targets.json`,
  `scenarios/renderer-debug.json`, `scenarios/renderer-debug-converge.json`,
  `scenarios/renderer-debug-jitter.json`, `scenarios/capture-free.json`,
  `scenarios/editor-ghost.json`, `scenarios/debug-pop.json`, and
  `scenarios/perf-lamps.json`.

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

`make smoke` runs the smoke scenario with the normal agent and needs no
validation layer. `make shot SCENARIO=...` runs one scenario and prints the
capture paths. `make ui` runs the four UI scenarios into `runs/ui-*`.

`make validate` builds the agent with validation enabled and runs
`scenarios/smoke.json` offscreen, then with `--present` when a display is
available. Both validation targets accept `SCENARIO=...` (one name, one path,
or a list) and `AGENT_FLAGS=...`; each scenario still gets its own output
directory. `make validate-offscreen` is the headless target: it runs `smoke`,
`type-weight`, `settings-menu`, `ui`, `shadow-angle`, and `perf-crates` offscreen,
each into its own output directory, and stops on the first failure. Both
validation targets accept `SCENARIO=...` (one path, one stem, or a list) and
`AGENT_FLAGS=...`:

```sh
make validate-offscreen SCENARIO=renderer-debug AGENT_FLAGS=--debug-renderer
```

`make shot SCENARIO=scenarios/ui.json` builds, runs, and prints the capture
paths. `make ui` runs the four UI scenarios into `runs/ui-*`. `make smoke` is the
short end-to-end gate and needs no validation layers.
`make validate-demo` runs the game with validation enabled.

## Keep the harness current

The harness is part of the product. When you add or change a feature, update the
harness in the same change. Do not leave the automation behind the game.

- New simulation input: add it to `game.Input_Snapshot`, the `input` command,
  and `tests/harness`.
- New state field: add it to `State`, `state_build`, the table in
  `state_fields.odin` and its leaf resolver, the report schema, and the docs. Add it to `state_digest` only when it changes the
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
  analysis report, the docs, and a unit test. `analysis_bands.odin` owns the
  flat-run metric.
- New capture block: add it to `Capture_Command`, `Capture_Request`,
  `Pending_Capture`, the backend, `capture_field`, the docs, and a synthetic
  image test. A block that writes no file must still be readable by a check. A check must read the same value
  the file records.
- New renderer debug override: add it to `Renderer_Debug`, `set_renderer_debug`,
  the resolve push constants and shader, `renderer_debug_fields`, the renderer
  state, the docs, and the gate test. Do not make it reachable without the
  gate.
- New point light input: add it to `Light`, the light buffer upload, the scene
  shader loop, the render digest, and `tests/renderer/lights.odin`.
- New scenario key or run option: add it to `scenario_parse` and its allowed
  key set, the CLI parser, the README, this page, and a parser test. A new
  top-level key also joins `scenario_build` and the inheritance merge.
- New state object: one row in `STATE_FIELDS` in `src/harness/state_fields.odin`
  and the sub-resolver case. A flat field is one case; an indexed object is one
  resolver.
- New check namespace: add it to `check_field` and to the resolver table.
- Render state is not simulation state: render fields do not go into
  `state_digest`. Put pipeline state in the render digest and `Renderer_State`.
  A scene input such as the sun stays at the top level and feeds the render
  digest.
- New renderer pass or target: keep it behind `Target` or `Frame_View`. Add an
  offscreen test when the pass must match the game.
- New screenshot or evidence path: update the README and this page.
- New prefab: add it to `Prefab_Id` and `PREFABS` in `src/game/prefabs.odin`,
  including its `short_name` for the palette card. The renderer, the game API,
  and the harness read the catalog generically.
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
