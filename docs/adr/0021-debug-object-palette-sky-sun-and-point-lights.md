# Debug object palette, sky sun, and point lights

The `F2` debug mode becomes a small scene editor. One placed-object list holds
every editable box, a bottom-dock palette chooses a prefab, a wireframe ghost
places it, the sun is placed on a sky dome, and lamps are real point lights.

## Context

The old editor could add one kind of dynamic crate and drag it. It could not
choose a prefab, preview it, set its height or yaw before placing it, or edit a
placed object. The sun was a gizmo that rotated the light direction. The scene
had one directional light and no local light.

The renderer draws one cube mesh and one box list. The physics world has one
body per box. The harness drives the game through a command stream, not a
window, so the editor had to be testable without a cursor.

## Decisions

- **One placed-object list.** A placed object has a stable id, a prefab, a body
  mode, a physics body, and a spawn time. The three starting crates are placed
  objects. The crate-only API is gone. The list is capped at 128 objects.
- **A fixed prefab catalog.** The catalog holds eight box shapes plus three
  light shapes. A prefab has half extents, colour, a default body mode, an
  optional base pitch, and an optional point light. There is no new mesh and no
  parametric size editor.
- **Body mode is per placement.** The prefab supplies the default; `M` flips the
  next placement and the choice sticks until the prefab changes. `M` also
  converts a selected placed object. Static objects use a static body; dynamic
  objects use the prefab density.
- **The palette is a bottom dock.** A 6x2 grid of 72 px cards and a preview pane
  sit in a 678 x 226 panel at density 1. The panel fits 800x600 and keeps the
  crosshair clear. The grid has one empty cell.
- **The preview is isometric HUD geometry.** The renderer projects the oriented
  box corners and draws three shaded faces. A live 3D preview would need a
  second scene pass, a second camera and object upload, and extra TAA and
  capture handling.
- **Pointer and keyboard share one palette.** The cursor is released while the
  palette is open. Hover and click use a hit test that reads the same layout as
  the draw; arrows, `1`-`9`, `Enter`, and `M` stay available. Picking recaptures
  the cursor and arms the ghost.
- **The ghost is debug lines.** A 100 m camera ray anchors the prefab's AABB
  bottom on the hit surface, or 3 m ahead on a miss. The wheel changes height in
  0.25 m steps, `Q`/`E` turn in 15 degree steps, and `G` toggles a 0.25 m X/Z
  snap. Placement stays armed; `Esc` or right click cancels.
- **The sun is placed on a sky dome.** `L` replaces the old drag. The aim point
  is projected onto a 50 m dome around the arena centre with a 2.5 m minimum
  height. The light direction is from that point to the centre, and the scene
  updates live. A click commits; `Esc` restores the previous sun.
- **Eight point lights with one hard shadow ray each.** The frame selects the
  eight nearest lamps, deterministically by distance and id. A lamp is emissive
  even when its light is not active. The point-light shadow ray uses a TLAS mask
  that excludes lamps, so a lamp does not shadow its own light; the sun ray
  still sees them. The sun keeps its 16-ray soft shadow.
- **The point shadow ray stops short of the light.** A lamp placed against a
  wall puts its light exactly on the wall plane. An endpoint hit then made the
  wall paint a fan of shadows on every surface the lamp lit. The ray stops one
  millimetre short of the light, so a surface at the light cannot shadow it.
- **Per-placement light tuning.** `C` cycles colour, brackets change intensity,
  comma and period change range. The values stick to the next placement and edit
  a selected lamp. The palette preview and the inspector show them.
- **The pop is visual only.** A new or duplicated object scales up with an
  ease-out-back curve over 0.28 s with about 8 percent overshoot, anchored at
  the AABB bottom. The physics body keeps its full size. Initial crates and
  undo/redo restores do not pop.
- **Undo is a heap-backed snapshot history.** Up to 64 full object snapshots
  preserve ids, prefab, body, transform, colour, and light. The history is
  allocated on the first edit and freed with the debug mode, so the large state
  does not sit on the stack. A drag records one snapshot at its start.
- **The harness drives the same APIs.** One `editor` command covers the palette,
  placement, object edits, light, sun, and history. The state reports the placed
  objects, light budget, sun, inspector, and history depth. Scenarios capture
  the palette, ghost, pop, sun, and lamp scenes. The harness steps the world, not
  the player, while debug mode is active.

## Considered Options

- **Parametric boxes**: one box with width, height, and depth fields. More
  flexible, but every card becomes a form and the catalog stops being scannable.
- **New mesh shapes**: cylinders, spheres, and wedges. Needs a new mesh, BLAS
  variants, and new physics shapes. A separate feature.
- **Live 3D preview**: a second scene pass. Rejected for the first cut because
  the isometric projection is deterministic, cheap, and testable as geometry.
- **Centred modal palette**: stronger focus, but it hides the placement area.
- **All-dynamic or all-static objects**: one loses level building, the other
  loses pushable crates. Per-placement body keeps both.
- **Restore the scene when `F2` exits**: safe experiments, but it prevents
  play-testing what was just built. Placed objects stay until `Shift+R`.
- **Emissive-only lamps**: cheap, but the lamp would light nothing.
- **Soft point-light shadows or cube shadow maps**: higher quality, much higher
  cost. The first cut uses one hard ray per light and measures the result.
- **Compound lamp posts**: a post plus a head is more lamp-like, but it needs
  multi-part objects and a compound collider. Deferred to a follow-up.

## Consequences

- The renderer gains a fourth descriptor binding, a per-frame light buffer, an
  emissive field in the box data, and a light count in the camera uniform.
- The frame cost grows with the covered pixels and the active light count. The
  measured eight-light scene pass is 1.64x the no-light baseline at 1080p and
  1.61x at 1440p; the paired shadow cost is 1.20x and 1.28x. The evidence is in
  `docs/evidence/perf-lamps.md`.
- The harness `Session` no longer holds the frame scratch by value; it is
  allocated on the heap so the larger state stays under the stack warning.
- The status panel gains object, light, sun, and placement rows. Every changing
  value uses a fixed field.
- The palette, object placement, and sun placement are mutually exclusive. The
  settings menu cancels all three when it opens.
- The compound lamp post remains an open follow-up. The light model and the
  palette grid already have room for it.
