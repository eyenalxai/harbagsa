#+vet explicit-allocators
package game

import b3 "libs:box3d"

// The player capsule. Height is the full capsule height, so the two sphere
// centers sit one radius inside each end.
PLAYER_RADIUS :: 0.35
PLAYER_HEIGHT :: 1.80
PLAYER_EYE_HEIGHT :: 1.65

PLAYER_WALK_SPEED :: 5.0
PLAYER_GROUND_ACCELERATION :: 60.0
PLAYER_GROUND_DECELERATION :: 80.0
PLAYER_GRAVITY :: 18.0
PLAYER_JUMP_SPEED :: 6.0
PLAYER_AIR_CONTROL :: 15.0

GROUND_NORMAL_THRESHOLD :: 0.7
GROUND_PROBE_LIFT :: 0.02
GROUND_PROBE_LENGTH :: 0.10
GROUND_CONTACT_TOLERANCE :: 0.02

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

// jump is a frame edge: apply it on one fixed step. Look is a separate call so
// it works when no fixed step runs.
Input_Snapshot :: struct {
	move_forward: f32,
	move_right:   f32,
	jump_pressed: bool,
}

Render_Snapshot :: struct {
	position:              b3.Vec3,
	previous_position:     b3.Vec3,
	eye_position:          b3.Vec3,
	previous_eye_position: b3.Vec3,
	velocity:              b3.Vec3,
	yaw:                   f32,
	pitch:                 f32,
	grounded:              bool,
}

Simulation :: struct {
	world_id:               b3.WorldId,
	player:                 Player,
	crates:                 [MAX_CRATES]Crate,
	crate_count:            int,
	next_crate_color_index: int,
}

simulation_create :: proc() -> Simulation {
	sim: Simulation

	world_def := b3.DefaultWorldDef()
	world_def.gravity = {0.0, -PLAYER_GRAVITY, 0.0}
	sim.world_id = b3.CreateWorld(world_def)
	if !b3.World_IsValid(sim.world_id) {
		return sim
	}

	create_arena(&sim)
	simulation_reset_crates(&sim)
	simulation_reset(&sim)
	return sim
}

simulation_destroy :: proc(sim: ^Simulation) {
	if b3.World_IsValid(sim.world_id) {
		b3.DestroyWorld(sim.world_id)
	}
	sim^ = {}
}

simulation_is_valid :: proc(sim: ^Simulation) -> bool {
	return b3.World_IsValid(sim.world_id)
}

simulation_reset :: proc(sim: ^Simulation) {
	player_place(&sim.player, SPAWN_POSITION, 0.0, 0.0)
}

simulation_step :: proc(sim: ^Simulation, input: Input_Snapshot, time_step: f32) {
	if !b3.World_IsValid(sim.world_id) || time_step <= 0.0 {
		return
	}

	if sim.player.position.y < FALL_RESET_Y {
		simulation_reset(sim)
		return
	}

	sim.player.previous_position = sim.player.position

	probe := probe_ground(sim)
	sim.player.grounded = is_grounded(sim, probe)

	// Use ground acceleration on the jump frame too. The jump only changes the
	// vertical velocity; the horizontal controller still has the floor.
	update_horizontal_velocity(&sim.player, input, time_step)
	if input.jump_pressed && sim.player.grounded {
		sim.player.velocity.y = PLAYER_JUMP_SPEED
		sim.player.grounded = false
	}

	sim.player.velocity.y -= PLAYER_GRAVITY * time_step

	move_player(sim, time_step)
	b3.World_Step(sim.world_id, time_step, SIMULATION_SUB_STEPS)

	probe = probe_ground(sim)
	sim.player.grounded = is_grounded(sim, probe)
	if sim.player.grounded && sim.player.velocity.y < 0.0 {
		sim.player.velocity.y = 0.0
	}
}

simulation_snapshot :: proc(sim: ^Simulation) -> Render_Snapshot {
	eye_offset := b3.Vec3{0.0, PLAYER_EYE_HEIGHT, 0.0}
	return {
		position = sim.player.position,
		previous_position = sim.player.previous_position,
		eye_position = sim.player.position + eye_offset,
		previous_eye_position = sim.player.previous_position + eye_offset,
		velocity = sim.player.velocity,
		yaw = sim.player.yaw,
		pitch = sim.player.pitch,
		grounded = sim.player.grounded,
	}
}

// The debug mode keeps the crates alive while the player is not simulated.
simulation_step_world :: proc(sim: ^Simulation, time_step: f32) {
	if !b3.World_IsValid(sim.world_id) || time_step <= 0.0 {
		return
	}
	b3.World_Step(sim.world_id, time_step, SIMULATION_SUB_STEPS)
}

@(private)
create_arena :: proc(sim: ^Simulation) {
	for box in arena_static_boxes() {
		create_static_box(sim.world_id, box.center, box.half_extents)
	}
}

@(private)
create_static_box :: proc(world_id: b3.WorldId, position: b3.Vec3, half_extents: b3.Vec3) {
	body_def := b3.DefaultBodyDef()
	body_def.position = position
	body_id := b3.CreateBody(world_id, body_def)

	hull := b3.MakeBoxHull(half_extents.x, half_extents.y, half_extents.z)
	shape_def := b3.DefaultShapeDef()
	_ = b3.CreateHullShape(body_id, shape_def, &hull.base)
}
