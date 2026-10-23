#+vet explicit-allocators
package game

import b3 "libs:box3d"

@(private)
try_step :: proc(sim: ^Simulation, time_step: f32) -> bool {
	player := &sim.player
	speed := horizontal_speed(player.velocity)
	if speed < 0.1 {
		return false
	}
	direction := b3.Vec3{player.velocity.x / speed, 0.0, player.velocity.z / speed}
	start := player.position
	path := Ledge_Path {
		forward_distance = max(speed * time_step, 0.05) + STEP_SKIN,
		up_distance = STEP_HEIGHT,
		across_scale = 0.5,
		min_across = 0.0,
		down_distance = STEP_HEIGHT + STEP_DOWN_EXTRA,
	}

	ledge, ok := probe_ledge(sim, start, direction, path)
	if !ok {
		return false
	}

	clearance := slope_clearance(ledge.ground.normal)
	target := ledge.candidate + b3.Vec3{0.0, clearance + GROUND_OFFSET, 0.0}
	step_height := ledge.candidate.y - start.y
	if step_height < STEP_MIN_HEIGHT || step_height > STEP_HEIGHT + 0.001 {
		return false
	}

	player.position = target
	player.velocity.y = 0.0
	return true
}

// The snap lifts a penetrating foot back to the ground offset and follows a
// descending walkable surface. It never climbs a ledge.
snap_to_ground :: proc(sim: ^Simulation, was_grounded: bool) {
	player := &sim.player
	if player.velocity.y > 0.0 && !player.grounded {
		return
	}
	if player.movement_state == .Diving || player.movement_state == .Mantling {
		return
	}
	if !was_grounded && !player.grounded {
		return
	}

	probe := probe_ground(sim, GROUND_SNAP_DISTANCE + GROUND_PROBE_LIFT)
	if !probe.hit || probe.normal.y < GROUND_NORMAL_THRESHOLD {
		return
	}
	clearance := slope_clearance(probe.normal)
	if probe.distance - clearance > GROUND_SNAP_DISTANCE {
		return
	}

	target_y := player.position.y - probe.distance + clearance + GROUND_OFFSET

	player.position.y = target_y
	player.velocity.y = 0.0
	player.grounded = true
}
