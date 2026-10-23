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
One frame of player intent: movement axes, look delta, jump, and reset.
_Avoid_: Input state, controls

**Render snapshot**:
The interpolatable view of the player after a simulation step.
_Avoid_: Frame state, view state

**Cursor capture**:
The state where the mouse controls the camera and the pointer is hidden.
_Avoid_: Mouse lock

**Debug draw**:
The line pass that shows the physics world: shapes, contacts, and bounds.
_Avoid_: Debug view, wireframe

**HUD**:
The 2D overlay: crosshair, controls hint, and player state.
_Avoid_: UI, overlay
