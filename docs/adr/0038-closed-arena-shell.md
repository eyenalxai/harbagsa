# Closed arena shell

> Shadow visibility is added by [ADR 0040](0040-hard-point-light-shadows.md). The no-shadow statements in this decision describe the state at the time.

The arena is one closed box. A solid ceiling spans the top of the four outer walls. The inner light-lock room and its four-turn entry tunnel are removed.

## Why

> A one-bounce probe field was added later by [ADR 0042](0042-single-volume-ddgi.md). The shell decision and the removed inner room stay in force.

The direct-light renderer has no shadow visibility and no indirect-light cache. The inner room no longer tests a lighting system that exists. Keeping it adds twelve collision shapes, a special movement path, and palette entries for no player-facing value. The open outer shell also exposes a background where no box covers the view.

## Decisions

- The outer walls rise to 5.5 m so a standing jump from the dive platform stays below the ceiling. The ceiling is one static box at the wall top. Its half extents cover the outer wall faces, and its thickness is 0.5 m.
- The ceiling is static arena geometry. It collides and renders through the same paths as the floor and walls.
- The ceiling takes its own neutral hue so downward views separate it from the warm walls.
- The inner room, its channel geometry, and its dedicated movement paths are deleted. The movement course itself stays.
- The shell count, ceiling placement, and a non-background ceiling view are fixed. The ceiling collides.
- Plan views continue to use `renderer_debug.clip_height` to hide the ceiling.

## Consequences

- The static arena has 52 boxes instead of 63.
- The whole playable space is interior. No normal player view reaches the clear colour.
- A new arena feature must fit inside the existing shell or change the shell in the same decision.
