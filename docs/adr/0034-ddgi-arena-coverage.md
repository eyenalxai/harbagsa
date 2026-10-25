# DDGI arena and roof coverage

Builds on [ADR 0031](0031-ddgi-probe-volumes.md) and
[ADR 0033](0033-ddgi-irradiance-and-gather.md). The update, the gather, and the
room volume stay.

## Context

The scene supplied one probe volume: the room, its lane network, and the
chamber. `probe_indirect` returns zero when no volume contains the surface, so
the open arena had no indirect term and no sky term. The `outside` capture from
`scenarios/room-lighting.json` was 26.8 percent pure black in this tree, 33.5
percent in the issue report, and a crop of the room's shaded west face was 86.3
percent pure black.

The issue allowed either arena probe volumes or a sky irradiance term with
visibility.

## Decision

- Add five probe volumes after the room:
  - a roof volume over the room footprint at the room ceiling height, which
    lights the roof exterior;
  - a west, an east, a south, and a north perimeter volume over the open floor.
- The room volume stays first. The sampler picks the first volume that contains
  the surface point, so an interior surface never reads an arena probe.
- The perimeter bounds stop 0.05 m inside the room's outer wall face. An
  exterior face fragment that rounds outward still selects the arena volume,
  and the 0.3 m wall keeps the arena grid at least 0.25 m from the room's inner
  face.
- The open floor uses a 4 m cell. Sky fill is low frequency, so the coarse cell
  is enough and keeps the probe count down. The north strip is 5.5 m deep and
  needs two rows that both stay outside the room, which fixes its spacing at
  2.775 m.
- Every arena probe centre is outside the room footprint and inside the arena
  walls. A south centre is at z at most 1.55, a north centre at z at least 15.84,
  and a side centre at x at most 4.55 or at least 19.45.
- The room volume is unchanged. The update, the gather, and the blend are
  unchanged.

## Why

- The room volume first is what keeps the sky out of the room and the lane. The
  room images are unchanged by this decision: every `room-lighting` capture
  keeps its old mean, and the chamber stays at 0.26.
- A sky irradiance term with a per-pixel visibility ray would also work, but it
  adds a ray to every pixel and it double counts wherever the room probes
  already carry the sky through a door. The perimeter volumes keep one
  mechanism and one energy scale.
- A single arena-wide grid would put probes inside the room and inside the
  room's walls, and the arena would light the chamber through the wall.
- The roof volume is separate because the room volume stops at the ceiling
  underside. Without it the roof exterior is inside no volume, so a shaded roof
  would stay black.

## Consequences

- The scene supplies 6 volumes and 537 probes, up from 1 volume and 300 probes.
  The probe pass is 0.672 ms at 1280 x 720 with 64 synthetic lights, up from
  0.413 ms.
- The arena grid is coarse, so the perimeter walls show soft blotches at 4 m.
  The shaded room face moves from 0.16 to 151.27 mean green, and the whole
  outside frame falls from 26.8 to 0.30 percent pure black. The remaining black
  pixels are the room doorway, which is the unlit interior.
- `scenarios/ddgi-arena.json` is the coverage gate. It measures the room's
  shaded west face with a pure-black colour key and checks that the chamber
  stays at the dither floor with no sky depth pixel.
- `tests/frame/probe_volumes.odin` keeps the ordering and the bounds in the
  build without a renderer: the room volume is first, no arena probe centre is
  inside the room footprint, the arena bounds stop before the room interior, and
  every floor sample is covered.
- Probe classification and the sealed two-room leak pair remain out of scope.
  The leak pair is issue #322.
