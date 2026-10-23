#+vet explicit-allocators
package game

import "core:math"
import b3 "libs:box3d"

Stance :: enum {
	Standing,
	Crouching,
	Prone,
}

Gait :: enum {
	Walk,
	Sprint,
}

Movement_State :: enum {
	None,
	Diving,
	Sliding_Dive,
	Sliding_Crouch,
	Mantling,
}

Input_Mode :: enum {
	Hold,
	Toggle,
}

SPRINT_INPUT_MODE :: Input_Mode.Hold
CROUCH_INPUT_MODE :: Input_Mode.Toggle
PRONE_INPUT_MODE :: Input_Mode.Toggle

PLAYER_RADIUS :: 0.35
PLAYER_STANDING_HEIGHT :: 1.80
PLAYER_CROUCH_HEIGHT :: 1.20
PLAYER_PRONE_HEIGHT :: 0.70
PLAYER_STANDING_EYE :: 1.65
PLAYER_CROUCH_EYE :: 1.05
PLAYER_PRONE_EYE :: 0.30

PLAYER_WALK_SPEED :: 5.0
PLAYER_SPRINT_SPEED :: 8.0
PLAYER_CROUCH_SPEED :: 2.4
PLAYER_CRAWL_SPEED :: 1.2
PLAYER_DIVE_SPEED :: 11.0
PLAYER_DIVE_HOP_SPEED :: 2.5
PLAYER_CROUCH_SLIDE_SPEED :: 10.0
PLAYER_DIVE_SLIDE_FRACTION :: 0.55
PLAYER_SLIDE_DECELERATION :: 18.0
PLAYER_SLIDE_END_EPSILON :: 0.02
PLAYER_CROUCH_SLIDE_JUMP_DELAY :: 0.15

PLAYER_GROUND_ACCELERATION :: 60.0
PLAYER_GROUND_DECELERATION :: 80.0
PLAYER_GRAVITY :: 18.0
PLAYER_JUMP_SPEED :: 6.0
PLAYER_AIR_CONTROL :: 15.0
PLAYER_COYOTE_TIME :: 0.10
PLAYER_JUMP_BUFFER :: 0.12

GROUND_NORMAL_THRESHOLD :: 0.70710678
GROUND_PROBE_LIFT :: 0.02
GROUND_PROBE_LENGTH :: 0.25
GROUND_CONTACT_TOLERANCE :: 0.02
GROUND_OFFSET :: 0.01
GROUND_SNAP_DISTANCE :: 0.30

STEP_HEIGHT :: 0.35
STEP_MIN_HEIGHT :: 0.02
STEP_SKIN :: 0.02
STEP_FLAT_NORMAL :: 0.95
STEP_PROBE_LIFT :: 0.05
STEP_PROBE_DROP :: 0.10

STEP_SMOOTH_RATE :: 18.0
STEP_SMOOTH_MAX :: 0.40
STEP_SMOOTH_EPSILON :: 0.001

STEP_GRACE_TIME :: 0.35
STEP_GRACE_SPEED :: 0.1

MANTLE_MIN_HEIGHT :: 0.20
MANTLE_MAX_HEIGHT :: 1.50
MANTLE_REACH :: 0.50
MANTLE_ACROSS_DISTANCE :: 0.45
MANTLE_DOWN_EXTRA :: 0.20
MANTLE_DURATION :: 0.25
MANTLE_UP_FRACTION :: 0.60
HEADROOM_PROBE_LIFT :: 0.002
HEADROOM_CEILING_MARGIN :: 0.05

EYE_HEIGHT_SMOOTH_RATE :: 25.0

FALL_RESET_Y :: -10.0
YAW_SENSITIVITY :: 0.0022
PITCH_SENSITIVITY :: 0.0018
PITCH_LIMIT :: 89.0 * b3.DEG_TO_RAD

SPAWN_POSITION :: b3.Vec3{0.0, 0.05, 14.0}

CRATE_DENSITY :: 20.0

SIMULATION_STEP :: 1.0 / 60.0
SIMULATION_SUB_STEPS :: 4

MAX_COLLISION_PLANES :: 16
MOVE_ITERATIONS :: 5
MOVE_TOLERANCE :: 0.01

Stance_Info :: struct {
	height:       f32,
	eye:          f32,
	walk_speed:   f32,
	sprint_speed: f32,
	name:         string,
}

STANCE_INFO := [Stance]Stance_Info {
	.Standing = {
		PLAYER_STANDING_HEIGHT,
		PLAYER_STANDING_EYE,
		PLAYER_WALK_SPEED,
		PLAYER_SPRINT_SPEED,
		"Standing",
	},
	.Crouching = {
		PLAYER_CROUCH_HEIGHT,
		PLAYER_CROUCH_EYE,
		PLAYER_CROUCH_SPEED,
		PLAYER_CROUCH_SPEED,
		"Crouching",
	},
	.Prone = {
		PLAYER_PRONE_HEIGHT,
		PLAYER_PRONE_EYE,
		PLAYER_CRAWL_SPEED,
		PLAYER_CRAWL_SPEED,
		"Prone",
	},
}

MOVEMENT_STATE_NAMES := [Movement_State]string {
	.None = "None",
	.Diving = "Diving",
	.Sliding_Dive = "Sliding",
	.Sliding_Crouch = "Sliding",
	.Mantling = "Mantling",
}

stance_height :: proc(stance: Stance) -> f32 {
	return STANCE_INFO[stance].height
}

stance_eye_height :: proc(stance: Stance) -> f32 {
	return STANCE_INFO[stance].eye
}

stance_speed :: proc(stance: Stance, gait: Gait) -> f32 {
	info := STANCE_INFO[stance]
	return gait == .Sprint ? info.sprint_speed : info.walk_speed
}

stance_name :: proc(stance: Stance) -> string {
	return STANCE_INFO[stance].name
}

gait_name :: proc(gait: Gait) -> string {
	return gait == .Sprint ? "Sprint" : "Walk"
}

movement_state_name :: proc(state: Movement_State) -> string {
	return MOVEMENT_STATE_NAMES[state]
}

horizontal_speed :: proc(velocity: b3.Vec3) -> f32 {
	return math.sqrt(velocity.x * velocity.x + velocity.z * velocity.z)
}
