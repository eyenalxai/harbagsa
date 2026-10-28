# Ground speed, step-up, and step smoothing

> Superseded by ADR 0043: the stance speed is replaced by the gait speed, and step
> smoothing now offsets the third-person camera pivot only.

> 0004 until 2026-10-24. The temporal anti-aliasing ADR claimed 0004 first, so
> this one moved.

Movement uses the walkable ground plane. The wish velocity is projected onto the
ground normal and normalized to the stance speed. A straight climb keeps the
stance speed along the surface, so the horizontal speed drops by the slope
cosine. Across the slope the horizontal speed stays at the stance speed.

Step-up is a narrow probe, not the mantle probe. It runs only while grounded,
only on a flat surface, and only when a forward capsule cast meets a
near-vertical riser whose top ray is near flat. The probe crosses the riser
along the riser's own horizontal normal, then casts a ray down onto the tread.
It lifts the capsule and lets the normal collide-and-slide move supply the
horizontal travel. A short step grace keeps the capsule grounded while its
center crosses the tread, and the ground snap follows a step-down.

The camera carries a separate step smoothing offset. A step-up or step-down
moves the offset by the vertical correction; the offset decays as
`offset *= exp(-STEP_SMOOTH_RATE * dt)` at 18 /s, so the 0.40 m clamp falls
below the 1 mm epsilon in 20 steps at 60 Hz, about 0.33 s. The eye position adds
this offset, so the capsule can step while the view stays smooth. The offset
never changes the player position.

## Why

- Quake III and Godot keep the speed along the walkable plane. Unreal optionally
  does the same with `bMaintainHorizontalGroundVelocity`. A horizontal-only
  target makes the along-slope speed `v / cos(theta)`, which feels faster uphill.
- A step-up that writes a fixed radius forward in one frame is a visible lurch.
  The capsule, the camera, and the collision move must be separate.
- The probe must cross the riser. A fixed offset along the velocity stays in
  front of the tread when the approach is shallow, so the down ray lands back
  on the current step and the player slides along the riser. The riser's own
  horizontal normal crosses the tread at every approach angle.
- The capsule rests on the step edge until its center crosses the riser. A short
  step grace avoids gravity pulling it back to the lower floor during those
  frames.

## Consequences

- The HUD shows horizontal speed, so a climb shows the expected drop.
- Step-up ignores walkable ramps; they are climbed by the slope controller.
- A diagonal approach climbs like a straight one. The step probe aims at the
  tread, so the approach angle does not decide whether a step is taken.
- The probe uses the most opposed blocking plane. A riser that meets a wall in a
  concave corner can lose to the wall; no arena geometry has that shape.
- Step smoothing is visual only. A large fall is not smoothed, so a jump and a
  fall keep their direct vertical motion.
- A step-down can free-fall for a few frames before the ground probe finds the
  next tread. The camera offset hides the drop, but the capsule is not glued to
  the stair. A dedicated step-down snap is future work.
- The step probe uses capsule casts and a downward ray. A Box3D upgrade can
  change the mover behavior.
