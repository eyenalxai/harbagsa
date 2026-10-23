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
Steering while airborne. It changes direction without gaining horizontal speed.
_Avoid_: Air strafe

**Arena**:
The fixed test level: a floor, walls, and a few crates.
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

**Spawn**:
The point where the player starts and returns after a reset.
_Avoid_: Start, origin

**Simulation**:
The headless fixed-step update that owns the world and the player state.
_Avoid_: Game loop, engine

**Input snapshot**:
One frame of player intent: movement axes, jump, and reset. Look is a separate frame call.
_Avoid_: Input state, controls

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
_Avoid_: Screenshot, shot

**Offscreen target**:
The render target with a color image, a depth image, and a readback buffer, but
no surface or swapchain.
_Avoid_: Headless framebuffer

**Swapchain target**:
The render target that acquires and presents swapchain images for the window.
_Avoid_: Window target

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
