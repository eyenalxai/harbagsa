#+vet explicit-allocators
package game

import "core:math"
import b3 "libs:box3d"

Mantle_State :: struct {
	start:        b3.Vec3,
	target:       b3.Vec3,
	local_target: b3.Vec3,
	body:         b3.BodyId,
	has_body:     bool,
	elapsed:      f32,
	clearance:    f32,
}

@(private)
try_mantle :: proc(sim: ^Simulation, input: Input_Snapshot) -> bool {
	player := &sim.player
	if player.movement_state != .None || player.grounded || !input.jump_pressed {
		return false
	}

	direction := intent_direction(player, input)
	start := player.position
	capsule := player_capsule(player.stance)
	forward_distance: f32 = PLAYER_RADIUS + MANTLE_REACH

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

	up_distance: f32 = MANTLE_MAX_HEIGHT + 0.1
	up_fraction := b3.World_CastMover(
		sim.world_id,
		start,
		capsule,
		b3.Vec3{0.0, up_distance, 0.0},
		b3.DefaultQueryFilter(),
		nil,
		nil,
	)
	if up_fraction < 0.99 {
		return false
	}

	lifted := start + b3.Vec3{0.0, up_distance * up_fraction, 0.0}
	across_distance: f32 = max(
		f32(MANTLE_ACROSS_DISTANCE),
		forward_distance * (1.0 - forward_fraction) + PLAYER_RADIUS,
	)
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
	down_distance: f32 = MANTLE_MAX_HEIGHT + MANTLE_DOWN_EXTRA
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
	probe := probe_ground_at(sim, candidate, down_distance)
	if !probe.hit || probe.normal.y < GROUND_NORMAL_THRESHOLD {
		return false
	}

	clearance := slope_clearance(probe.normal)
	target := candidate + b3.Vec3{0.0, clearance + GROUND_OFFSET, 0.0}
	height := target.y - start.y
	if height < MANTLE_MIN_HEIGHT || height > MANTLE_MAX_HEIGHT {
		return false
	}

	target_stance := Stance.Standing
	if player.crouch_engaged {
		target_stance = .Crouching
	} else if !has_headroom(sim, target, .Standing) {
		target_stance = .Crouching
	}
	if target_stance == .Crouching && !has_headroom(sim, target, .Crouching) {
		return false
	}

	body_id := b3.Shape_GetBody(probe.shape_id)
	is_dynamic := b3.Body_IsValid(body_id) && b3.Body_GetType(body_id) == .dynamicBody

	player.mantle.start = start
	player.mantle.target = target
	player.mantle.clearance = clearance
	player.mantle.elapsed = 0.0
	player.mantle.has_body = is_dynamic
	player.mantle.body = body_id
	if is_dynamic {
		player.mantle.local_target = b3.Body_GetLocalPoint(body_id, candidate)
	}

	player.movement_state = .Mantling
	player.stance = target_stance
	if target_stance == .Standing {
		player.crouch_engaged = false
		player.prone_engaged = false
	}
	player.velocity = {}
	player.grounded = false
	player.jump_buffer = 0.0
	player.coyote = 0.0
	player.slide_speed = 0.0
	player.slide_elapsed = 0.0
	return true
}

@(private)
update_mantle :: proc(sim: ^Simulation, time_step: f32) {
	player := &sim.player
	if player.movement_state != .Mantling {
		return
	}

	player.mantle.elapsed += time_step
	target := player.mantle.target
	if player.mantle.has_body && b3.Body_IsValid(player.mantle.body) {
		surface := b3.Body_GetWorldPoint(player.mantle.body, player.mantle.local_target)
		target = surface + b3.Vec3{0.0, player.mantle.clearance + GROUND_OFFSET, 0.0}
	}

	t := clamp(player.mantle.elapsed / MANTLE_DURATION, 0.0, 1.0)
	if t >= 1.0 {
		player.position = target
		player.velocity = {}
		player.movement_state = .None
		return
	}

	if t < MANTLE_UP_FRACTION {
		u := math.smoothstep(f32(0.0), f32(MANTLE_UP_FRACTION), t)
		player.position = {
			player.mantle.start.x,
			math.lerp(player.mantle.start.y, target.y, u),
			player.mantle.start.z,
		}
	} else {
		u := math.smoothstep(f32(MANTLE_UP_FRACTION), f32(1.0), t)
		player.position = {
			math.lerp(player.mantle.start.x, target.x, u),
			target.y,
			math.lerp(player.mantle.start.z, target.z, u),
		}
	}
}
