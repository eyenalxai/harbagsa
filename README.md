# harbagsa

An Odin project.

## Requirements

- [Odin](https://odin-lang.org/) tested with `dev-2026-10`
- SDL3 and the Vulkan loader (Vulkan 1.3 or newer)
- `make` (optional)

## Run

```sh
odin run . -collection:src=src -collection:libs=vendor
```

Or:

```sh
make run
```

## Build

```sh
make build
./bin/harbagsa
```

## Checks

Odin has no separate lint tool. The compiler's `-vet` checks are the linter,
and `make check` runs the strictest set this compiler supports.

```sh
make check
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
