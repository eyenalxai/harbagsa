#+vet explicit-allocators
package game

import "core:math"
import b3 "libs:box3d"

@(private)
crouch_slide_direction :: proc(player: ^Player, input: Input_Snapshot) -> b3.Vec3 {
	direction := movement_direction(player, input)
	length := b3.Length(direction)
	if length > 0.0001 {
		return direction / length
	}

	speed := horizontal_speed(player.velocity)
	if speed > 0.1 {
		return {player.velocity.x / speed, 0.0, player.velocity.z / speed}
	}

	forward := b3.Vec3{-math.sin(player.yaw), 0.0, -math.cos(player.yaw)}
	return forward
}

@(private)
try_crouch_slide :: proc(sim: ^Simulation, input: Input_Snapshot) -> bool {
	player := &sim.player
	if player.movement_state != .None || !input.crouch_pressed {
		return false
	}
	if !player.grounded ||
	   player.gait != .Sprint ||
	   horizontal_speed(player.velocity) < PLAYER_WALK_SPEED {
		return false
	}

	direction := crouch_slide_direction(player, input)
	player.movement_state = .Sliding_Crouch
	player.slide_direction = direction
	player.slide_speed = PLAYER_CROUCH_SLIDE_SPEED
	player.slide_elapsed = 0.0
	player.velocity.x = direction.x * PLAYER_CROUCH_SLIDE_SPEED
	player.velocity.z = direction.z * PLAYER_CROUCH_SLIDE_SPEED
	player.velocity.y = 0.0
	player.crouch_engaged = true
	player.prone_engaged = false
	player.stance = .Crouching
	player.jump_buffer = 0.0
	return true
}

@(private)
try_crouch_slide_jump :: proc(sim: ^Simulation, input: Input_Snapshot) {
	player := &sim.player
	if player.movement_state != .Sliding_Crouch {
		return
	}
	if !input.jump_pressed ||
	   player.slide_elapsed < PLAYER_CROUCH_SLIDE_JUMP_DELAY ||
	   !player.grounded {
		return
	}
	if !has_headroom(sim, player.position, .Standing) {
		player.jump_buffer = 0.0
		return
	}

	player.stance = .Standing
	player.crouch_engaged = false
	player.prone_engaged = false
	player.movement_state = .None
	player.air_cap = max(PLAYER_WALK_SPEED, horizontal_speed(player.velocity))
	player.velocity.y = PLAYER_JUMP_SPEED
	player.grounded = false
	player.coyote = 0.0
	player.jump_buffer = 0.0
}

@(private)
update_crouch_slide :: proc(sim: ^Simulation, time_step: f32) {
	player := &sim.player
	if player.movement_state != .Sliding_Crouch {
		return
	}
	player.slide_elapsed += time_step
	if !player.grounded {
		return
	}

	player.slide_speed = max(
		PLAYER_CROUCH_SPEED,
		player.slide_speed - PLAYER_SLIDE_DECELERATION * time_step,
	)
	player.velocity.x = player.slide_direction.x * player.slide_speed
	player.velocity.z = player.slide_direction.z * player.slide_speed
	if player.slide_speed <= PLAYER_CROUCH_SPEED + PLAYER_SLIDE_END_EPSILON {
		player.movement_state = .None
		player.velocity.x = player.slide_direction.x * PLAYER_CROUCH_SPEED
		player.velocity.z = player.slide_direction.z * PLAYER_CROUCH_SPEED
	}
}
