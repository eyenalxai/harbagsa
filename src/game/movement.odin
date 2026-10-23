#+vet explicit-allocators
package game

import b3 "libs:box3d"

@(private)
update_jump_timers :: proc(sim: ^Simulation, input: Input_Snapshot, time_step: f32) {
	player := &sim.player
	player.jump_buffer = max(player.jump_buffer - time_step, 0.0)
	if input.jump_pressed && player.movement_state == .None {
		player.jump_buffer = PLAYER_JUMP_BUFFER
	}

	if player.grounded {
		player.coyote = PLAYER_COYOTE_TIME
	} else {
		player.coyote = max(player.coyote - time_step, 0.0)
	}
}

@(private)
launch_jump :: proc(player: ^Player) {
	player.air_cap = max(PLAYER_WALK_SPEED, horizontal_speed(player.velocity))
	player.velocity.y = PLAYER_JUMP_SPEED
	player.grounded = false
	player.coyote = 0.0
	player.jump_buffer = 0.0
	player.step_grace = 0.0
}

@(private)
decay_slide_speed :: proc(speed, minimum, time_step: f32) -> f32 {
	return max(minimum, speed - PLAYER_SLIDE_DECELERATION * time_step)
}

@(private)
set_slide_velocity :: proc(player: ^Player, direction: b3.Vec3, speed: f32) {
	player.velocity.x = direction.x * speed
	player.velocity.z = direction.z * speed
}

@(private)
advance_slide :: proc(player: ^Player, direction: b3.Vec3, minimum, time_step: f32) -> f32 {
	speed := decay_slide_speed(player.slide_speed, minimum, time_step)
	set_slide_velocity(player, direction, speed)
	return speed
}

@(private)
try_jump :: proc(sim: ^Simulation) {
	player := &sim.player
	if player.movement_state != .None {
		return
	}
	if player.jump_buffer <= 0.0 {
		return
	}
	if !player.grounded && player.coyote <= 0.0 {
		return
	}

	if player.stance != .Standing {
		if !has_headroom(sim, player.position, .Standing) {
			player.jump_buffer = 0.0
			return
		}
		commit_stance(player, .Standing)
	}

	launch_jump(player)
}
