# Kinematic capsule for the player

The player is a capsule collider moved by Rapier's kinematic character controller, not a dynamic rigid body. FPS movement needs direct control of velocity, jump arcs, and stance height. A dynamic body lets collisions and slopes push the player in ways that break that control. The controller still applies impulses to dynamic crates, so the player can push props.

Changing to a dynamic body later would replace most of the movement code. The player gets no ragdoll and no physics-driven knockback. Stance changes resize the capsule.
