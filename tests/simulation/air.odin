#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"
import game "src:game"

@(test)
gravity_returns_player_to_floor_after_jump :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	step(&sim, {}, 10)
	testing.expect(t, sim.player.grounded, "player is not grounded before the jump")

	step(&sim, game.Input_Snapshot{jump_pressed = true}, 1)
	testing.expect(t, !sim.player.grounded, "player is still grounded after the jump")

	max_y := sim.player.position.y
	for _ in 0 ..< 120 {
		game.simulation_step(&sim, {}, DT)
		max_y = max(max_y, sim.player.position.y)
	}

	testing.expectf(t, max_y > 0.9, "jump height is too low: max y=%v", max_y)
	testing.expectf(
		t,
		sim.player.position.y < 0.1,
		"player did not return to the floor: y=%v",
		sim.player.position.y,
	)
	testing.expect(t, sim.player.grounded, "player is not grounded after landing")
}

@(test)
jump_requires_ground :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	step(&sim, {}, 10)
	step(&sim, game.Input_Snapshot{jump_pressed = true}, 1)
	testing.expect(t, !sim.player.grounded, "player is still grounded after the jump")

	step(&sim, {}, 10)
	velocity_before := sim.player.velocity.y
	testing.expectf(t, velocity_before > 0.0, "player is not rising: vy=%v", velocity_before)

	step(&sim, game.Input_Snapshot{jump_pressed = true}, 1)
	testing.expectf(
		t,
		sim.player.velocity.y < velocity_before,
		"mid-air jump added upward velocity: before=%v after=%v",
		velocity_before,
		sim.player.velocity.y,
	)
	testing.expect(t, !sim.player.grounded, "player is grounded in mid-air")
}

@(test)
air_control_steers_without_speed_gain :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 30)
	step(&sim, game.Input_Snapshot{move_forward = 1.0, jump_pressed = true}, 1)
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 5)
	testing.expect(t, !sim.player.grounded, "player is not airborne")

	start_speed := game.horizontal_speed(sim.player.velocity)
	testing.expectf(t, start_speed > 4.5, "player is too slow before steering: %v", start_speed)

	for _ in 0 ..< 20 {
		game.simulation_step(&sim, game.Input_Snapshot{move_right = 1.0}, DT)
		speed := game.horizontal_speed(sim.player.velocity)
		testing.expectf(
			t,
			speed <= game.PLAYER_WALK_SPEED + 0.01,
			"air control gained speed: %v",
			speed,
		)
	}

	testing.expectf(
		t,
		sim.player.velocity.x > 1.0,
		"air control did not steer: vx=%v",
		sim.player.velocity.x,
	)
	testing.expect(t, !sim.player.grounded, "player landed during air control")
}

@(test)
standing_jump_can_steer_to_the_air_cap :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	step(&sim, {}, 10)
	step(&sim, game.Input_Snapshot{jump_pressed = true}, 1)
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 30)

	speed := game.horizontal_speed(sim.player.velocity)
	testing.expectf(
		t,
		speed > 4.0 && speed <= game.PLAYER_WALK_SPEED + 0.01,
		"standing jump air control did not reach the cap: speed=%v",
		speed,
	)
}
