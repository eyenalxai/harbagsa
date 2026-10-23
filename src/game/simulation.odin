#+vet explicit-allocators
package game

import b3 "libs:box3d"

import "src:geometry"

// Jump, reset, and the stance edges are frame edges: apply them on one fixed
// step. Look is a separate call so it works when no fixed step runs.
Input_Snapshot :: struct {
	move_forward:   f32,
	move_right:     f32,
	sprint_held:    bool,
	sprint_pressed: bool,
	crouch_held:    bool,
	crouch_pressed: bool,
	prone_held:     bool,
	prone_pressed:  bool,
	jump_pressed:   bool,
	jump_held:      bool,
	reset_pressed:  bool,
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
	stance:                Stance,
	gait:                  Gait,
	movement_state:        Movement_State,
	step_smoothing:        f32,
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
	commit_stance(&sim.player, .Standing)
	sim.player.gait = .Walk
	sim.player.sprint_toggled = false
	sim.player.sprint_wanted = false
	sim.player.eye_height = PLAYER_STANDING_EYE
	sim.player.previous_eye_height = PLAYER_STANDING_EYE
}

simulation_step :: proc(sim: ^Simulation, input: Input_Snapshot, time_step: f32) {
	if !b3.World_IsValid(sim.world_id) || time_step <= 0.0 {
		return
	}

	if input.reset_pressed || sim.player.position.y < FALL_RESET_Y {
		simulation_reset(sim)
		return
	}

	sim.player.previous_position = sim.player.position
	sim.player.previous_eye_height = sim.player.eye_height
	sim.player.previous_step_smoothing = sim.player.step_smoothing
	sim.player.step_grace = max(sim.player.step_grace - time_step, 0.0)

	probe := probe_ground(sim)
	sim.player.grounded = is_grounded(sim, probe)
	// A step leaves the capsule over the edge until its center crosses the
	// tread. Keep it grounded for a short grace instead of letting gravity undo
	// the step.
	if sim.player.grounded {
		sim.player.ground_normal = probe.normal
		if sim.player.step_grace > 0.0 {
			sim.player.ground_normal = {0.0, 1.0, 0.0}
			sim.player.velocity.y = 0.0
		}
		if horizontal_speed(sim.player.velocity) < STEP_GRACE_SPEED {
			sim.player.step_grace = 0.0
		}
	} else if sim.player.step_grace > 0.0 &&
	   horizontal_speed(sim.player.velocity) >= STEP_GRACE_SPEED {
		sim.player.grounded = true
		sim.player.ground_normal = {0.0, 1.0, 0.0}
		sim.player.velocity.y = 0.0
	} else {
		sim.player.step_grace = 0.0
	}
	was_grounded := sim.player.grounded

	_ = try_mantle(sim, input)
	try_dive(sim, input)
	_ = try_crouch_slide(sim, input)
	update_stance_input(&sim.player, input)
	update_sprint_input(&sim.player, input)
	resolve_stance(sim, input)
	update_eye_height(&sim.player, time_step)

	update_jump_timers(sim, input, time_step)
	try_crouch_slide_jump(sim, input)

	// Use ground acceleration on the jump frame too. The jump only changes the
	// vertical velocity; the horizontal controller still has the floor.
	update_horizontal_velocity(&sim.player, input, time_step)
	try_jump(sim)

	if sim.player.movement_state == .Mantling {
		update_mantle(sim, time_step)
	} else {
		if !sim.player.grounded {
			sim.player.velocity.y -= PLAYER_GRAVITY * time_step
		}

		lift := try_step(sim, time_step)
		if lift > 0.0 {
			sim.player.step_smoothing = clamp(
				sim.player.step_smoothing + lift,
				-STEP_SMOOTH_MAX,
				STEP_SMOOTH_MAX,
			)
		}
		move_player(sim, time_step)
	}
	b3.World_Step(sim.world_id, time_step, SIMULATION_SUB_STEPS)

	probe = probe_ground(sim)
	sim.player.grounded = is_grounded(sim, probe)
	snap_to_ground(sim, was_grounded)
	probe = probe_ground(sim)
	sim.player.grounded = is_grounded(sim, probe)
	if sim.player.grounded {
		sim.player.ground_normal = probe.normal
	}
	if sim.player.step_grace > 0.0 &&
	   horizontal_speed(sim.player.velocity) >= STEP_GRACE_SPEED {
		sim.player.grounded = true
	}
	if was_grounded &&
	   !sim.player.grounded &&
	   sim.player.movement_state == .None &&
	   sim.player.velocity.y <= 0.0 {
		sim.player.air_cap = max(PLAYER_WALK_SPEED, horizontal_speed(sim.player.velocity))
	}

	update_dive(sim, time_step)
	update_crouch_slide(sim, time_step)
	update_step_smoothing(&sim.player, time_step)
	sim.player.grounded_last_step = sim.player.grounded
}

simulation_snapshot :: proc(sim: ^Simulation) -> Render_Snapshot {
	eye_offset := b3.Vec3{0.0, sim.player.eye_height - sim.player.step_smoothing, 0.0}
	previous_eye_offset := b3.Vec3 {
		0.0,
		sim.player.previous_eye_height - sim.player.previous_step_smoothing,
		0.0,
	}
	return {
		position = sim.player.position,
		previous_position = sim.player.previous_position,
		eye_position = sim.player.position + eye_offset,
		previous_eye_position = sim.player.previous_position + previous_eye_offset,
		velocity = sim.player.velocity,
		yaw = sim.player.yaw,
		pitch = sim.player.pitch,
		grounded = sim.player.grounded,
		stance = sim.player.stance,
		gait = sim.player.gait,
		movement_state = sim.player.movement_state,
		step_smoothing = sim.player.step_smoothing,
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
		if box.visual_only {
			continue
		}
		create_static_box(sim.world_id, box)
	}
}

@(private)
create_static_box :: proc(world_id: b3.WorldId, box: geometry.Box) {
	body_def := b3.DefaultBodyDef()
	body_def.position = box.center
	body_def.rotation.x = box.rotation.x
	body_def.rotation.y = box.rotation.y
	body_def.rotation.z = box.rotation.z
	body_def.rotation.w = box.rotation.w
	body_id := b3.CreateBody(world_id, body_def)

	hull := b3.MakeBoxHull(box.half_extents.x, box.half_extents.y, box.half_extents.z)
	shape_def := b3.DefaultShapeDef()
	_ = b3.CreateHullShape(body_id, shape_def, &hull.base)
}
