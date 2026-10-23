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
mantle_climbs_the_one_point_two_wall :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	approach_and_jump(&sim, game.ARENA_MANTLE_12_APPROACH)
	step(&sim, game.Input_Snapshot{jump_pressed = true}, 1)
	testing.expect_value(t, sim.player.movement_state, game.Movement_State.Mantling)

	step(&sim, {}, 20)
	testing.expect_value(t, sim.player.movement_state, game.Movement_State.None)
	testing.expectf(
		t,
		sim.player.position.y > 1.1 && sim.player.position.y < 1.3,
		"did not mantle the 1.2 m wall: y=%v",
		sim.player.position.y,
	)
	testing.expect_value(t, sim.player.stance, game.Stance.Standing)
}

@(test)
mantle_climbs_the_one_point_five_wall :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	approach_and_jump(&sim, game.ARENA_MANTLE_15_APPROACH)
	step(&sim, game.Input_Snapshot{jump_pressed = true}, 1)
	testing.expect_value(t, sim.player.movement_state, game.Movement_State.Mantling)

	step(&sim, {}, 20)
	testing.expect_value(t, sim.player.movement_state, game.Movement_State.None)
	testing.expectf(
		t,
		sim.player.position.y > 1.4 && sim.player.position.y < 1.6,
		"did not mantle the 1.5 m wall: y=%v",
		sim.player.position.y,
	)
}

@(test)
mantle_onto_a_crate_tracks_the_body :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = {0.0, 0.6, 9.0}
	sim.player.velocity = {}
	sim.player.yaw = 0
	sim.player.grounded = false

	b3.Body_SetLinearVelocity(sim.crates[0], {0.0, 0.0, 1.0})
	step(&sim, game.Input_Snapshot{jump_pressed = true}, 1)
	testing.expect_value(t, sim.player.movement_state, game.Movement_State.Mantling)

	step(&sim, {}, 20)
	testing.expect_value(t, sim.player.movement_state, game.Movement_State.None)
	crate := game.simulation_crate_position(&sim, 0)
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
