# Kinematic capsule for the player

> Superseded by ADR 0043: the player is now a spider with a low body capsule. The
> kinematic mover and the capsule query seam stay.

The player is a capsule moved by a kinematic character controller, not a dynamic rigid body. FPS movement needs direct control of velocity, jump, and camera. A dynamic body lets collisions and slopes push the player in ways that break that control. The controller uses Box3D's mover queries (`World_CollideMover`, `World_CastMover`, `SolvePlanes`, `ClipVector`) to resolve walls and floors, and it applies impulses to dynamic crates so the player can push props. Box3D's mover is experimental and gives no step-up or slope handling. The controller owns those behaviors; the first slice adds neither. Changing to a dynamic body later would replace most of the movement code. The player gets no ragdoll and no physics-driven knockback.

ADR-0003 keeps the kinematic capsule and adds step-up, slopes, ground snap, the stance set, and the movement states.
