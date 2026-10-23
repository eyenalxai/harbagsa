#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"
import b3 "libs:box3d"
import game "src:game"

@(test)
starting_scene_has_three_crates :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	testing.expect_value(t, game.simulation_crate_count(&sim), game.INITIAL_CRATE_COUNT)
	for position, index in game.INITIAL_CRATE_POSITIONS {
		box := game.simulation_crate_box(&sim, index)
		testing.expectf(
			t,
			box.center == position,
			"crate %d center is %v, want %v",
			index,
			box.center,
			position,
		)
	}
}

@(test)
add_crate_creates_body_and_box :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	center := b3.Vec3{1.0, 2.0, 3.0}
	index := game.simulation_add_crate(&sim, center, game.CRATE_HALF_EXTENTS, {1, 0, 0, 1})
	testing.expect_value(t, index, game.INITIAL_CRATE_COUNT)
	testing.expect_value(t, game.simulation_crate_count(&sim), game.INITIAL_CRATE_COUNT + 1)
	testing.expect(t, b3.Body_IsValid(game.simulation_crate_body(&sim, index)), "new crate body is invalid")
	testing.expect_value(t, game.simulation_crate_box(&sim, index).center, center)
}

@(test)
add_crate_past_cap_is_ignored :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	for _ in 0 ..< game.MAX_CRATES {
		_ = game.simulation_add_crate(&sim, {0, 50, 0}, game.CRATE_HALF_EXTENTS, {1, 1, 1, 1})
	}
	testing.expect_value(t, game.simulation_crate_count(&sim), game.MAX_CRATES)

	index := game.simulation_add_crate(&sim, {0, 50, 0}, game.CRATE_HALF_EXTENTS, {1, 1, 1, 1})
	testing.expect_value(t, index, -1)
	testing.expect_value(t, game.simulation_crate_count(&sim), game.MAX_CRATES)
}

@(test)
remove_crate_destroys_body_and_shifts_list :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	body := game.simulation_crate_body(&sim, 0)
	next_center := game.simulation_crate_box(&sim, 1).center

	testing.expect(t, game.simulation_remove_crate(&sim, 0), "remove failed")
	testing.expect(t, !b3.Body_IsValid(body), "removed crate body is still valid")
	testing.expect_value(t, game.simulation_crate_count(&sim), game.INITIAL_CRATE_COUNT - 1)
	testing.expect_value(t, game.simulation_crate_box(&sim, 0).center, next_center)
	testing.expect(t, !game.simulation_remove_crate(&sim, 99), "out-of-range remove succeeded")
}

@(test)
move_crate_sets_position_and_stops_velocity :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	body := game.simulation_crate_body(&sim, 0)
	b3.Body_SetLinearVelocity(body, {3, 4, 5})
	b3.Body_SetAngularVelocity(body, {1, 2, 3})

	target := b3.Vec3{1.0, 2.0, 3.0}
	game.simulation_move_crate(&sim, 0, target)

	testing.expect_value(t, game.simulation_crate_box(&sim, 0).center, target)
	testing.expect_value(t, b3.Body_GetLinearVelocity(body), b3.Vec3_zero)
	testing.expect_value(t, b3.Body_GetAngularVelocity(body), b3.Vec3_zero)
	testing.expect(t, b3.Body_IsAwake(body), "moved crate is asleep")
}

@(test)
reset_scene_restores_starting_crates_and_player :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	_ = game.simulation_remove_crate(&sim, 0)
	_ = game.simulation_add_crate(&sim, {5, 5, 5}, game.CRATE_HALF_EXTENTS, {1, 1, 1, 1})
	sim.player.position = {1, 2, 3}

	game.simulation_reset_scene(&sim)

	testing.expect_value(t, game.simulation_crate_count(&sim), game.INITIAL_CRATE_COUNT)
	for position, index in game.INITIAL_CRATE_POSITIONS {
		testing.expect_value(t, game.simulation_crate_box(&sim, index).center, position)
	}
	testing.expect_value(t, sim.player.position, game.SPAWN_POSITION)
}

@(test)
default_added_crates_cycle_the_palette :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	first := game.simulation_add_default_crate(&sim, {10, 0.5, 10})
	second := game.simulation_add_default_crate(&sim, {12, 0.5, 10})
	testing.expect_value(t, sim.crates[first].color, game.INITIAL_CRATE_COLORS[0])
	testing.expect_value(t, sim.crates[second].color, game.INITIAL_CRATE_COLORS[1])
}

@(test)
step_world_leaves_player_alone_and_settles_crates :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	index := game.simulation_add_crate(&sim, {0, 4, 0}, game.CRATE_HALF_EXTENTS, {1, 1, 1, 1})
	before := sim.player

	for _ in 0 ..< 120 {
		game.simulation_step_world(&sim, game.SIMULATION_STEP)
	}

	testing.expect_value(t, sim.player.position, before.position)
	testing.expect_value(t, sim.player.velocity, before.velocity)
	testing.expect_value(t, sim.player.yaw, before.yaw)
	testing.expect_value(t, sim.player.pitch, before.pitch)
	testing.expect_value(t, sim.player.grounded, before.grounded)
	testing.expectf(
		t,
		abs(game.simulation_crate_box(&sim, index).center.y - game.ARENA_CRATE_HALF_SIZE) < 0.05,
		"crate did not settle: y=%v",
		game.simulation_crate_box(&sim, index).center.y,
	)
}
