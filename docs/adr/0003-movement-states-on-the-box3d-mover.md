# Movement states on the Box3D mover

The player stays a kinematic capsule moved by Box3D's mover. Stances, gait, jump, dive, crouch slide, and mantle are movement rules in the game layer. The exclusive action state is None, Diving, Sliding, or Mantling. The game layer also owns step-up, the walkable slope limit, ground snap, and the headroom probe. Box3D supplies capsule collide and cast queries, the plane solver, and the velocity clipper; it has no character controller, step-up, slope limit, ground snap, or headroom helper. The mover API is experimental.

The alternative is a dynamic rigid body. It would fight the direct control that first-person movement needs, and every movement state would still need explicit rules. A different character controller would replace Box3D and the established physics seam. Neither pays for itself in this slice.

## Consequences

- The movement rules are ours to test. The headless simulation seam covers them.
- Headroom ignores floor-level side obstacles and treats a shape whose lower bound is above the floor margin as a ceiling. This keeps a step or crate beside the lower body from blocking a taller stance.
- The prone capsule is vertical because the mover has no rotation handling. Crawl is movement while prone, not a horizontal body.
- Step-up and slope handling use capsule casts and a ground probe rather than a controller library. A Box3D upgrade can change the mover behavior; the tests gate that.
- The player stays first person with no visible body. A visible body or a horizontal prone collider would need a different solution.
- Action states are committed. A dive, a dive slide, and a mantle lock the stance and the relevant inputs until they end.
