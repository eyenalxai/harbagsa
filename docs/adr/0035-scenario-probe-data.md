# Scenario-owned probe data

Builds on [ADR 0034](0034-ddgi-arena-coverage.md). The room volume, the update,
the gather, and the blend stay.

## Context

ADR 0034 put one sealed-pair volume per room in the production probe list. Every
run then allocated 96 probes for a test room that most scenarios do not build.
A scenario could not add or remove a probe volume, so a test scene depended on
permanent data and on placement order. The perimeter strips also stopped 0.05 m
inside the room's outer wall face, which left the wall thickness, the door
threshold, and a wall end cap outside every volume. The gather shader hid the
one-ULP case with a 1 mm bound, but the layout had no diagnostic that could show
the remaining strips.

## Decision

- Remove the sealed pair from `PROBE_VOLUMES`. The production scene is six
  volumes: the room, the roof, and four perimeter strips.
- Add a `probe_volumes` block to the `scene` command. It adds interior volumes
  after the room volume and before the arena strips. A volume carries a name,
  a minimum corner, a spacing, and a 3D count.
- `scenarios/ddgi-sealed.json` supplies its two pair volumes and names every
  placed object. The default scene stays at six volumes; ADR 0036 raises the
  count from 537 to 2205, and the sealed run from 633 to 2301.
- The perimeter strips meet the room's inner faces instead of stopping inside
  the outer face. The room volume is first, so it still owns the inner face and
  every interior point; the strips own the wall thickness, the door threshold,
  and the open floor. The north strip grows to 2.9 m spacing so it still reaches
  the arena wall.
- Add `harbagsa-agent probes`. It prints the effective layout and the owner of a
  point, and `--coverage` samples visible static-box faces and reports the
  points that no volume owns. It reads a scenario's `scene` block without a
  renderer.

## Why

- Test data belongs to the test. A run that does not build the sealed pair
  should not pay for its probes or depend on its volume order.
- The scene block is already the declarative setup path. It carries camera,
  sun, objects, settings, view, displays, and renderer debug; probe volumes were
  the one missing scene input.
- The inner-face bounds are safe because the sampler takes the first match and
  the room volume is first. A test can check the ordering without a renderer.
- A coverage command is cheaper than a reference run. It would have shown the
  north-wall gap and the missing door threshold before any capture.

## Consequences

- `scenarios/ddgi-arena.json` and `scenarios/ddgi.json` now check six volumes;
  ADR 0036 raises the count to 2205. `scenarios/ddgi-sealed.json` checks eight
  and 2301.
- `scenarios/ddgi-sealed.json` owns the pair layout and uses names instead of
  `objects.14` and `remove id 5`.
- The perimeter probe centres move slightly toward the room. ADR 0036 changes
  the grid and the count to 2205 and 2301. The path-traced reference must be
  re-run after a layout change; it is the energy gate, not this decision.
- The coverage command excludes hidden faces, floor-on-floor faces, and the
  0.25 m band at a face edge. A non-zero count is a real surface with no probe,
  not a boundary artifact.
- The probe map and the gather read the same 1 mm high-bound epsilon. A change
  to one must change the other.
