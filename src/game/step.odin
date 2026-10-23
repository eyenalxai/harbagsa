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
	capsule := player_capsule(player.stance)
	start := player.position
	forward_distance := max(speed * time_step, 0.05) + STEP_SKIN

	forward_fraction := b3.World_CastMover(
		sim.world_id,
		start,
		capsule,
		direction * forward_distance,
		b3.DefaultQueryFilter(),
		nil,
		nil,
	)
	if forward_fraction >= 1.0 {
		return false
	}

	up_fraction := b3.World_CastMover(
		sim.world_id,
		start,
		capsule,
		b3.Vec3{0.0, STEP_HEIGHT, 0.0},
		b3.DefaultQueryFilter(),
		nil,
		nil,
	)
	if up_fraction < 0.99 {
		return false
	}

	lifted := start + b3.Vec3{0.0, STEP_HEIGHT * up_fraction, 0.0}
	across_distance := forward_distance * (1.0 - forward_fraction) + PLAYER_RADIUS * 0.5
	across_fraction := b3.World_CastMover(
		sim.world_id,
		lifted,
		capsule,
		direction * across_distance,
		b3.DefaultQueryFilter(),
		nil,
		nil,
	)
	if across_fraction < 0.01 {
		return false
	}

	across := lifted + direction * (across_distance * across_fraction)
	down_distance: f32 = STEP_HEIGHT + STEP_DOWN_EXTRA
	down_fraction := b3.World_CastMover(
		sim.world_id,
		across,
		capsule,
		b3.Vec3{0.0, -down_distance, 0.0},
		b3.DefaultQueryFilter(),
		nil,
		nil,
	)
	if down_fraction >= 1.0 {
		return false
	}

	candidate := across + b3.Vec3{0.0, -down_distance * down_fraction, 0.0}
	probe := probe_ground_at(sim, candidate, STEP_HEIGHT + STEP_DOWN_EXTRA)
	if !probe.hit || probe.normal.y < GROUND_NORMAL_THRESHOLD {
		return false
	}

	clearance := slope_clearance(probe.normal)
	target := candidate + b3.Vec3{0.0, clearance + GROUND_OFFSET, 0.0}
	step_height := candidate.y - start.y
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
