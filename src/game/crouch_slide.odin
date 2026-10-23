#+vet explicit-allocators
package game

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

	direction := intent_direction(player, input)
	player.movement_state = .Sliding_Crouch
	player.slide_direction = direction
	player.slide_speed = PLAYER_CROUCH_SLIDE_SPEED
	player.slide_elapsed = 0.0
	set_slide_velocity(player, direction, PLAYER_CROUCH_SLIDE_SPEED)
	player.velocity.y = 0.0
	commit_stance(player, .Crouching)
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

	commit_stance(player, .Standing)
	player.movement_state = .None
	launch_jump(player)
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

	player.slide_speed = advance_slide(
		player,
		player.slide_direction,
		PLAYER_CROUCH_SPEED,
		time_step,
	)
	if player.slide_speed <= PLAYER_CROUCH_SPEED + PLAYER_SLIDE_END_EPSILON {
		player.movement_state = .None
		set_slide_velocity(player, player.slide_direction, PLAYER_CROUCH_SPEED)
	}
}
