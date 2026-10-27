#+vet explicit-allocators
#+vet !unused-procedures // the harness calls simulation_face; the game binary does not
package game

import "core:mem"

import b3 "libs:box3d"

import "src:geometry"

// Jump and reset are frame edges: apply them on one fixed step. Look is a
// separate call so it works when no fixed step runs.
Input_Snapshot :: struct {
	move_forward:   f32,
	move_right:     f32,
	sprint_held:    bool,
	sprint_pressed: bool,
	jump_pressed:   bool,
	reset_pressed:  bool,
}

Leg_Snapshot :: struct {
	foot:          b3.Vec3,
	previous_foot: b3.Vec3,
	planted:       bool,
}

Render_Snapshot :: struct {
	position:                b3.Vec3,
	previous_position:       b3.Vec3,
	velocity:                b3.Vec3,
	camera_yaw:              f32,
	camera_pitch:            f32,
	body_yaw:                f32,
	previous_body_yaw:       f32,
	grounded:                bool,
	gait:                    Gait,
	step_smoothing:          f32,
	previous_step_smoothing: f32,
	legs:                    [LEG_COUNT]Leg_Snapshot,
}

Simulation :: struct {
	allocator:      mem.Allocator,
	world_id:       b3.WorldId,
	player:         Player,
	objects:        [dynamic]Placed_Object,
	light_scratch:  [dynamic]Active_Light,
	next_object_id: Object_Id,
	time:           f32,
	settings:       Settings,
}

simulation_create :: proc(allocator: mem.Allocator) -> Simulation {
	sim: Simulation
	sim.allocator = allocator
	sim.objects = make([dynamic]Placed_Object, 0, 0, allocator)
	sim.light_scratch = make([dynamic]Active_Light, 0, 0, allocator)
	sim.settings = settings_default()

	world_def := b3.DefaultWorldDef()
	world_def.gravity = {0.0, -PLAYER_GRAVITY, 0.0}
	sim.world_id = b3.CreateWorld(world_def)
	if !b3.World_IsValid(sim.world_id) {
		return sim
	}

	create_arena(&sim)
	simulation_reset_objects(&sim)
	simulation_reset(&sim)
	return sim
}

simulation_destroy :: proc(sim: ^Simulation) {
	if b3.World_IsValid(sim.world_id) {
		b3.DestroyWorld(sim.world_id)
	}
	if sim.objects != nil {
		delete(sim.objects)
	}
	if sim.light_scratch != nil {
		delete(sim.light_scratch)
	}
	sim^ = {}
}

simulation_is_valid :: proc(sim: ^Simulation) -> bool {
	return b3.World_IsValid(sim.world_id)
}

simulation_reset :: proc(sim: ^Simulation) {
	player_place(&sim.player, SPAWN_POSITION, 0.0, CAMERA_DEFAULT_PITCH)
	sim.player.gait = .Walk
	sim.player.sprint_toggled = false
	sim.player.sprint_wanted = false
	spider_plant_legs(sim)
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
	sim.player.previous_yaw = sim.player.yaw
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

	update_sprint_input(&sim.player, input, sim.settings.sprint_mode)
	sim.player.gait = sim.player.sprint_wanted ? .Sprint : .Walk

	update_jump_timers(sim, input, time_step)

	// Use ground acceleration on the jump frame too. The jump only changes the
	// vertical velocity; the horizontal controller still has the floor.
	update_horizontal_velocity(&sim.player, input, time_step)
	try_jump(sim)

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
	simulation_step_world(sim, time_step)

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
	if was_grounded && !sim.player.grounded && sim.player.velocity.y <= 0.0 {
		sim.player.air_cap = max(PLAYER_WALK_SPEED, horizontal_speed(sim.player.velocity))
	}

	update_step_smoothing(&sim.player, time_step)
	update_body_yaw(&sim.player, time_step)
	spider_update_legs(sim, time_step)
	sim.player.grounded_last_step = sim.player.grounded
}

simulation_snapshot :: proc(sim: ^Simulation) -> Render_Snapshot {
	snapshot := Render_Snapshot {
		position = sim.player.position,
		previous_position = sim.player.previous_position,
		velocity = sim.player.velocity,
		camera_yaw = sim.player.camera_yaw,
		camera_pitch = sim.player.camera_pitch,
		body_yaw = sim.player.yaw,
		previous_body_yaw = sim.player.previous_yaw,
		grounded = sim.player.grounded,
		gait = sim.player.gait,
		step_smoothing = sim.player.step_smoothing,
		previous_step_smoothing = sim.player.previous_step_smoothing,
	}
	for leg, index in sim.player.legs {
		snapshot.legs[index] = {
			foot = leg.foot,
			previous_foot = leg.previous_foot,
			planted = leg.planted,
		}
	}
	return snapshot
}

snapshot_planted_count :: proc(snapshot: Render_Snapshot) -> int {
	count := 0
	for leg in snapshot.legs {
		if leg.planted {
			count += 1
		}
	}
	return count
}

// The debug mode keeps the placed objects alive while the player is not
// simulated. Time advances here only, so a caller that keeps the player still
// and a caller that moves it share one clock.
simulation_step_world :: proc(sim: ^Simulation, time_step: f32) {
	if !b3.World_IsValid(sim.world_id) || time_step <= 0.0 {
		return
	}
	sim.time += time_step
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
	_ = create_box_body(
		world_id,
		.staticBody,
		box.center,
		transmute(b3.Quat)box.rotation,
		box.half_extents,
		0.0,
	)
}

// The harness aims the camera, not the body. The body keeps its heading until
// the movement input turns it.
simulation_face :: proc(sim: ^Simulation, yaw, pitch: f32) {
	sim.player.camera_yaw = b3.UnwindAngle(yaw)
	sim.player.camera_pitch = clamp(pitch, CAMERA_PITCH_MIN, CAMERA_PITCH_MAX)
}
