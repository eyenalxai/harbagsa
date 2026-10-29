# Absolute darkness

> A mixed-lighting bake now supplies indirect light from the static fixtures.
> See [ADR 0045](0045-mixed-lighting.md). The no-ambient-floor rule and every
> other decision here stay in force.

The renderer has no ambient fill. A surface receives light only from the current direct point lights and its emissive term. A view with no active lamp is black.

## Why

- The owner wants absolute darkness by default. A constant ambient floor is a default light, even when no lamp reaches the surface.
- Light placement is meaningful only when an unlit surface is actually black. A fill hides bad lamp coverage and flattens the room.
- Direct hard shadows already supply contact cues. The ambient floor was not ambient occlusion, GI, or a sky term.
- The old floor existed for readability. The owner rejects that trade.
- The flat box style still has shape under a lamp: range falloff and hard shadows make the surface readable.

## Decisions

- Remove `AMBIENT_FLOOR` from `src/renderer/shaders/box.frag`.
- Shade with `albedo * direct_point_lights + albedo * emissive`.
- Keep every explicit starting lamp. A lamp-free scene is the black baseline.
- Keep the direct clustered lights, hard ray-query shadows, TAA, and emissive term.
- Do not add a screen-space fill or an ambient occlusion term to replace the floor. A baked mixed-lighting layer was added later by ADR 0045; it carries light from the static fixtures and does not create a default fill.
- The lamp-free frame is black, and a lamp restores light.
- The ceiling is proved from a lit ceiling, not from ambient fill.
- Update the world guide, README, glossary, ADR 0037, and ADR 0040.

## Considered Options

- **Keep a small ambient floor.** This is the old look. It makes every unlit surface readable, but it is a default light and hides missing lamp coverage. Rejected by the owner.
- **Use ray-traced ambient occlusion instead.** AO is a visibility term for ambient light. With no ambient term it would multiply zero. It cannot replace the floor.
- **Add indirect light.** This is GI and needs a new transport system and denoiser. Out of scope.
- **Bake a floor.** There is no texture or baked lighting. Out of scope.
- **Remove the starting lamps too.** The explicit starting lamps are placed light, not a default fill. They stay so the spawn shows the lighting model. A scene with no lamps is black.

## Consequences

- Lamp-free views are black.
- Corners outside every lamp range lose all detail. This is deliberate.
- The starting scene is lit only by the three starting lamps and their emissive boxes.
- The ceiling is dim but not black where the starting lights reach it.
- The evidence changes from non-black ambient coverage to black unlit coverage.
- This supersedes the ambient-floor decisions in ADR 0037. The direct-light and shadow decisions otherwise stay in force.
