# Direct light with surface occlusion

Supersedes
[ADR 0017](0017-sky-ambient-and-ray-traced-ambient-occlusion.md). The scene has
no ambient term. The sky stays a background. The ambient-occlusion rays stay and
now scale the sun and the point lights.

## Context

The room in the arena's +x/+z corner exposed the base light. A sealed room was
still lit because the ambient term was a constant ramp on the surface normal.
No amount of geometry could make the room dark. The owner wants total darkness
as the base level, and keeps the ambient-occlusion term.

Ambient occlusion is a visibility term for ambient light. With the ambient term
at zero it would have nothing to scale. The owner wants it to stay and to darken
a surface that the sun or a lamp reaches.

## Decision

- Remove the flat `AMBIENT_COLOR` and the `sky_ambient` ramp. A surface that the
  sun and the point lights do not reach is black.
- Keep the eight cosine-weighted occlusion rays and the `ao` override.
- Scale the direct sun and the point-light sum by the occlusion term:
  `out = albedo * (sun + point_lights) * occlusion + emissive`.
- Set `AO_STRENGTH` to 0.5. At 1.0 the stochastic term moves sunlit pixels by
  more than 16 levels in the TAA motion hold.
- Keep the sky pass as the background. The `sky` override controls that pass
  only; it no longer selects an ambient source.
- Keep the four-turn room light lock. The chamber has no straight path to the
  door, so it is black until a lamp is placed.

## Why

- The base level must be zero. A constant ambient cannot be zero in a corner
  and non-zero in the open without a sky-visibility model, and the owner
  rejected ambient fill.
- The occlusion stays useful where there is real light: a sunlit floor at the
  foot of a wall, or a lamp-lit corner, keeps a contact darkening.
- The direct shadows remain ray-traced. The occlusion is a second, local
  visibility term. It is not global illumination and it does not bounce.
- The room is the proof. The depth target contains no sky pixel, the chamber
  mean stays at the output dither floor under both sun azimuths, and a placed
  lamp raises it to 124 levels.

## Considered Options

- **Keep the ambient ramp and add sky visibility.** This would keep a real
  ambient source and make the room dark, but it reintroduces a fill term. The
  owner asked for no ambient base.
- **Remove the occlusion with the ambient.** The owner wants the contact
  darkening to stay.
- **Apply the occlusion to the ambient only and set the ambient to zero.** The
  rays would run and change nothing. This is dead work and a dead control.
- **Apply the occlusion at full strength.** The sunlit pixels step by up to 16
  levels, and `taa-motion` measures 5.1e-05 over its 5e-06 gate. Half strength
  measures 3.25e-06 and keeps the contact term visible.
- **Apply the occlusion to the sky pass.** The sky is a background, not a light.
  The pass has no surface position or normal to occlude.
- **A separate occlusion pass.** The lit pass already holds the world position,
  the normal, and the TLAS. A second pass would write the same inputs and read
  them back.
- **A bounce term.** A bounce is transport and needs a denoiser. The occlusion
  is visibility.

## Consequences

- The scene has two light sources: the sun and the point lights. The sky is a
  background. A shadowed surface is black.
- A lit surface in a corner loses up to half of its light. The exact loss is the
  unoccluded hemisphere fraction, out to 1.5 m, scaled by 0.5.
- The room chamber is black with no lamp at both sun azimuths. The first tunnel
  lane is lit when the sun is west, and black when it is east. The four turns
  stop the rest.
- `AO_STRENGTH` is 0.5 and `setup.renderer.ao_strength` reports it. The
  `AO_SAMPLES` define and the eight-ray cost are unchanged.
- `scenarios/sky.json` tests the sky pass and the background flag. The old
  corner AO captures are gone because the replaced ambient no longer exists.
  `scenarios/stairs-ao.json` now checks that AO darkens the sunlit floor and the
  shade.
- `scenarios/taa-motion.json` measures 0.0412 mean delta and 3.25e-06 over-16
  fraction. The gates stay at 0.07 and 5e-06.
- The scene contrast rises. The sunlit faces and the black shadows are the look;
  a texture or a fill light would break it.
- The evidence is in `docs/evidence/sky-ao.md` and
  `docs/evidence/room-lighting.md`. The room design is in issue #300.
