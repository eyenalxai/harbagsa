# harbagsa

An Odin project.

## Requirements

- [Odin](https://odin-lang.org/) tested with `dev-2026-10`
- `make` (optional)

## Run

```sh
odin run .
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

## Clean

```sh
make clean
```
