# harbagsa

A first-person movement demo. The player walks, sprints, crouches, crawls,
jumps, dives, slides, and mantles in a fixed arena with stairs, ramps, tunnels,
mantle walls, a dive platform, and pushable crates. SDL3 provides the window and
input, raw Vulkan 1.3 draws the scene, and Box3D runs the physics. A fixed
directional sun casts soft shadows from the walls and crates.

## Requirements

- [Odin](https://odin-lang.org/) tested with `dev-2026-10`
- SDL3 and a Vulkan 1.3 driver with the Vulkan loader
- `glslc` from shaderc to compile the GLSL shaders
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
- Left `Shift`: sprint. Hold by default; the mode is a code constant.
- `Space`: jump. In the air, try to mantle a ledge. Jump input buffers before landing.
- `C`: crouch. Toggle by default. While sprinting, it starts a crouch slide.
- `Z`: prone. Toggle by default. Crawl while prone. Dive in the air or from a sprint.
- `R`: return the player to spawn.
- `Shift+R`: reset the crates, the sun, and the player.
- `F1`: toggle the debug draw.
- `F2`: toggle debug mode.
- `Esc`: release the cursor capture.

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

The HUD shows the stance, gait, horizontal speed, grounded state, movement
state, and position, or the debug mode selection, crate count, and sun angles.
It also shows the control list. The window is resizable.

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
make test
```

`make check` runs the strict compiler checks on the main program and every
library package. `make test` runs the physics, simulation, and renderer math
tests headless.

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
them. To enable them when `VK_LAYER_KHRONOS_validation` is installed:

```sh
odin run . -collection:src=src -collection:libs=vendor -define:ENABLE_VALIDATION_LAYERS=true
```

## Clean

```sh
make clean
```
