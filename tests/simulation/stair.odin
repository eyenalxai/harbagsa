#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:math"
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

	previous := game.spider_camera(&sim, 1.0).position
	max_delta: f32 = 0
	for _ in 0 ..< 40 {
		step(&sim, game.Input_Snapshot{move_forward = 1.0}, 1)
		position := game.spider_camera(&sim, 1.0).position
		max_delta = max(max_delta, abs(position.y - previous.y))
		previous = position
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
step_up_climbs_at_an_angle :: proc(t: ^testing.T) {
	// A diagonal approach used to land the probe ray back on the current tread,
	// so the player slid along each riser instead of climbing it.
	angles := [4]f32{-60, -45, 45, 60}
	frames := 20
	for degrees in angles {
		sim := create(t)
		defer game.simulation_destroy(&sim)

		angle := degrees * math.PI / 180.0
		drift :=
			math.sin(angle) * game.PLAYER_WALK_SPEED * f32(frames) * game.SIMULATION_STEP
		// Center the diagonal path on the tread so it stays on the staircase.
		sim.player.position = {
			game.ARENA_STAIR_X + drift * 0.5,
			game.ARENA_STAIR_RISE + game.GROUND_OFFSET,
			game.ARENA_STAIR_START_Z - 0.1,
		}
		sim.player.velocity = {}
		sim.player.yaw = angle
		step(&sim, {}, 2)
		step(&sim, game.Input_Snapshot{move_forward = 1.0}, frames)

		testing.expectf(
			t,
			sim.player.position.y > game.ARENA_STAIR_RISE * 1.5,
			"did not climb a step at %v degrees: y=%v",
			degrees,
			sim.player.position.y,
		)
		testing.expect(t, sim.player.grounded, "player is not grounded on the angled climb")
	}
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
	sim.player.camera_yaw = 3.14159265
	step(&sim, {}, 2)

	previous := game.spider_camera(&sim, 1.0).position
	max_delta: f32 = 0
	for _ in 0 ..< 60 {
		step(&sim, game.Input_Snapshot{move_forward = 1.0}, 1)
		position := game.spider_camera(&sim, 1.0).position
		max_delta = max(max_delta, abs(position.y - previous.y))
		previous = position
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
