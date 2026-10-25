# Unbounded scene capacity

## Context

The scene had four fixed caps: 128 placed objects, 256 rendered boxes, 8 active
point lights, and 8 uploaded lights. The game also sorted lamps by camera
distance and kept the nearest eight. A scene past any cap dropped content
without an error the player could see. The target is interiors with many lights,
so the caps are the first thing that breaks.

## Decision

- `Simulation.objects` is a dynamic array. `object_count` is `len`.
- `frame.Scratch` holds dynamic box and light arrays.
- The renderer object and light buffers start at a capacity hint and double when
  the scene outgrows them. Growth reallocates the mapped buffers and rewrites the
  descriptor writes.
- The TLAS instance buffer and acceleration structure grow the same way.
- `TAA.prev_models` grows with the box count.
- Every active lamp is collected. The nearest-eight sort is gone.
- Synthetic debug lights are generated for any count.

These stay, because they are protocol or hardware bounds rather than scene
content: display and mode counts from the OS, capture target count, overlay
vertex capacity, collision plane count, per-frame key edges, and the harness
protocol limits.

## Why

- A silent drop is a correctness bug. A scene that accepts 300 crates must draw
  300 crates.
- The count is known at upload time, so growth is a rare event, not a per-frame
  check on every buffer.
- A fixed cap chosen for the old arena would be wrong for a building.

## Considered Options

- **Keep the caps and fail loudly.** Simple, but it moves the limit to the level
  author and the player, and the target scene needs more.
- **Allocate a very large fixed buffer.** It trades one arbitrary limit for a
  larger one and pays the memory on every run.
- **Grow only the current frame's buffer.** The other frames would still have
  the old capacity. All frames grow together.
- **Grow without a device wait.** A previous frame can still read the buffer.
  Growth waits for the device; it is rare.

## Consequences

- Growth stalls the device. The capacities double, so a scene pays it a
  logarithmic number of times.
- `Scene.object_capacity` and `Scene.light_capacity` are the live sizes. The
  upload paths check them and name the count on failure.
- `Acceleration.capacity` is the TLAS instance capacity.
- Tests cover past the old caps: 300 objects, 96 lights, and a 300-box frame.
- `scenarios/capacity.json` renders 32 and 64 synthetic lights and checks the
  reported count.
- The next step is clustered forward+, which uses the now-unbounded light list.
