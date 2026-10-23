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
	if player.movement_state != .None || player.grounded {
		return false
	}
	if !input.jump_pressed && !input.jump_held {
		return false
	}
	// A held jump is a continuous check, so require movement intent. A fresh
	// press keeps the old deliberate behavior and works without movement input.
	if !input.jump_pressed && input.move_forward == 0.0 && input.move_right == 0.0 {
		return false
	}

	direction := intent_direction(player, input)
	start := player.position
	path := Ledge_Path {
		forward_distance = PLAYER_RADIUS + MANTLE_REACH,
		up_distance = MANTLE_MAX_HEIGHT + 0.1,
		across_scale = 1.0,
		min_across = MANTLE_ACROSS_DISTANCE,
		down_distance = MANTLE_MAX_HEIGHT + MANTLE_DOWN_EXTRA,
	}

	ray := b3.World_CastRayClosest(
		sim.world_id,
		start + b3.Vec3{0.0, 0.1, 0.0},
		direction * path.forward_distance,
		b3.DefaultQueryFilter(),
	)
	if !ray.hit || b3.Dot(ray.normal, direction) > -0.1 {
		return false
	}

	ledge, ok := probe_ledge(sim, start, direction, path)
	if !ok {
		return false
	}

	clearance := slope_clearance(ledge.ground.normal)
	target := ledge.candidate + b3.Vec3{0.0, clearance + GROUND_OFFSET, 0.0}
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

	body_id := b3.Shape_GetBody(ledge.ground.shape_id)
	is_dynamic := b3.Body_IsValid(body_id) && b3.Body_GetType(body_id) == .dynamicBody

	player.mantle.start = start
	player.mantle.target = target
	player.mantle.clearance = clearance
	player.mantle.elapsed = 0.0
	player.mantle.has_body = is_dynamic
	player.mantle.body = body_id
	if is_dynamic {
		player.mantle.local_target = b3.Body_GetLocalPoint(body_id, ledge.candidate)
	}

	player.movement_state = .Mantling
	if target_stance == .Standing {
		commit_stance(player, .Standing)
	} else {
		player.stance = .Crouching
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
