#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"
import b3 "libs:box3d"
import game "src:game"

@(private)
approach_and_jump :: proc(sim: ^game.Simulation, approach: b3.Vec3) {
	sim.player.position = approach
	sim.player.velocity = {}
	sim.player.yaw = 0
	step(sim, game.Input_Snapshot{move_forward = 1.0}, 10)
	step(sim, game.Input_Snapshot{move_forward = 1.0, jump_pressed = true}, 1)
	step(sim, game.Input_Snapshot{move_forward = 1.0}, 4)
}

@(test)
mantle_climbs_the_walls :: proc(t: ^testing.T) {
	Case :: struct {
		approach: b3.Vec3,
		height:   f32,
	}
	cases := [2]Case {
		{game.ARENA_MANTLE_12_APPROACH, game.ARENA_MANTLE_12_HEIGHT},
		{game.ARENA_MANTLE_15_APPROACH, game.ARENA_MANTLE_15_HEIGHT},
	}
	for c in cases {
		sim := create(t)
		approach_and_jump(&sim, c.approach)
		step(&sim, game.Input_Snapshot{jump_pressed = true}, 1)
		testing.expect_value(t, sim.player.movement_state, game.Movement_State.Mantling)

		step(&sim, {}, 20)
		testing.expect_value(t, sim.player.movement_state, game.Movement_State.None)
		expect_near(t, sim.player.position.y, c.height + game.GROUND_OFFSET, 0.1, "mantle height")
		testing.expect_value(t, sim.player.stance, game.Stance.Standing)
		game.simulation_destroy(&sim)
	}
}

@(test)
holding_jump_mantles_without_a_second_press :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = game.ARENA_MANTLE_12_APPROACH
	sim.player.velocity = {}
	sim.player.yaw = 0
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 10)
	step(
		&sim,
		game.Input_Snapshot{move_forward = 1.0, jump_pressed = true, jump_held = true},
		1,
	)
	step(&sim, game.Input_Snapshot{move_forward = 1.0, jump_held = true}, 4)

	testing.expect_value(t, sim.player.movement_state, game.Movement_State.Mantling)
}

@(test)
holding_jump_without_movement_does_not_mantle :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = game.ARENA_MANTLE_12_APPROACH
	sim.player.velocity = {}
	sim.player.yaw = 0
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 10)
	step(
		&sim,
		game.Input_Snapshot{move_forward = 1.0, jump_pressed = true, jump_held = true},
		1,
	)
	step(&sim, game.Input_Snapshot{jump_held = true}, 4)

	testing.expect_value(t, sim.player.movement_state, game.Movement_State.None)
}

@(test)
holding_jump_on_flat_ground_does_not_repeat :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	step(&sim, {}, 10)
	step(&sim, game.Input_Snapshot{jump_pressed = true, jump_held = true}, 1)
	step(&sim, game.Input_Snapshot{jump_held = true}, 120)

	testing.expect(t, sim.player.grounded, "held jump did not settle")
	expect_near(t, sim.player.velocity.y, 0.0, 0.01, "held jump kept rising")
}

@(test)
mantle_onto_a_crate_tracks_the_body :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = {0.0, 0.6, 9.0}
	sim.player.velocity = {}
	sim.player.yaw = 0
	sim.player.grounded = false

	b3.Body_SetLinearVelocity(game.simulation_crate_body(&sim, 0), {0.0, 0.0, 1.0})
	step(&sim, game.Input_Snapshot{jump_pressed = true}, 1)
	testing.expect_value(t, sim.player.movement_state, game.Movement_State.Mantling)

	step(&sim, {}, 20)
	testing.expect_value(t, sim.player.movement_state, game.Movement_State.None)
	crate := game.simulation_crate_box(&sim, 0).center
	testing.expectf(
		t,
		sim.player.position.y > 0.9 && sim.player.position.y < 1.2,
		"did not mantle the crate: y=%v",
		sim.player.position.y,
	)
	testing.expectf(
		t,
		abs(sim.player.position.z - crate.z) < 0.6,
		"mantle did not follow the crate: player z=%v crate z=%v",
		sim.player.position.z,
		crate.z,
	)
}

@(test)
mantle_rejects_a_wall_above_the_limit :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = {0.0, game.GROUND_OFFSET, -18.0}
	sim.player.velocity = {}
	sim.player.yaw = 0
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 20)
	step(&sim, game.Input_Snapshot{jump_pressed = true}, 1)
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 4)
	step(&sim, game.Input_Snapshot{jump_pressed = true}, 1)

	testing.expect_value(t, sim.player.movement_state, game.Movement_State.None)
}

@(test)
mantle_rejects_a_distant_ledge :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = {game.ARENA_MANTLE_12_X, game.GROUND_OFFSET, 11.0}
	sim.player.velocity = {}
	sim.player.yaw = 0
	step(&sim, game.Input_Snapshot{jump_pressed = true}, 1)
	step(&sim, {}, 4)
	step(&sim, game.Input_Snapshot{jump_pressed = true}, 1)

	testing.expect_value(t, sim.player.movement_state, game.Movement_State.None)
}

@(test)
mantle_rejects_a_steep_ramp :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = {game.ARENA_RAMP_50_X, game.GROUND_OFFSET, 0.5}
	sim.player.velocity = {}
	sim.player.yaw = 0
	step(&sim, game.Input_Snapshot{jump_pressed = true}, 1)
	step(&sim, {}, 4)
	step(&sim, game.Input_Snapshot{jump_pressed = true}, 1)

	testing.expect_value(t, sim.player.movement_state, game.Movement_State.None)
}
