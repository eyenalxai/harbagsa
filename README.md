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
- A C compiler for the vendored Box3D library
- `make` (optional)

## Run

```sh
make run
```

`make run` builds the Box3D archive, compiles every shader with `glslc`, builds
the demo, and starts it. The SPIR-V lives in `build/shaders/` and is embedded
into the binary.

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
- `Esc`: open the settings menu. The menu pauses the game and releases the
  cursor. Press `Esc` again to resume.

### Settings menu

`Esc` opens a centered settings menu. The menu pauses the simulation and shows
the active control list. It changes the sprint, crouch, and prone input modes
between Hold and Toggle.

- `Up` / `Down`: select a row.
- `Left` / `Right`: change the selected input mode.
- `Enter`: apply the selected row. `Resume` closes the menu.
- `Esc`: close the menu.

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
The settings menu shows the control list. The window is resizable.

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
  frames/frame_0000.png
  frames/frame_0090.png
  frames/frame_0121.png
  run.log
```

`report.json` holds the pass/fail result, the final state, absolute screenshot
paths, checks, and the state digest. `state.json` holds the final state alone.
`run.log` holds the log lines. Standard output is one JSON summary.

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

The harness view starts with the HUD off, the debug draw off, and the capture
hint off. A scenario captures the final frame by default. `capture` adds more
frames, and `"capture": []` turns rendering off for that scenario.

### Scenario format

```json
{
  "view": {"hud": false, "debug": false, "hint": false},
  "steps": [
    {"frames": 90, "forward": 1, "look": [220, 0]},
    {"frames": 1, "jump": true},
    {"frames": 30, "forward": 1}
  ],
  "capture": [0, 90, 121],
  "checks": [
    {"field": "crates.0.position.z", "op": "lt", "value": 7.5}
  ]
}
```

One step means one fixed `SIMULATION_STEP`. `look` applies once before the
step. `forward`, `right`, and `jump` persist; `jump` is an edge on the first
frame of its block. Capture frames are zero-based frame numbers. Check operators
are `eq`, `ne`, `lt`, `le`, `gt`, and `ge`. Check fields use the `state.json`
shape, for example `player.position.y`, `player.grounded`, `crates.0.position.z`,
`crates.count`, `settings.sprint_mode`, or `menu.open`.

A scenario may use `commands` instead of `steps`:

```json
{
  "commands": [
    {"cmd": "view", "hud": false},
    {"cmd": "input", "forward": 1},
    {"cmd": "step", "frames": 90},
    {"cmd": "capture", "name": "after-walk"}
  ]
}
```

A `commands` scenario runs verbatim. It does not add a default capture, so
include a `capture` command when you want a PNG.

### Commands

The batch runner and the live session share one command set:

- `{"cmd": "reset"}`: fresh simulation. Crates return to spawn, the settings
  return to their defaults, and the menu closes.
- `{"cmd": "look", "dx": 220, "dy": 0}`: pixel look delta through the game
  sensitivity and pitch clamp.
- `{"cmd": "face", "yaw": 0, "pitch": 0}`: set the player view directly.
- `{"cmd": "input", "forward": 1, "right": 0, "jump": false}`: set persistent
  input. Omitted fields keep their value.
- `{"cmd": "step", "frames": 60}`: fixed steps with no wall clock. A step is an
  error while the menu is open.
- `{"cmd": "state"}`: player, eye, velocity, yaw, pitch, grounded, crates,
  settings, menu, frame, and digest.
- `{"cmd": "capture", "name": "shot", "frame": 90, "alpha": 1.0}`: write a PNG.
  `frame` is optional. A past frame is an error; a future frame queues.
- `{"cmd": "camera", "position": [0, 2, 12], "yaw": 0, "pitch": 0}`: inspection
  camera. It does not move the player. `{"cmd": "camera", "clear": true}` drops
  the override.
- `{"cmd": "view", "hud": true, "debug": false, "hint": false}`: toggle the HUD,
  the debug draw, and the capture hint.
- `{"cmd": "menu", "open": true, "select": 1, "activate": true}`: open or close
  the settings menu, select a row, and activate the selected row. `select` is
  zero-based and needs an open menu. `activate` also needs an open menu. Omitted
  fields keep the state. An open menu renders even when `hud` is off.
- `{"cmd": "check", "field": "player.position.y", "op": "gt", "value": 0}`:
  evaluate a predicate now.
- `{"cmd": "record", "path": "scenarios/walk.json"}`: start recording. Send
  `{"cmd": "record"}` to stop and write the scenario.
- `{"cmd": "replay", "path": "scenarios/walk.json"}`: reset and run a scenario.
- `{"cmd": "quit"}`: stop the session.

Unknown keys, wrong types, and out-of-range values are per-command errors. The
session stays usable.

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

### Screenshot workflow

```sh
make build
./bin/harbagsa-agent run scenarios/smoke.json
```

Read `runs/smoke/report.json` and use the absolute paths in `screenshots`. The
PNG is RGBA, sRGB, and `1280x720` by default. The repository samples are
`docs/evidence/harness-smoke.png`, `docs/evidence/present-window.png`, and
`docs/evidence/settings-menu.png`. To capture the owner's real window instead:

```sh
./bin/harbagsa-agent run scenarios/smoke.json --present --out runs/present
```

The compositor may resize the window. The PNG has the actual swapchain size. It
matches an offscreen capture at the same size when both frames share the same
TAA history; the first frame always matches.

`scenarios/taa-static.json` captures 25 consecutive frames from a static camera.
Use it to check TAA edge stability without a window. The first frames converge;
compare later frames to see the steady-state ripple.

`scenarios/settings-menu.json` opens the settings menu, captures it, changes the
crouch input mode, closes the menu, and checks the saved state.

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
runs the physics, simulation, frame, harness, and renderer tests headless. The
offscreen render test logs a skip when no Vulkan device is available.

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
