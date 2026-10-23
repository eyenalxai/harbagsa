# Ground speed, step-up, and step smoothing

Movement uses the walkable ground plane. The wish velocity is projected onto the
ground normal and normalized to the stance speed. A straight climb keeps the
stance speed along the surface, so the horizontal speed drops by the slope
cosine. Across the slope the horizontal speed stays at the stance speed.

Step-up is a narrow probe, not the mantle probe. It runs only while grounded,
only on a flat surface, and only when a forward capsule cast meets a
near-vertical riser whose top ray is near flat. It lifts the capsule and lets the
normal collide-and-slide move supply the horizontal travel. A short step grace
keeps the capsule grounded while its center crosses the tread, and the ground
snap follows a step-down.

The camera carries a separate step smoothing offset. A step-up or step-down
moves the offset by the vertical correction; the offset decays over about 0.1 s.
The eye position adds this offset, so the capsule can step while the view stays
smooth. The offset never changes the player position.

## Why

- Quake III and Godot keep the speed along the walkable plane. Unreal optionally
  does the same with `bMaintainHorizontalGroundVelocity`. A horizontal-only
  target makes the along-slope speed `v / cos(theta)`, which feels faster uphill.
- A step-up that writes a fixed radius forward in one frame is a visible lurch.
  The capsule, the camera, and the collision move must be separate.
- The capsule rests on the step edge until its center crosses the riser. A short
  step grace avoids gravity pulling it back to the lower floor during those
  frames.

## Consequences

- The HUD shows horizontal speed, so a climb shows the expected drop.
- Step-up ignores walkable ramps; they are climbed by the slope controller.
- Step smoothing is visual only. A large fall is not smoothed, so a jump and a
  fall keep their direct vertical motion.
- The step probe uses capsule casts and a downward ray. A Box3D upgrade can
  change the mover behavior; the simulation tests gate it.
