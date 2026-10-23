#+vet explicit-allocators
package game

import "core:math"
import b3 "libs:box3d"

Step_Probe :: struct {
	hit:    bool,
	top:    f32,
	normal: b3.Vec3,
}

// A step is a near-vertical riser with a near-flat top. A walkable ramp has a
// sloped top, so it must be walked, not stepped onto.
@(private)
probe_step :: proc(
	sim: ^Simulation,
	start, direction: b3.Vec3,
	forward_distance: f32,
) -> Step_Probe {
	if sim.player.ground_normal.y < STEP_FLAT_NORMAL {
		return {}
	}

	capsule := player_capsule(sim.player.stance)
	query := b3.DefaultQueryFilter()
	forward_fraction := b3.World_CastMover(
		sim.world_id,
		start,
		capsule,
		direction * forward_distance,
		query,
		nil,
		nil,
	)
	if forward_fraction >= 1.0 {
		return {}
	}

	up_fraction := b3.World_CastMover(
		sim.world_id,
		start,
		capsule,
		b3.Vec3{0.0, STEP_HEIGHT + STEP_SKIN, 0.0},
		query,
		nil,
		nil,
	)
	if up_fraction < 0.99 {
		return {}
	}

	contact := start + direction * (forward_distance * forward_fraction)
	probe_point := contact + direction * (PLAYER_RADIUS + STEP_SKIN)
	ray_origin := b3.Pos {
		probe_point.x,
		start.y + STEP_HEIGHT + STEP_PROBE_LIFT,
		probe_point.z,
	}
	down_distance: f32 = STEP_HEIGHT + STEP_PROBE_LIFT + STEP_PROBE_DROP
	ray := b3.World_CastRayClosest(
		sim.world_id,
		ray_origin,
		b3.Vec3{0.0, -down_distance, 0.0},
		query,
	)
	if !ray.hit || ray.normal.y < STEP_FLAT_NORMAL {
		return {}
	}

	top := b3.ToVec3(ray.point).y
	height := top - start.y
	if height < STEP_MIN_HEIGHT || height > STEP_HEIGHT {
		return {}
	}
	return {hit = true, top = top, normal = ray.normal}
}

// Lifts the capsule onto the step. The normal collide-and-slide move supplies
// the horizontal travel for the same fixed step, so a step never adds a lurch.
@(private)
try_step :: proc(sim: ^Simulation, time_step: f32) -> f32 {
	player := &sim.player
	if player.movement_state != .None ||
	   !player.grounded ||
	   player.velocity.y > 0.0 ||
	   player.on_steep_slope {
		return 0.0
	}

	speed := horizontal_speed(player.velocity)
	if speed < 0.1 {
		return 0.0
	}
	direction := b3.Vec3{player.velocity.x / speed, 0.0, player.velocity.z / speed}
	forward_distance := max(speed * time_step, 0.05) + STEP_SKIN
	probe := probe_step(sim, player.position, direction, forward_distance)
	if !probe.hit {
		return 0.0
	}

	step_height := probe.top - player.position.y
	if step_height < STEP_MIN_HEIGHT || step_height > STEP_HEIGHT {
		return 0.0
	}
	lift := step_height + GROUND_OFFSET

	player.position.y += lift
	player.velocity.y = 0.0
	player.ground_normal = probe.normal
	player.step_grace = STEP_GRACE_TIME
	return lift
}

// Ground snap also follows a descending staircase while the player was recently
// on the ground. The camera offset hides the vertical correction; the capsule
// itself stays on the next tread.
snap_to_ground :: proc(sim: ^Simulation, was_grounded: bool) {
	player := &sim.player
	if player.velocity.y > 0.0 && !player.grounded {
		return
	}
	if player.movement_state == .Diving || player.movement_state == .Mantling {
		return
	}
	if player.step_grace > 0.0 &&
	   horizontal_speed(player.velocity) >= STEP_GRACE_SPEED {
		return
	}
	if !was_grounded && !player.grounded && !player.grounded_last_step {
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
	drop := player.position.y - target_y
	if player.grounded_last_step &&
	   drop >= STEP_MIN_HEIGHT &&
	   drop <= STEP_HEIGHT + GROUND_OFFSET &&
	   probe.normal.y >= STEP_FLAT_NORMAL {
		player.step_smoothing = clamp(
			player.step_smoothing - drop,
			-STEP_SMOOTH_MAX,
			STEP_SMOOTH_MAX,
		)
		player.step_grace = STEP_GRACE_TIME
	}

	player.position.y = target_y
	if was_grounded {
		player.velocity -= probe.normal * b3.Dot(player.velocity, probe.normal)
	} else {
		player.velocity.y = 0.0
	}
	player.grounded = true
	player.ground_normal = probe.normal
}

@(private)
update_step_smoothing :: proc(player: ^Player, time_step: f32) {
	alpha := 1.0 - math.exp(-STEP_SMOOTH_RATE * time_step)
	player.step_smoothing -= player.step_smoothing * alpha
	if abs(player.step_smoothing) < STEP_SMOOTH_EPSILON {
		player.step_smoothing = 0.0
	}
}
