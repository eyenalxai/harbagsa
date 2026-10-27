#+vet explicit-allocators
package game

@(private)
update_jump_timers :: proc(sim: ^Simulation, input: Input_Snapshot, time_step: f32) {
	player := &sim.player
	player.jump_buffer = max(player.jump_buffer - time_step, 0.0)
	if input.jump_pressed {
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
try_jump :: proc(sim: ^Simulation) {
	player := &sim.player
	if player.jump_buffer <= 0.0 {
		return
	}
	if !player.grounded && player.coyote <= 0.0 {
		return
	}
	launch_jump(player)
}
