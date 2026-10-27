#+vet explicit-allocators
#+vet !unused-procedures // the harness and the scene load use these names
package game

import "core:math"
import b3 "libs:box3d"

Gait :: enum {
	Walk,
	Sprint,
}

Input_Mode :: enum {
	Hold,
	Toggle,
}

DEFAULT_SPRINT_INPUT_MODE :: Input_Mode.Hold

// The collision capsule is the spider body. The legs are visual, so the capsule
// stays low enough for the 0.90 m tunnel.
PLAYER_RADIUS :: 0.42
PLAYER_HEIGHT :: 0.84

PLAYER_WALK_SPEED :: 5.0
PLAYER_SPRINT_SPEED :: 8.0

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

// Body geometry. The body center sits this high above the feet, and the leg
// rest points lie on the ground at the radius the legs reach comfortably.
SPIDER_BODY_HEIGHT :: 0.58
SPIDER_CEPHALOTHORAX_HALF :: b3.Vec3{0.32, 0.14, 0.26}
SPIDER_CEPHALOTHORAX_OFFSET :: b3.Vec3{0.0, 0.04, -0.22}
SPIDER_ABDOMEN_HALF :: b3.Vec3{0.40, 0.18, 0.34}
SPIDER_ABDOMEN_OFFSET :: b3.Vec3{0.0, 0.06, 0.26}

// Legs. The rest and hip tables are in body space, with local -Z as forward.
LEG_COUNT :: 8
LEG_FEMUR_LENGTH :: f32(0.62)
LEG_TIBIA_LENGTH :: f32(0.70)
LEG_THICKNESS :: f32(0.062)
LEG_KNEE_HALF :: f32(0.078)
LEG_REACH_FRACTION :: 0.94
LEG_STEP_TRIGGER :: 0.30
LEG_STEP_DURATION :: 0.14
LEG_STEP_LIFT :: 0.13
LEG_STEP_LEAD :: 0.16
LEG_LANDING_DURATION :: 0.10
LEG_GROUND_PROBE :: 1.80
LEG_PLANT_LIFT :: 0.015
LEG_TUCK_SCALE :: 0.55
LEG_TUCK_LIFT :: 0.06

// The body turns toward the movement direction. Look never turns the body.
SPIDER_TURN_RATE :: 14.0
SPIDER_TURN_MIN_SPEED :: 0.20

// Third-person camera. The pivot sits above the body center. A capsule cast
// keeps the arm short of the first surface.
CAMERA_DISTANCE :: f32(4.40)
CAMERA_PIVOT_RISE :: 0.45
CAMERA_MIN_DISTANCE :: f32(0.75)
CAMERA_WALL_PAD :: f32(0.12)
CAMERA_PROBE_RADIUS :: 0.16
CAMERA_PROBE_HALF :: 0.0
CAMERA_PITCH_MIN :: -70.0 * b3.DEG_TO_RAD
CAMERA_PITCH_MAX :: 45.0 * b3.DEG_TO_RAD
CAMERA_DEFAULT_PITCH :: -15.0 * b3.DEG_TO_RAD
CAMERA_CEILING_PROBE :: 1.60
CAMERA_CEILING_PAD :: 0.20

FALL_RESET_Y :: -10.0
YAW_SENSITIVITY :: 0.0022
PITCH_SENSITIVITY :: 0.0018

SPAWN_POSITION :: b3.Vec3{0.0, 0.01, 14.0}

SIMULATION_STEP :: 1.0 / 60.0
SIMULATION_SUB_STEPS :: 4

MAX_COLLISION_PLANES :: 16
MOVE_ITERATIONS :: 5
MOVE_TOLERANCE :: 0.01

MENU_STATUS_SECONDS :: 2.0

gait_name :: proc(gait: Gait) -> string {
	return gait == .Sprint ? "Sprint" : "Walk"
}

gait_speed :: proc(gait: Gait) -> f32 {
	return gait == .Sprint ? PLAYER_SPRINT_SPEED : PLAYER_WALK_SPEED
}

horizontal_speed :: proc(velocity: b3.Vec3) -> f32 {
	return math.sqrt(velocity.x * velocity.x + velocity.z * velocity.z)
}
