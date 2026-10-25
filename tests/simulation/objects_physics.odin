#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"

import b3 "libs:box3d"
import game "src:game"

@(test)
static_objects_do_not_fall :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	id := game.simulation_create_object(
		&sim,
		{prefab = .Platform, body_mode = .Static, center = {20, 5, 0}, yaw_rad = 0},
	)
	for _ in 0 ..< 120 {
		game.simulation_step_world(&sim, game.SIMULATION_STEP)
	}

	testing.expect_value(t, game.simulation_object_box(&sim, id).center, b3.Vec3{20, 5, 0})
}

@(test)
dynamic_objects_fall_and_settle :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	id := game.simulation_create_object(
		&sim,
		{prefab = .Small_Crate, body_mode = .Dynamic, center = {20, 5, 0}, yaw_rad = 0},
	)
	for _ in 0 ..< 240 {
		game.simulation_step_world(&sim, game.SIMULATION_STEP)
	}

	expect_near(
		t,
		game.simulation_object_box(&sim, id).center.y,
		game.prefab(.Small_Crate).half_extents.y,
		0.05,
		"small crate settle height",
	)
}

@(test)
static_object_blocks_the_player :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	_ = game.simulation_create_object(
		&sim,
		{prefab = .Wall, body_mode = .Static, center = {0, 1.5, 10}, yaw_rad = 0},
	)
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 120)

	testing.expectf(
		t,
		sim.player.position.z > 10.4,
		"player passed through the placed wall: z=%v",
		sim.player.position.z,
	)
}

@(test)
step_world_leaves_player_alone_and_settles_objects :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	id := game.simulation_create_object(
		&sim,
		{prefab = .Crate, body_mode = .Dynamic, center = {20, 4, 0}, yaw_rad = 0},
	)
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
		abs(game.simulation_object_box(&sim, id).center.y - game.prefab(.Crate).half_extents.y) <
			0.05,
		"crate did not settle: y=%v",
		game.simulation_object_box(&sim, id).center.y,
	)
}
