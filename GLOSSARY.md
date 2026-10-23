# harbagsa

A first-person game. The current slice is a walking demo.

## Language

**Player**:
The single first-person character.
_Avoid_: Avatar, pawn

**Character controller**:
The component that moves the player through the world and resolves walls and floors by collide-and-slide.
_Avoid_: Mover, motor

**Mover**:
Box3D's capsule query API. It gathers contact planes, sweeps the capsule, solves penetration, and clips velocity. The character controller uses the mover; the mover is not the controller.
_Avoid_: Character controller

**Capsule**:
The player's collision shape: a vertical cylinder with rounded ends. It sets the player's height and radius.
_Avoid_: Collider, cylinder

**Eye height**:
The camera height above the player's feet.
_Avoid_: Camera offset

**Grounded**:
The state where the character controller finds a floor under the player.
_Avoid_: On floor

**Air control**:
Steering while airborne. It changes direction up to the air cap; it never exceeds the cap.
_Avoid_: Air strafe

**Stance**:
The player's body height: Standing, Crouching, or Prone. It sets the capsule height, the eye height, and the movement speed.
_Avoid_: Posture, state

**Standing**:
The tallest stance. The capsule is 1.80 m high and the eye is 1.65 m above the feet.

**Crouching**:
The middle stance. The capsule is 1.20 m high and the eye is 1.05 m above the feet.

**Prone**:
The lowest stance. The capsule is 0.70 m high and the eye is 0.30 m above the feet. A prone player can crawl.

**Crawl**:
Movement while Prone. The crawl speed is 1.2 m/s along the walkable ground plane.
_Avoid_: Prone walk

**Gait**:
The ground movement mode: Walk or Sprint. Sprint applies only while Standing.
_Avoid_: Run mode

**Sprint**:
The 8.0 m/s ground speed. The horizontal component is lower on a climb.
_Avoid_: Run

**Ground speed**:
The speed along the walkable ground plane. On a straight climb the horizontal speed is `ground speed * cos(slope)`.
_Avoid_: Surface speed

**Headroom**:
The clear space above the feet that a taller stance needs. The controller tests it before the capsule grows. A floor-level side obstacle does not reduce headroom; an overhead shape does.
_Avoid_: Ceiling check

**Dive**:
An 11.0 m/s lunge that starts in the air or from a sprint. The player lands Prone and slides.
_Avoid_: Lunge

**Slide**:
The locked-direction glide after a dive or a crouch slide. A dive slide ends Prone; a crouch slide ends Crouching.
_Avoid_: Skid

**Crouch slide**:
A 10.0 m/s slide that starts from Sprint. It ends Crouching.
_Avoid_: Power slide

**Mantle**:
A 0.25 s climb onto a ledge up to 1.5 m above the feet. A fresh jump press or a held jump with movement input starts it.
_Avoid_: Climb, vault

**Step-up**:
The automatic climb onto a near-vertical obstacle up to 0.35 m high while grounded. The top must be near flat; a walkable ramp is not a step-up.
_Avoid_: Autostep

**Ground snap**:
The downward correction that keeps a grounded player on a walkable surface within 0.30 m. A walkable slope can give a small positive vertical velocity; the surface clearance decides, not the sign of the velocity.
_Avoid_: Stick to ground

**Step smoothing**:
The short vertical camera lag after a step-up or step-down. It decays after the capsule settles and does not move the player.
_Avoid_: Camera lag

**Coyote time**:
The 0.10 s after leaving a walkable surface during which a jump still works.
_Avoid_: Grace period

**Jump buffer**:
The 0.12 s before landing during which a jump press is remembered.
_Avoid_: Input buffer

**Movement state**:
The exclusive action state: None, Diving, Sliding, or Mantling. Stance and gait are separate.
_Avoid_: Action state

**Arena**:
The fixed test level: a floor, walls, stairs, ramps, tunnels, mantle walls, a dive platform, a slide lane, and a few crates.
_Avoid_: Map, level

**Light volume**:
The fixed orthographic box around the arena that the shadow map covers.
_Avoid_: Shadow frustum

**Sun**:
The fixed directional light that lights the arena and casts the shadow map.
_Avoid_: Lamp, light source

**Shadow map**:
The depth image rendered from the sun's point of view. The lit pass compares each surface point against it to decide whether the sun reaches the point.
_Avoid_: Depth map

**Shadow pass**:
The depth-only pass that fills the shadow map before the lit pass.
_Avoid_: Light pass

**Crate**:
A dynamic box that the player can push.
_Avoid_: Prop, box

**Slide lane**:
The marked arena strip for crouch slides.
_Avoid_: Runway

**Mantle wall**:
The arena wall with a top at mantle height.
_Avoid_: Ledge

**Dive platform**:
The 2.5 m arena platform that starts dives.
_Avoid_: Tower

**Spawn**:
The point where the player starts and returns after a reset.
_Avoid_: Start, origin

**Simulation**:
The headless fixed-step update that owns the world and the player state.
_Avoid_: Game loop, engine

**Input snapshot**:
One frame of player intent: movement axes, sprint, crouch, prone, jump, and reset. Look is a separate frame call.
_Avoid_: Input state, controls

**Render snapshot**:
The interpolatable view of the player after a simulation step.
_Avoid_: Frame state, view state

**Cursor capture**:
The state where the mouse controls the camera and the pointer is hidden.
_Avoid_: Mouse lock

**Debug draw**:
The line pass that shows the physics world: shape bounds and contacts.
_Avoid_: Debug view, wireframe

**Overlay**:
The screen-space pass that draws the debug draw and the HUD over the scene. It does not write depth.
_Avoid_: UI layer

**HUD**:
The 2D part of the overlay: crosshair, controls hint, and player state.
_Avoid_: UI

**Debug mode**:
The `F2` mode where the player becomes a free-fly camera and can edit crates and the sun.
_Avoid_: Edit mode, sandbox

**Free-fly camera**:
The debug mode camera that ignores gravity and collision.
_Avoid_: Noclip, spectator

**Selection**:
The crate or the sun that debug mode acts on.
_Avoid_: Focus, target

**Sun**:
The directional light. Debug mode changes its direction.
_Avoid_: Lamp, light source

**Scene reset**:
The `Shift+R` action that restores the starting crates, the sun, and the player.
_Avoid_: Reload, wipe
