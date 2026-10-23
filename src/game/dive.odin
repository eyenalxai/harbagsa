#+vet explicit-allocators
package game

import "core:math"
import b3 "libs:box3d"

@(private)
intent_direction :: proc(player: ^Player, input: Input_Snapshot) -> b3.Vec3 {
	direction := movement_direction(player, input)
	length := b3.Length(direction)
	if length > 0.0001 {
		return direction / length
	}

	speed := horizontal_speed(player.velocity)
	if speed > 0.1 {
		return {player.velocity.x / speed, 0.0, player.velocity.z / speed}
	}

	return {-math.sin(player.yaw), 0.0, -math.cos(player.yaw)}
}

@(private)
try_dive :: proc(sim: ^Simulation, input: Input_Snapshot) -> bool {
	player := &sim.player
	if player.movement_state != .None || !input.prone_pressed {
		return false
	}

	sprint_dive :=
		player.grounded &&
		player.gait == .Sprint &&
		horizontal_speed(player.velocity) >= PLAYER_WALK_SPEED
	if !sprint_dive && player.grounded {
		return false
	}

	direction := intent_direction(player, input)
	player.movement_state = .Diving
	player.slide_direction = direction
	commit_stance(player, .Prone)
	set_slide_velocity(player, direction, PLAYER_DIVE_SPEED)
	player.jump_buffer = 0.0
	player.slide_speed = 0.0
	player.slide_elapsed = 0.0

	if sprint_dive {
		player.velocity.y = PLAYER_DIVE_HOP_SPEED
		player.grounded = false
	}
	return true
}

@(private)
start_dive_slide :: proc(player: ^Player) {
	direction := player.slide_direction
	speed := horizontal_speed(player.velocity)
	if speed > 0.1 {
		direction = {player.velocity.x / speed, 0.0, player.velocity.z / speed}
	}

	player.slide_direction = direction
	player.slide_speed = max(
		PLAYER_CRAWL_SPEED,
		PLAYER_DIVE_SPEED * PLAYER_DIVE_SLIDE_FRACTION,
	)
	set_slide_velocity(player, direction, player.slide_speed)
	player.movement_state = .Sliding_Dive
	commit_stance(player, .Prone)
}

@(private)
update_dive :: proc(sim: ^Simulation, time_step: f32) {
	player := &sim.player
	switch player.movement_state {
	case .Diving:
		if player.grounded {
			start_dive_slide(player)
		}
	case .Sliding_Dive:
		if !player.grounded {
			player.movement_state = .Diving
			return
		}
		player.slide_speed = advance_slide(
			player,
			player.slide_direction,
			PLAYER_CRAWL_SPEED,
			time_step,
		)
		if player.slide_speed <= PLAYER_CRAWL_SPEED + PLAYER_SLIDE_END_EPSILON {
			player.movement_state = .None
		}
	case .None, .Sliding_Crouch, .Mantling:
	}
}
