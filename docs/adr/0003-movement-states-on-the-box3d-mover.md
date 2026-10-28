# Movement states on the Box3D mover

> Superseded by ADR 0043: stances, dive, crouch slide, mantle, and the exclusive
> movement state are removed. The mover and capsule seam stay.

The player stays a kinematic capsule moved by Box3D's mover. Stances, gait, jump, dive, crouch slide, and mantle are movement rules in the game layer. The exclusive action state is None, Diving, Sliding, or Mantling. The game layer also owns step-up, the walkable slope limit, ground snap, and the headroom probe. Box3D supplies capsule collide and cast queries, the plane solver, and the velocity clipper; it has no character controller, step-up, slope limit, ground snap, or headroom helper. The mover API is experimental.

The alternative is a dynamic rigid body. It would fight the direct control that first-person movement needs, and every movement state would still need explicit rules. A different character controller would replace Box3D and the established physics seam. Neither pays for itself in this slice.

## Consequences

- The movement rules live in the game layer. The headless simulation seam covers them.
- Headroom queries the stance capsule against the world with the probe inset from
  the capsule side and lifted off the floor. A floor, a step, a crate, or a wall
  that only grazes the capsule side therefore does not block a taller stance,
  while any shape that crosses the inset probe does. An AABB lower-bound test
  missed a rotated overhang whose bounds start below the feet, so a prone player
  could stand through a ramp underside.
- The prone capsule is vertical because the mover has no rotation handling. Crawl is movement while prone, not a horizontal body.
- Step-up and slope handling use capsule casts and a ground probe rather than a controller library. A Box3D upgrade can change the mover behavior.
- The player stays first person with no visible body. A visible body or a horizontal prone collider would need a different solution.
- Action states are committed. A dive, a dive slide, and a mantle lock the stance and the relevant inputs until they end.
