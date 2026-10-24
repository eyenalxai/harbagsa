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

**Input mode**:
The way a key engages a setting: Hold while the key is down, or Toggle on each
press. The settings menu changes the sprint, crouch, and prone input modes.
_Avoid_: Key mode

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

**Sun**:
The directional light that lights the arena and casts the sun shadows. Debug mode rotates it.
_Avoid_: Lamp, light source

**Sun angular diameter**:
The angle the sun disk subtends. It sets the penumbra width. The demo uses 3°; the real sun is about 0.53°. The wider disk makes the contact-hardening cue visible over the arena's short shadows.
_Avoid_: Light size

**Contact hardening**:
The shadow behavior where the penumbra grows with the distance between the blocker and the receiver. The shadow is sharp at contact and soft away from it.
_Avoid_: Soft shadow falloff

**Penumbra**:
The partly lit band between the umbra and the fully lit area. Its width grows with the blocker distance and the sun angular diameter.
_Avoid_: Soft edge, blur

**Top-level acceleration structure (TLAS)**:
The acceleration structure that holds the box instances for ray queries. The renderer rebuilds it each frame from the box transforms.
_Avoid_: Scene BVH

**Bottom-level acceleration structure (BLAS)**:
The acceleration structure for the unit cube mesh. Every TLAS instance shares it.
_Avoid_: Mesh BVH

**Ray query**:
A shader ray test against an acceleration structure. The sun shadow traces one ray per sun sample and counts the unblocked rays.
_Avoid_: Ray trace, RTX

**Shadow ray**:
A ray from a surface point toward a sample point on the sun. A hit means the sun sample is blocked.
_Avoid_: Light ray

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
The headless fixed-step update that owns the world, the player state, and the
settings.
_Avoid_: Game loop, engine

**Input snapshot**:
One frame of player intent: movement axes, sprint, crouch, prone, jump, and reset. Look is a separate frame call.
_Avoid_: Input state, controls

**Settings**:
The runtime input-mode choices for sprint, crouch, and prone. A new simulation
starts with sprint Hold, crouch Toggle, and prone Toggle. A player reset keeps
the current settings.
_Avoid_: Options, preferences

**Render snapshot**:
The interpolatable view of the player after a simulation step.
_Avoid_: Frame state, view state

**Harness**:
The `harbagsa-agent` program that drives the simulation, runs checks, and writes
screenshots without the game loop.
_Avoid_: Bot, driver

**Scenario**:
A JSON document that compiles to one command list for the harness.
_Avoid_: Script, test case

**Capture**:
One rendered frame written as a PNG by the harness.
_Avoid_: Shot

**Session**:
The live harness process that reads one JSON command per line and writes one
JSON reply per line.
_Avoid_: Daemon, server

**Offscreen target**:
The render target with a color image, a depth image, and a readback buffer, but
no surface or swapchain.
_Avoid_: Headless framebuffer

**Swapchain target**:
The render target that acquires and presents swapchain images for the window.
_Avoid_: Window target

**Cursor capture**:
The state where the mouse controls the camera and the pointer is hidden. The
settings menu releases the capture while it is open.
_Avoid_: Mouse lock

**Debug draw**:
The line pass that shows the physics world: shape bounds and contacts.
_Avoid_: Debug view, wireframe

**Overlay**:
The screen-space pass that draws the debug draw and the HUD over the scene. It does not write depth.
_Avoid_: UI layer

**HUD**:
The 2D part of the overlay: crosshair and player state. It does not show the
control list.
_Avoid_: UI

**Settings menu**:
The paused overlay opened with `Esc`. It lists the active control set and changes
the three input modes. The harness opens it with the `menu` command and reports
`settings.*` and `menu.*` in the state.
_Avoid_: Options screen, pause menu

**Pause**:
The state while the settings menu is open. The simulation and debug camera do
not update.
_Avoid_: Freeze

**Temporal anti-aliasing (TAA)**:
The render path that jitters the camera and averages frames through a history buffer to smooth edges.
_Avoid_: Temporal filtering, accumulation

**Jitter**:
The subpixel camera offset applied each frame for TAA.
_Avoid_: Shake, offset

**History**:
The previous resolved frame, with linear color and depth, that TAA blends into the current frame.
_Avoid_: Accumulation buffer, cache

**Velocity target**:
The offscreen image that stores each pixel's previous-to-current screen motion and linear view depth.
_Avoid_: Motion buffer, motion vectors

**Resolve**:
The fullscreen pass that reprojects, tests the depth range, clamps, and blends the history into the current frame.
_Avoid_: Composite, merge

**Disocclusion**:
A pixel that was hidden by a surface and becomes visible after the camera or a surface moves.
_Avoid_: Reveal

**Depth range**:
The smallest and largest current view depth in a pixel's 3x3 neighborhood. The resolve accepts a history depth inside the range; a disocclusion falls outside it.
_Avoid_: Depth bounds, depth span

**History reset**:
The state where TAA ignores the previous history and starts a new accumulation.
_Avoid_: Clear, flush

**Convergence**:
The frames after a history reset while the history weight ramps from 0.5 to 0.9.
_Avoid_: Warmup

**TAA toggle**:
The `F3` control that enables or disables temporal anti-aliasing.
_Avoid_: AA switch

**Debug mode**:
The `F2` mode where the player becomes a free-fly camera and can edit crates and the sun.
_Avoid_: Edit mode, sandbox

**Free-fly camera**:
The debug mode camera that ignores gravity and collision.
_Avoid_: Noclip, spectator

**Selection**:
The crate or the sun that debug mode acts on.
_Avoid_: Focus, target

**Scene reset**:
The `Shift+R` action that restores the starting crates, the sun, and the player.
_Avoid_: Reload, wipe
