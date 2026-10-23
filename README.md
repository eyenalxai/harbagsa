# harbagsa

A first-person walking demo. The player walks, looks, and jumps in a fixed
arena with pushable crates. SDL3 provides the window and input, raw Vulkan 1.3
draws the scene, and Box3D runs the physics.

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

- `WASD`: walk relative to the view.
- Mouse: look. Left click captures the cursor.
- `Space`: jump. The player must be grounded.
- `R`: return the player to spawn.
- `F1`: toggle the debug draw.
- `Esc`: release the cursor capture.

The HUD shows the player speed, grounded state, position, and this control list.
The window is resizable.

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
library package. `make test` runs the physics and simulation tests headless.

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
