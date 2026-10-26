# DDGI probe validity and contact

Supersedes the relocation rule in
[ADR 0031](0031-ddgi-probe-volumes.md), the gather rule in
[ADR 0033](0033-ddgi-irradiance-and-gather.md), and the arena density rule in
[ADR 0034](0034-ddgi-arena-coverage.md). Builds on
[ADR 0035](0035-scenario-probe-data.md): the production scene has six volumes,
and a test scene adds its own interior volumes.

## Context

The path-traced platform reference exposed three defects in one shaded face:

- a dark lobe with a hard hook, where a probe inside the platform had been
  pushed just outside a face and still received its full trilinear weight;
- dark specks along the tunnel corner, from probe texels the backface gate left
  at zero depth;
- a flat field and a missing contact at the base, because the 4 m cells and the
  y=2 and y=6 layers were larger than the platform.

The lobe stayed with AO off. With the sun below the horizon the lobe and the
specks stayed, so they were in `probe_indirect`. The direct term matched the
reference to 0.04 percent. The reference metrics were `p10` 0.82, `p90` 1.35,
median error 0.139, colour spread 0.058, and a mean 10 percent above the truth.

## Decision

- **A probe inside a box is invalid.** The CPU writes `0.0` in the probe
  position's `.w`. The ray pass skips it, the blend clears its atlas and skips
  it, and the gather skips it. The CPU does not move it out of the box.
- **A probe texel without depth data is not an occluder.** The gather skips a
  probe whose depth mean is zero. The backface gate is removed: a valid probe is
  outside every box, so its first hit is a front face. A backface ray contributes
  no radiance and its absolute distance still feeds the moments.
- **The Chebyshev test gets a distance bias.** The comparison is
  `distance > mean + max(0.05, spacing * 0.05)`, and the difference uses the
  biased mean. The cosine-weighted depth mean is shorter than the surface
  distance at a grazing angle, so the bias stops a visible probe being cut.
- **The weight crush is removed.** The trilinear floor is zero. A zero weight
  skips the probe, and the remaining weights are normalised. The crush turned a
  smooth trilinear blend into patches.
- **The arena grid resolves a crate and a platform.** The four perimeter strips
  use 2 m cells in x, y, and z, with the first layer at y=0.5. The west strip is
  2.065 m so its 13-cell width keeps a margin outside the west wall. The narrow
  east strip uses 1 m cells. The roof stays at 4 m, and the room and sealed-pair
  grids are unchanged. The strips keep ADR 0035's inner-face bounds.
- **The volume edge is inclusive across a float round trip.** The gather and the
  probe map add a 1 mm margin to both the low and high bounds, so the room wins
  a face one ULP below its inner bound, and a face on the far side of a wall does
  not fall out of the strip. The west strip's low x is -20.045; the west wall's
  inner face stays inside it.
- **The platform is a reference scene.** `scenarios/ddgi-platform.json` runs the
  path trace on the F5 dive-platform view. The tolerance is ratio 0.90–1.12,
  median error 0.10, colour 0.04, and zero coverage 1 percent.
  `make reference` runs it with the chamber and lane references.

## Why

- A probe is a position with a field. Moving it to the far side of a face does
  not make it a valid probe for that cell: the trilinear weight still favours it
  and the depth test cuts it. Validity is the state the gather needs.
- A zero depth is missing data, not a surface at distance zero. The old floor
  read it as a perfect occluder.
- The cosine kernel spans an 11.25° texel. On a face seen at a grazing angle its
  mean is shorter than the centre distance. A small bias costs little leak and
  removes the false silhouette cut.
- The crush was a leak-control heuristic. The reference says the field is too
  bright, not too leaky, and the hard patches come from the crush.
- A 4 m cell and a first layer at y=2 cannot see the contact of a 2.5 m platform.
  A 2 m cell with a y=0.5 ground layer costs about 0.53 ms, cuts the platform
  error in half, and cuts the crouched ramp-shadow error tenfold.

## Consequences

- The production scene supplies six volumes and 2205 probes; the sealed scenario
  adds its two pair volumes for 2301. ADR 0035 had six and 537 plus eight and 633.
  The probe pass grows from 0.373 ms to 0.940 ms at 1280 x 720 without synthetic
  lights, and from 0.735 ms to 1.732 ms with 64 lights. The full GPU frame grows
  from 2.095 ms to 2.850 ms in the first case and 3.937 ms to 5.549 ms in the
  second.
- The platform reference improves from median ratio 1.094, error 0.139, colour
  0.058, `p10` 0.82, `p90` 1.35 to median 1.014, error 0.059, colour 0.015,
  `p10` 0.897, `p90` 1.149. The gate fails on the old tree and passes on this
  one. With the sun below the horizon the mean moves from 0.086 to 0.079 against
  0.078, and the error from 0.151 to 0.069.
- The crouched ramp-shadow reference moves from median ratio 4.10, error 3.15,
  colour 0.61 to 1.12, 0.31, 0.039. The y=0.5 ground layer is what closes most
  of that gap; the standing ramp-shadow step count falls from 4633 to 180.
- A probe that becomes invalid has its atlas cleared, so a later valid frame
  starts from a reset texel. A moving crate can change validity; the field does
  not keep stale light across that change.
- The invalid probes still occupy an atlas slot and a dispatch slot. The ray and
  blend return early; the cost is the dispatch, not the rays.
- `tests/frame/probe_volumes.odin` now keeps a ground layer within 1.05 m of the
  floor and a spacing of 2.07 m or less for every arena volume. The default
  count is 2205. `tests/harness/probe_map.odin` checks 2205 and 2301. The existing
  ordering, footprint, bounds, and coverage tests stay.
- `scenarios/ddgi-platform.json` joins the lighting suite. The chamber, lane,
  arena, door, move, and sealed gates still run.
