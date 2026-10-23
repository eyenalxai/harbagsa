#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"
import game "src:game"

@(private)
air_dive :: proc(sim: ^game.Simulation, forward, right: f32) {
	step(sim, {}, 10)
	step(sim, game.Input_Snapshot{move_forward = forward, move_right = right, jump_pressed = true}, 1)
	step(sim, game.Input_Snapshot{move_forward = forward, move_right = right}, 3)
	step(
		sim,
		game.Input_Snapshot {
			move_forward = forward,
			move_right = right,
			prone_pressed = true,
		},
		1,
	)
}

@(test)
air_dive_locks_steering_and_lands_prone :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	air_dive(&sim, 1.0, 0.0)
	testing.expect_value(t, sim.player.movement_state, game.Movement_State.Diving)
	testing.expect_value(t, sim.player.stance, game.Stance.Prone)
	expect_near(t, game.horizontal_speed(sim.player.velocity), 11.0, 0.01, "dive speed")
	testing.expectf(t, sim.player.velocity.x * sim.player.velocity.x < 0.01, "dive gained sideways speed: vx=%v", sim.player.velocity.x)

	step(&sim, game.Input_Snapshot{move_right = 1.0}, 10)
	testing.expectf(t, abs(sim.player.velocity.x) < 0.01, "dive steered: vx=%v", sim.player.velocity.x)
	testing.expect_value(t, sim.player.movement_state, game.Movement_State.Diving)

	for _ in 0 ..< 120 {
		game.simulation_step(&sim, {}, DT)
		if sim.player.movement_state == .None {
			break
		}
	}
	testing.expect_value(t, sim.player.movement_state, game.Movement_State.None)
	testing.expect_value(t, sim.player.stance, game.Stance.Prone)
}

@(test)
dive_slide_starts_fast_and_ends_at_crawl_speed :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	air_dive(&sim, 1.0, 0.0)
	for _ in 0 ..< 120 {
		game.simulation_step(&sim, {}, DT)
		if sim.player.movement_state == .Sliding_Dive {
			break
		}
	}
	testing.expect_value(t, sim.player.movement_state, game.Movement_State.Sliding_Dive)
	expect_near(t, game.horizontal_speed(sim.player.velocity), 6.05, 0.05, "dive slide start")

	for _ in 0 ..< 120 {
		game.simulation_step(&sim, {}, DT)
		if sim.player.movement_state == .None {
			break
		}
	}
	testing.expect_value(t, sim.player.movement_state, game.Movement_State.None)
	testing.expect_value(t, sim.player.stance, game.Stance.Prone)
	expect_near(t, game.horizontal_speed(sim.player.velocity), 1.2, 0.1, "dive slide end")
}

@(test)
sprint_dive_hops_and_requires_sprint :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	step(&sim, {}, 10)
	step(&sim, game.Input_Snapshot{prone_pressed = true}, 1)
	testing.expect_value(t, sim.player.movement_state, game.Movement_State.None)
	testing.expect_value(t, sim.player.stance, game.Stance.Prone)

	game.simulation_reset(&sim)
	step(&sim, game.Input_Snapshot{move_forward = 1.0, sprint_held = true}, 30)
	testing.expect_value(t, sim.player.gait, game.Gait.Sprint)

	step(&sim, game.Input_Snapshot{move_forward = 1.0, sprint_held = true, prone_pressed = true}, 1)
	testing.expect_value(t, sim.player.movement_state, game.Movement_State.Diving)
	testing.expect_value(t, sim.player.stance, game.Stance.Prone)
	expect_near(t, game.horizontal_speed(sim.player.velocity), 11.0, 0.01, "sprint dive speed")
	testing.expectf(t, sim.player.velocity.y > 0.0, "sprint dive did not hop: vy=%v", sim.player.velocity.y)
}

@(test)
jump_cannot_cancel_a_dive :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	air_dive(&sim, 1.0, 0.0)
	testing.expect_value(t, sim.player.movement_state, game.Movement_State.Diving)
	step(&sim, game.Input_Snapshot{jump_pressed = true}, 1)
	testing.expect_value(t, sim.player.movement_state, game.Movement_State.Diving)
	testing.expectf(t, sim.player.velocity.y < 6.0, "jump cancelled the dive: vy=%v", sim.player.velocity.y)
}

@(test)
dive_works_in_eight_directions :: proc(t: ^testing.T) {
	for direction in DIRECTIONS {
		sim := create(t)
		air_dive(&sim, direction.x, direction.y)
		testing.expect_value(t, sim.player.movement_state, game.Movement_State.Diving)
		expect_near(t, game.horizontal_speed(sim.player.velocity), 11.0, 0.01, "dive speed")
		game.simulation_destroy(&sim)
	}
}
