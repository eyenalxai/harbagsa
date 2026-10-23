#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:math"
import "core:testing"
import game "src:game"

@(test)
jump_buffers_before_landing :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	step(&sim, {}, 10)
	step(&sim, game.Input_Snapshot{jump_pressed = true}, 1)
	step(&sim, {}, 35)
	testing.expect(t, !sim.player.grounded, "player landed before the buffered jump")

	step(&sim, game.Input_Snapshot{jump_pressed = true}, 1)
	step(&sim, {}, 8)
	testing.expectf(t, sim.player.velocity.y > 0.0, "buffered jump did not fire: vy=%v", sim.player.velocity.y)
}

@(test)
coyote_time_allows_a_late_jump :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = game.ARENA_DIVE_EDGE
	sim.player.velocity = {}
	sim.player.yaw = 0
	step(&sim, {}, 2)

	for _ in 0 ..< 20 {
		step(&sim, game.Input_Snapshot{move_forward = 1.0}, 1)
		if !sim.player.grounded {
			break
		}
	}
	testing.expect(t, !sim.player.grounded, "player did not leave the dive platform")

	step(&sim, game.Input_Snapshot{jump_pressed = true}, 1)
	testing.expectf(t, sim.player.velocity.y > 1.0, "coyote jump did not fire: vy=%v", sim.player.velocity.y)
}

@(test)
sprint_jump_keeps_the_sprint_air_cap :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	step(&sim, game.Input_Snapshot{move_forward = 1.0, sprint_held = true}, 30)
	step(&sim, game.Input_Snapshot{move_forward = 1.0, sprint_held = true, jump_pressed = true}, 1)
	testing.expectf(t, sim.player.air_cap >= 8.0, "air cap is too low: %v", sim.player.air_cap)

	step(&sim, game.Input_Snapshot{move_right = 1.0}, 20)
	testing.expectf(
		t,
		horizontal_speed(sim.player.velocity) <= sim.player.air_cap + 0.01,
		"air control exceeded the cap: speed=%v cap=%v",
		horizontal_speed(sim.player.velocity),
		sim.player.air_cap,
	)
}

@(test)
jump_from_crouch_stands_first :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	step(&sim, {}, 10)
	step(&sim, game.Input_Snapshot{crouch_pressed = true}, 1)
	testing.expect_value(t, sim.player.stance, game.Stance.Crouching)

	step(&sim, game.Input_Snapshot{jump_pressed = true}, 1)
	testing.expect_value(t, sim.player.stance, game.Stance.Standing)
	testing.expectf(t, sim.player.velocity.y > 0.0, "crouch jump did not fire: vy=%v", sim.player.velocity.y)
}

@(test)
jump_from_crouch_fails_under_a_low_ceiling :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = game.ARENA_TUNNEL_122_POSITION
	sim.player.velocity = {}
	step(&sim, {}, 2)
	testing.expect_value(t, sim.player.stance, game.Stance.Crouching)

	step(&sim, game.Input_Snapshot{jump_pressed = true}, 1)
	testing.expect_value(t, sim.player.stance, game.Stance.Crouching)
	testing.expectf(t, sim.player.velocity.y < 1.0, "blocked jump gained height: vy=%v", sim.player.velocity.y)
}

@(test)
ground_snap_descends_the_twenty_degree_ramp :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = {game.ARENA_RAMP_20_X, 2.06, -6.5}
	sim.player.velocity = {}
	sim.player.yaw = math.PI
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 60)

	testing.expect(t, sim.player.grounded, "player left the ramp while descending")
	testing.expectf(t, sim.player.position.y < 1.5, "player did not descend the ramp: y=%v", sim.player.position.y)
}
