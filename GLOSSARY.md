# harbagsa

A first-person shooter. The current slice is first-person movement.

## Language

**Stance**:
The player's body posture: standing, crouching, or prone. It sets the capsule height, the eye height, and the ground speed.
_Avoid_: Posture, position

**Gait**:
The player's ground movement mode: walk or sprint. Sprint is available in every direction.
_Avoid_: Run, speed mode

**Omnidirectional movement**:
Movement where input maps to any horizontal direction relative to camera yaw. Stance and gait do not restrict the direction.
_Avoid_: Free movement, 8-way movement

**Headroom**:
The free space above the player's feet that accepts a target stance capsule. Headroom decides whether the player can enter a taller stance.
_Avoid_: Ceiling space

**Clearance**:
The free height of a tunnel or opening. A stance fits when its capsule height is below the clearance.
_Avoid_: Headroom

**Eye height**:
The camera height above the player's feet. Each stance has one.
_Avoid_: Camera offset

**Dive**:
An airborne move that locks the horizontal direction, raises speed, and ends in prone.
_Avoid_: Lunge, belly flop

**Slide**:
The short prone glide after a dive lands. The slide locks steering.
_Avoid_: Skid

**Character controller**:
The component that moves the player through the world and resolves walls, steps, and slopes by collide-and-slide.
_Avoid_: Mover, motor

**Grounded**:
The state where the character controller finds a floor under the player.
_Avoid_: On floor

**Air control**:
Steering while airborne. It changes direction without gaining horizontal speed.
_Avoid_: Air strafe

**Coyote time**:
A short grace window after the player leaves the ground in which a jump still works.
_Avoid_: Late jump

**Jump buffer**:
A short window that remembers a jump press made before landing.
_Avoid_: Input buffer

**Player**:
The single first-person character.
_Avoid_: Avatar, pawn
