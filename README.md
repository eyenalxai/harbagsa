# harbagsa

A third-person movement demo. The player controls an eight-legged spider that
walks, sprints, and jumps through a fixed arena with stairs, ramps, tunnels,
tall west walls, a high platform, a closed ceiling, pushable crates, and three
coloured lamps. Two-bone inverse kinematics plant the feet on the floor,
and a spring-arm camera orbits behind the body.
SDL3 provides the window and input, Vulkan 1.3 draws the scene, and Box3D runs
physics. Direct point lights, hard ray-query shadows, a baked one-bounce
indirect pass, and emissive boxes shade every frame. Static boxes read a lightmap
atlas; dynamic boxes read a baked probe volume. An unlit surface is black.
There is no ambient floor, directional light, background pass, shadow map, or
dynamic global illumination.

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

## Build and check

```sh
make build
make check
make bake
```

`make check` compiles every package, enforces the 400-line file limit, and
validates the shaders. It is a build check, not a test gate.
`make check-references` checks the documentation links. `make bake` writes
`build/bake/arena.hbake` for the runtime; the artifact is generated, never
committed. The renderer reports a missing artifact in `state.renderer.bake`.
The harness `bake reload` and `bake publish` commands replace the bound artifact
without a restart.

## Run

```sh
make run
```

The first build compiles the vendored libraries and takes about a minute. Later
builds reuse them. SPIR-V lives in `build/shaders/` and is embedded into the
binary.

## Controls

- `WASD`: move relative to the camera. The spider turns toward the movement.
- Mouse: orbit the camera. Left click captures the cursor.
- `Left Shift`: sprint. The settings menu switches Hold and Toggle.
- `Space`: jump.
- `R`: return the player to spawn.
- `Shift+R`: reset placed objects and the player.
- `F1`: toggle physics debug draw.
- `F2`: toggle debug mode.
- `F3`: toggle temporal anti-aliasing (TAA).
- `F4`: toggle the perf overlay.
- `F5`: write a repro scenario to `runs/repro/`.
- `Esc`: open or close the settings menu.

Movement follows the walkable ground plane. A straight climb keeps the gait
speed along the slope, so horizontal speed drops by the slope cosine. The camera
holds a fixed distance until a wall, floor, or prop shortens the arm. Step-ups
and step-downs use a short camera lag.

Each leg has a hip, a femur, and a tibia. The solver bends the knee up and out.
A planted foot stays in the world; a leg swings to a new ground point when its
foot drifts past the step trigger. Even legs and odd legs step in turns, and
the eight feet tuck under the body in the air.

### Settings menu

The menu pauses the simulation and releases the cursor. It changes window mode,
display, resolution, type weight, and the sprint input mode.
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
- `M`: flip the body between static and dynamic. On a lamp this also switches
  between a static fixture and a dynamic lamp.
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
lights. A new lamp defaults to a dynamic lamp; switching its body to static
makes it a static fixture and adds its bounce to the next bake. The preview and
inspector show the kind, colour, intensity, and range. Every active lamp enters
the light budget. The starting arena holds one of each lamp prefab as a static
fixture, so its first view shows warm, cool, and red pools on the closed shell.

### Perf overlay

The summary shows FPS, frame interval, CPU frame time, p95 interval, spike
count, and GPU total with the costliest pass. The pass row shows TLAS, cluster
assignment, depth prepass, lit scene, TAA resolve, and overlay
times. GPU numbers belong to the last completed frame. A device without
timestamp support shows CPU numbers only.

## Agent harness

`bin/harbagsa-agent` drives the simulation and writes screenshots without a
window or compositor. Read `docs/agents/harness.md` for the operational guide.
Run the schema first:

```sh
make build
./bin/harbagsa-agent schema
./bin/harbagsa-agent run scenarios/lamp-threshold.json
```

Useful loops:

```sh
make shot SCENARIO=lamp-threshold OUT=runs/lamp-threshold
./bin/harbagsa-agent run scenarios/perf.json --out runs/perf
```

A run writes `report.json`, `state.json`, `run.log`, and any requested frames
under `runs/<scenario-stem>/`. Use `--out DIR` to choose another directory and
`--tag NAME` to keep repeated runs beside each other. Exit code 0 means the run
completed. Exit 1 means a command failed, 2 means bad input, and 3 means
renderer or backend initialization failed.

Common options:

- `--size WxH`: capture extent.
- `--no-render`: simulation only.
- `--present`: use the real SDL window.
- `--debug-renderer`: accept gated renderer overrides.
- `--summary` and `--verbose`: print run detail.
- `--timeout SECONDS`: bound wall time.
- `--bake PATH`: load another `.hbake` artifact. The default is
  `build/bake/arena.hbake`; a missing file shows `missing` in
  `state.renderer.bake`.
- `--param NAME=VALUE`: override a scenario parameter. Comma values run a sweep.
- `run -`: read a scenario from standard input.

### Scenario format

```json
{
  "view": {"hud": false, "debug": false, "hint": false, "perf": false},
  "commands": [
    {"cmd": "place", "prefab": "Lamp", "position": [0, 1, 6], "name": "key-lamp"},
    {"cmd": "settle", "frames": 40},
    {"cmd": "capture", "name": "lit"}
  ]
}
```

A scenario can declare `size`, `requires`, `renderer_debug`, `parameters`, and
`note`. `extends` merges a base scenario and lets the child win. Every angle uses
degrees and ends in `_deg`. Positions and ranges are metres. One `step` or
`settle` frame is one fixed simulation step.

### Commands

- `reset`: restore the simulation.
- `look`: apply a pixel look delta.
- `face`: set the camera yaw and pitch.
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
- `bake`: report, reload, or publish the static bake. `action` is `status`,
  `reload`, or `publish`.
- `get`: resolve one state or capture field.
- `quit`: close a live session.

Use `./bin/harbagsa-agent help <command>` for fields. The live session accepts
one JSON command per line on standard input or a Unix socket.

### Captures

Capture targets are `color`, `velocity`, `history`, `depth`, and `scene_color`.
Formats are `png`, `float`, `raw`, `stats`, and `profile`. Color defaults to PNG;
intermediate targets default to stats. A stats capture accepts `region`,
`histogram`, `steps`, `color_key`, and `coverage`. A color capture also accepts
`crop` and `profile`.

`harbagsa-agent compare A B --delta` writes a before/after/delta panel. Keep PNGs
under `runs/`; never commit them.

`boxes` prints immutable arena geometry. `schema` prints commands, fields, units,
capture shapes, and state paths.

### Performance

`scenarios/perf.json` measures the default view. `scenarios/perf-arena.json`
measures the arena from above. `tools/ab.sh` and `harbagsa-agent ab` compare two
builds.

### Visual evidence

`scenarios/lamp-threshold.json` captures a lamp wall plane for visual comparison.
For a visible change, capture before and after with the same scenario and
command. Point at the run directory as evidence; do not commit images.
