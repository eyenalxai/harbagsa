#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:math"
import "core:testing"
import game "src:game"

@(test)
gait_speeds_match_the_package :: proc(t: ^testing.T) {
	expect_near(t, game.gait_speed(.Walk), 5.0, 0.0001, "walk speed")
	expect_near(t, game.gait_speed(.Sprint), 8.0, 0.0001, "sprint speed")
}

@(test)
walk_moves_in_every_direction :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	step(&sim, {}, 10)

	for direction in DIRECTIONS {
		sim.player.position = game.SPAWN_POSITION
		sim.player.velocity = {}
		sim.player.camera_yaw = 0
		start := sim.player.position
		step(
			&sim,
			game.Input_Snapshot {
				move_forward = direction.x,
				move_right = direction.y,
			},
			30,
		)
		expect_near(
			t,
			game.horizontal_speed(sim.player.velocity),
			game.PLAYER_WALK_SPEED,
			0.01,
			"walk speed",
		)
		testing.expectf(
			t,
			horizontal_distance(start, sim.player.position) > 0.5,
			"player did not move: %v",
			horizontal_distance(start, sim.player.position),
		)
	}
}

@(test)
sprint_is_faster_than_walk :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	// A clear lane along +X at the spawn row, so the pushable crates do not slow
	// the speed assertion.
	sim.player.position = {-18.0, 0.05, 14.0}
	sim.player.camera_yaw = -math.PI / 2.0
	step(&sim, {}, 10)
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 60)
	expect_near(
		t,
		game.horizontal_speed(sim.player.velocity),
		game.PLAYER_WALK_SPEED,
		0.01,
		"walk speed",
	)

	step(&sim, game.Input_Snapshot{move_forward = 1.0, sprint_held = true}, 60)
	testing.expect_value(t, sim.player.gait, game.Gait.Sprint)
	expect_near(
		t,
		game.horizontal_speed(sim.player.velocity),
		game.PLAYER_SPRINT_SPEED,
		0.01,
		"sprint speed",
	)
}

@(test)
body_faces_the_movement_direction :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	step(&sim, {}, 10)

	// Strafe right with the camera at zero yaw. The body turns to face +X, which
	// is a yaw of -90 degrees in the local-forward convention.
	step(&sim, game.Input_Snapshot{move_right = 1.0}, 40)
	expect_near(t, sim.player.yaw, -1.5707963, 0.02, "body yaw after a right strafe")
}

@(test)
sprint_toggle_holds_between_steps :: proc(t: ^testing.T) {
	sim := create(t)
	sim.settings.sprint_mode = .Toggle
	defer game.simulation_destroy(&sim)

	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 10)
	step(&sim, game.Input_Snapshot{move_forward = 1.0, sprint_pressed = true}, 1)
	testing.expect_value(t, sim.player.gait, game.Gait.Sprint)

	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 30)
	testing.expect_value(t, sim.player.sprint_toggled, true)

	step(&sim, game.Input_Snapshot{move_forward = 1.0, sprint_pressed = true}, 1)
	testing.expect_value(t, sim.player.gait, game.Gait.Walk)
}

@(test)
twenty_degree_ramp_is_climbable :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = game.ARENA_RAMP_20_APPROACH
	sim.player.velocity = {}
	sim.player.camera_yaw = 0
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 60)

	testing.expectf(t, sim.player.position.y > 0.5, "did not climb the 20 degree ramp: y=%v", sim.player.position.y)
	testing.expect(t, sim.player.grounded, "player is not grounded on the 20 degree ramp")
}

@(test)
forty_degree_ramp_is_climbable :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = game.ARENA_RAMP_40_APPROACH
	sim.player.velocity = {}
	sim.player.camera_yaw = 0
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 60)

	testing.expectf(t, sim.player.position.y > 0.5, "did not climb the 40 degree ramp: y=%v", sim.player.position.y)
}

@(test)
fifty_degree_ramp_does_not_ground_the_player :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = game.ARENA_RAMP_50_APPROACH
	sim.player.velocity = {}
	sim.player.camera_yaw = 0
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 60)

	testing.expectf(t, sim.player.position.y < 0.5, "climbed the 50 degree ramp: y=%v", sim.player.position.y)
}

@(test)
step_up_climbs_the_twenty_centimetre_stairs :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = game.ARENA_STAIR_APPROACH
	sim.player.velocity = {}
	sim.player.camera_yaw = 0
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 60)

	testing.expectf(t, sim.player.position.y > 0.9, "did not climb the stairs: y=%v", sim.player.position.y)
	testing.expect(t, sim.player.grounded, "player is not grounded on the stairs")
}

@(test)
step_up_climbs_thirty_five_centimetres :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = game.ARENA_STEP_035_APPROACH
	sim.player.velocity = {}
	sim.player.camera_yaw = 0
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 25)

	testing.expectf(t, sim.player.position.y > 0.3, "did not climb the 0.35 m step: y=%v", sim.player.position.y)
}

@(test)
step_up_rejects_fifty_centimetres :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = game.ARENA_STEP_050_APPROACH
	sim.player.velocity = {}
	sim.player.camera_yaw = 0
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 60)

	testing.expectf(t, sim.player.position.y < 0.1, "climbed the 0.50 m step: y=%v", sim.player.position.y)
}

@(test)
movement_names_are_stable :: proc(t: ^testing.T) {
	testing.expect_value(t, game.gait_name(.Walk), "Walk")
	testing.expect_value(t, game.gait_name(.Sprint), "Sprint")
}
