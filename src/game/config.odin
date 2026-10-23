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
STEP_DOWN_EXTRA :: 0.10

MANTLE_MIN_HEIGHT :: 0.20
MANTLE_MAX_HEIGHT :: 1.50
MANTLE_REACH :: 0.50
MANTLE_ACROSS_DISTANCE :: 0.45
MANTLE_DOWN_EXTRA :: 0.20
MANTLE_DURATION :: 0.25
MANTLE_UP_FRACTION :: 0.60
HEADROOM_PROBE_LIFT :: 0.002

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

stance_height :: proc(stance: Stance) -> f32 {
	switch stance {
	case .Standing:
		return PLAYER_STANDING_HEIGHT
	case .Crouching:
		return PLAYER_CROUCH_HEIGHT
	case .Prone:
		return PLAYER_PRONE_HEIGHT
	}
	return PLAYER_STANDING_HEIGHT
}

stance_eye_height :: proc(stance: Stance) -> f32 {
	switch stance {
	case .Standing:
		return PLAYER_STANDING_EYE
	case .Crouching:
		return PLAYER_CROUCH_EYE
	case .Prone:
		return PLAYER_PRONE_EYE
	}
	return PLAYER_STANDING_EYE
}

stance_speed :: proc(stance: Stance, gait: Gait) -> f32 {
	switch stance {
	case .Standing:
		return gait == .Sprint ? PLAYER_SPRINT_SPEED : PLAYER_WALK_SPEED
	case .Crouching:
		return PLAYER_CROUCH_SPEED
	case .Prone:
		return PLAYER_CRAWL_SPEED
	}
	return PLAYER_WALK_SPEED
}

stance_name :: proc(stance: Stance) -> string {
	switch stance {
	case .Standing:
		return "Standing"
	case .Crouching:
		return "Crouching"
	case .Prone:
		return "Prone"
	}
	return "Standing"
}

gait_name :: proc(gait: Gait) -> string {
	return gait == .Sprint ? "Sprint" : "Walk"
}

movement_state_name :: proc(state: Movement_State) -> string {
	switch state {
	case .None:
		return "None"
	case .Diving:
		return "Diving"
	case .Sliding_Dive, .Sliding_Crouch:
		return "Sliding"
	case .Mantling:
		return "Mantling"
	}
	return "None"
}

horizontal_speed :: proc(velocity: b3.Vec3) -> f32 {
	return math.sqrt(velocity.x * velocity.x + velocity.z * velocity.z)
}
