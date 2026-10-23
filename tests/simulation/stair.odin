#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"
import game "src:game"

@(test)
stair_step_up_does_not_lurch_forward :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = game.ARENA_STAIR_APPROACH
	sim.player.velocity = {}
	sim.player.yaw = 0
	step(&sim, {}, 2)

	max_horizontal: f32 = 0
	for _ in 0 ..< 35 {
		before := sim.player.position
		step(&sim, game.Input_Snapshot{move_forward = 1.0}, 1)
		max_horizontal = max(max_horizontal, horizontal_distance(before, sim.player.position))
	}
	testing.expectf(
		t,
		max_horizontal <= game.PLAYER_WALK_SPEED * game.SIMULATION_STEP + 0.04,
		"step-up lurched forward: %v",
		max_horizontal,
	)
}

@(test)
stair_camera_y_is_smoothed :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = game.ARENA_STAIR_APPROACH
	sim.player.velocity = {}
	sim.player.yaw = 0
	step(&sim, {}, 2)

	previous := game.simulation_snapshot(&sim).eye_position
	max_delta: f32 = 0
	for _ in 0 ..< 40 {
		step(&sim, game.Input_Snapshot{move_forward = 1.0}, 1)
		snapshot := game.simulation_snapshot(&sim)
		max_delta = max(max_delta, abs(snapshot.eye_position.y - previous.y))
		previous = snapshot.eye_position
	}
	testing.expectf(t, max_delta <= 0.10, "camera jumped on the stairs: %v", max_delta)
	testing.expectf(
		t,
		game.horizontal_speed(sim.player.velocity) > 4.5,
		"player slowed on the stairs: %v",
		game.horizontal_speed(sim.player.velocity),
	)
}

@(test)
stair_descent_camera_y_is_smoothed :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = {
		game.ARENA_STAIR_X,
		game.ARENA_STAIR_TOP + game.GROUND_OFFSET,
		-1.0,
	}
	sim.player.velocity = {}
	sim.player.yaw = 3.14159265
	step(&sim, {}, 2)

	previous := game.simulation_snapshot(&sim).eye_position
	max_delta: f32 = 0
	for _ in 0 ..< 60 {
		step(&sim, game.Input_Snapshot{move_forward = 1.0}, 1)
		snapshot := game.simulation_snapshot(&sim)
		max_delta = max(max_delta, abs(snapshot.eye_position.y - previous.y))
		previous = snapshot.eye_position
	}
	testing.expectf(t, max_delta <= 0.10, "camera jumped on the way down: %v", max_delta)
}

@(test)
step_up_does_not_launch_the_player_on_a_ramp :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = game.ARENA_RAMP_20_APPROACH
	sim.player.velocity = {}
	sim.player.yaw = 0
	step(&sim, {}, 2)

	max_rise: f32 = 0
	max_speed: f32 = 0
	for _ in 0 ..< 45 {
		before := sim.player.position
		step(&sim, game.Input_Snapshot{move_forward = 1.0}, 1)
		max_rise = max(max_rise, sim.player.position.y - before.y)
		max_speed = max(max_speed, game.horizontal_speed(sim.player.velocity))
	}
	testing.expectf(t, max_rise < 0.10, "ramp produced a step-up rise: %v", max_rise)
	testing.expectf(
		t,
		max_speed <= game.PLAYER_WALK_SPEED + 0.10,
		"ramp step-up gained speed: %v",
		max_speed,
	)
}

@(test)
jump_at_a_stair_edge_keeps_its_velocity :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = {game.ARENA_STAIR_X, game.GROUND_OFFSET, 3.67}
	sim.player.velocity = {}
	sim.player.yaw = 0
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 1)

	step(
		&sim,
		game.Input_Snapshot{move_forward = 1.0, jump_pressed = true},
		1,
	)
	testing.expectf(t, sim.player.velocity.y > 1.0, "jump was swallowed: vy=%v", sim.player.velocity.y)
	testing.expectf(
		t,
		sim.player.position.y < 0.15,
		"jump was replaced by a step: y=%v",
		sim.player.position.y,
	)
}
