# harbagsa

A first-person movement demo. The player walks, sprints, crouches, crawls,
jumps, dives, slides, and mantles in a fixed arena with stairs, ramps, tunnels,
mantle walls, a dive platform, a closed ceiling, pushable crates, and three
dynamic coloured lamps.
SDL3 provides the window and input, Vulkan 1.3 draws the scene, and Box3D runs
physics. Direct point lights, hard ray-query shadows, one-bounce probe GI, and
emissive boxes shade every frame. An unlit surface is black. There is no
ambient floor, directional light, background pass, shadow map, or baked global
illumination.

## Requirements

- [Odin](https://odin-lang.org/) tested with `dev-2026-10`
- SDL3 and a Vulkan 1.3 driver with the Vulkan loader
- A GPU with Vulkan 1.3 dynamic rendering, shader demote, and the ray-query
  extensions (`VK_KHR_acceleration_structure`, `VK_KHR_ray_query`, and
  `VK_KHR_deferred_host_operations`)
- `glslc` from shaderc to compile the GLSL shaders
- `spirv-val` from SPIRV-Tools to validate the compiled shaders (optional)
- A C and C++ compiler for the vendored Box3D, FreeType, and HarfBuzz libraries
- `python3` for reference checks and the perf A/B report
- `make` (optional)

## Run

```sh
make run
```

The first build compiles the vendored libraries and takes about a minute. Later
builds reuse them. SPIR-V lives in `build/shaders/` and is embedded into the
binary.

## Controls

- `WASD`: move relative to the view.
- Mouse: look. Left click captures the cursor.
- `Left Shift`: sprint. The settings menu switches Hold and Toggle.
- `Space`: jump. Hold it while moving toward a ledge to mantle.
- `C`: crouch. While sprinting, start a crouch slide.
- `Z`: prone. Crawl while prone. Dive in the air or from a sprint.
- `R`: return the player to spawn.
- `Shift+R`: reset placed objects and the player.
- `F1`: toggle physics debug draw.
- `F2`: toggle debug mode.
- `F3`: toggle temporal anti-aliasing (TAA).
- `F4`: toggle the perf overlay.
- `F5`: write a repro scenario to `runs/repro/`.
- `Esc`: open or close the settings menu.

Movement follows the walkable ground plane. A straight climb keeps stance speed
along the slope, so horizontal speed drops by the slope cosine. Step-ups and
step-downs use a short camera lag.

### Settings menu

The menu pauses the simulation and releases the cursor. It changes window mode,
display, resolution, type weight, and sprint, crouch, and prone input modes.
`Up` and `Down` select a row. `Left`, `Right`, and `Enter` change it. `Resume`
closes the menu. The Type weight track also accepts a drag.

Window mode is Borderless or Windowed. Borderless uses the selected display's
desktop size. Windowed uses the chosen resolution and a normal title bar. The
selected display supplies the resolution list. Display and mode choices last for
the current run.

### Debug mode

`F2` replaces the player with a free-fly camera and enables scene editing.

- `WASD`: fly horizontally. Mouse: look.
- `Space` / `Ctrl`: fly up / down.
- `Tab`: open or close the object palette.
- Left click: select and drag an object, or place the armed prefab.
- Wheel: raise or lower the ghost or selected object.
- `Q` / `E`: rotate in 15 degree steps. Hold `Shift` for 45 degree steps.
- `G`: toggle 0.25 m grid snap.
- `M`: flip a non-lamp target between static and dynamic. A lamp always stays
  dynamic.
- `Ctrl+D`: duplicate the selected object.
- `Delete` or `X`: remove it.
- `Ctrl+Z` / `Ctrl+Shift+Z`: undo / redo.
- `C`: cycle lamp colour through warm, cool, red, green, and blue.
- `[` / `]`: change lamp intensity from 0.2 to 4.0.
- `,` / `.`: change lamp range from 2 to 20 m.
- `R`: reset the player and camera.
- `Shift+R`: reset placed objects and the player.
- `F5`: write a scene snapshot.
- `F2`: leave debug mode.

The palette shows eleven box prefabs. Lamp, Light panel, and Beacon carry point
lights and always use a dynamic body. The preview and inspector show colour,
intensity, and range. Every active lamp enters the light budget. The starting
arena holds one of each lamp prefab, so its first view shows warm, cool, and red
pools on the closed shell.

### Perf overlay

The summary shows FPS, frame interval, CPU frame time, p95 interval, spike
count, and GPU total with the costliest pass. The pass row shows TLAS, cluster
assignment, probe field, depth prepass, lit scene, TAA resolve, and overlay
times. GPU numbers belong to the last completed frame. A device without
timestamp support shows CPU numbers only.

## Agent harness

`bin/harbagsa-agent` drives the simulation and writes screenshots without a
window or compositor. Read `docs/agents/harness.md` for the operational guide.
Run the schema first:

```sh
make build
./bin/harbagsa-agent schema
./bin/harbagsa-agent run scenarios/smoke.json
```

Useful loops:

```sh
make test-simulation
make quick
make shot SCENARIO=lighting OUT=runs/lighting
./bin/harbagsa-agent suite lighting --out runs/lighting
./bin/harbagsa-agent checks runs/lighting
```

A run writes `report.json`, `state.json`, `run.log`, and any requested frames
under `runs/<scenario-stem>/`. Use `--out DIR` to choose another directory and
`--tag NAME` to keep repeated runs beside each other. Exit code 0 means every
blocking check passed. Exit 1 means a check failed, 2 means bad input, and 3
means renderer or backend initialization failed.

Common options:

- `--size WxH`: capture extent.
- `--no-render`: simulation and checks only.
- `--present`: use the real SDL window.
- `--debug-renderer`: accept gated renderer overrides.
- `--no-analysis`: skip image analysis.
- `--summary` and `--verbose`: print run detail.
- `--timeout SECONDS`: bound wall time.
- `--param NAME=VALUE`: override a scenario parameter. Comma values run a sweep.
- `run -`: read a scenario from standard input.

### Scenario format

```json
{
  "view": {"hud": false, "debug": false, "hint": false, "perf": false},
  "commands": [
    {"cmd": "place", "prefab": "Lamp", "position": [0, 1, 6], "name": "key-lamp"},
    {"cmd": "settle", "frames": 40},
    {"cmd": "capture", "name": "lit"},
    {"cmd": "check", "field": "objects.key-lamp.light.active", "op": "eq", "value": true}
  ]
}
```

A scenario can declare `size`, `requires`, `renderer_debug`, `parameters`,
`analysis`, and `note`. `extends` merges a base scenario and lets the child win.
Every angle uses degrees and ends in `_deg`. Positions and ranges are metres.
One `step` or `settle` frame is one fixed simulation step.

Check operators are `eq`, `ne`, `lt`, `le`, `gt`, and `ge`. A check compares
with `value` or `other`. It can read state, captures, and image analysis. Named
capture paths include `capture.named.<name>.*`.

### Commands

- `reset`: restore the simulation.
- `look`: apply a pixel look delta.
- `face`: set player yaw and pitch.
- `input`: set persistent movement input.
- `step`: advance fixed frames.
- `settle`: render fixed frames without a capture, or wait for convergence.
- `state`: report current state.
- `capture`: render and write one output.
- `captures`: write several outputs from one frame.
- `camera`: set or clear an inspection camera.
- `view`: set HUD, debug draw, capture hint, and perf flags.
- `debug_mode`: enter or leave debug mode.
- `editor`: drive the palette, placement, object edits, light settings, and history.
- `menu`: drive the settings menu.
- `check`: evaluate one predicate.
- `record`: start or stop a recording.
- `replay`: reset and run a recorded scenario.
- `repro`: write the live view as a scene snapshot.
- `perf`: measure frames and optional traces.
- `renderer_debug`: change gated renderer inputs. A field set to `null` resets it.
- `displays`: replace or clear the scripted display list.
- `rows`: dump HUD and menu rows.
- `scene`: apply exact camera, objects, settings, view, displays, and renderer debug blocks.
- `place`: create one object without entering debug mode.
- `remove`: delete one object by id or name.
- `get`: resolve one state, capture, or analysis field.
- `quit`: close a live session.

Use `./bin/harbagsa-agent help <command>` for fields. The live session accepts
one JSON command per line on standard input or a Unix socket.

### Captures and checks

Capture targets are `color`, `velocity`, `history`, `depth`, and `scene_color`.
Formats are `png`, `float`, `raw`, `stats`, and `profile`. Color defaults to PNG;
intermediate targets default to stats. A stats capture accepts `region`,
`histogram`, `steps`, `color_key`, and `coverage`. A color capture also accepts
`crop` and `profile`.

`analysis.json` holds pair deltas, stability, dominant period, and banding data.
`harbagsa-agent compare A B --delta` writes a before/after/delta panel. Keep PNGs
under `runs/`; never commit them.

`boxes` prints immutable arena geometry. `checks` prints every gate and margin.
`schema` prints commands, fields, units, capture shapes, and state paths.

### Suites and performance

Suite manifests live in `suites/`: `fast`, `lighting`, `renderer`, `offscreen`,
and `ui`. Run one with `harbagsa-agent suite <name>`. Use `--list`, `--only`,
`--skip`, or `--fail-fast` to select work.

`scenarios/perf.json` measures the default view. `scenarios/perf-lamps.json`
measures direct point lights. `scenarios/perf-shadows.json` measures the paired
shadow cost at 96 lights and 1080p. `scenarios/perf-gi.json` measures the paired
GI cost at the same scale. `scenarios/perf-crates.json` measures many placed
objects. `tools/ab.sh` and `harbagsa-agent ab` compare two builds.

### Lighting and visual evidence

`scenarios/closed-arena.json` checks the shell count, the ceiling, and a ceiling
view with no visible background. `scenarios/initial-lamps.json` checks the three
starting lamps, their dynamic bodies, and a moved light. `scenarios/lighting.json`
checks a black lamp-free view and the direct lamp response.
`scenarios/light-move.json` checks that a moved lamp changes the captured light
field and render digest. `scenarios/shadows.json` checks a blocked surface and
the paired shadow toggle. `scenarios/shadow-move.json` checks that a moved lamp
moves its shadow. `scenarios/lamp-wall-plane.json` checks
placement and a smooth wall gradient. `scenarios/banding.json` checks output
dither on that gradient. `scenarios/gi.json` pairs indirect light on and off;
`scenarios/gi-dark.json` keeps a lamp-free view black; `scenarios/gi-move.json`
checks a moved lamp's bounce; `scenarios/gi-sealed.json` checks that a sealed
wall stops the bounce.

For a visible change, capture before and after with the same scenario and
command. Put numeric assertions in the scenario. Point at the run directory as
evidence; do not commit images.
