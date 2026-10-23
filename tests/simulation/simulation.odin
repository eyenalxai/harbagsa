#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:math"
import "core:testing"
import b3 "libs:box3d"
import game "src:game"

DT :: game.SIMULATION_STEP

DIRECTIONS :: [8][2]f32 {
	{1.0, 0.0},
	{1.0, 1.0},
	{0.0, 1.0},
	{-1.0, 1.0},
	{-1.0, 0.0},
	{-1.0, -1.0},
	{0.0, -1.0},
	{1.0, -1.0},
}

@(private)
create :: proc(t: ^testing.T) -> game.Simulation {
	sim := game.simulation_create()
	testing.expect(t, game.simulation_is_valid(&sim), "simulation world is invalid")
	return sim
}

@(private)
step :: proc(sim: ^game.Simulation, input: game.Input_Snapshot, count: int) {
	for _ in 0 ..< count {
		game.simulation_step(sim, input, DT)
	}
}

@(private)
horizontal_distance :: proc(from, to: b3.Vec3) -> f32 {
	delta := to - from
	horizontal := b3.Vec3{delta.x, 0.0, delta.z}
	return b3.Length(horizontal)
}

@(private)
expect_near :: proc(t: ^testing.T, actual, expected, tolerance: f32, message: string) {
	testing.expectf(
		t,
		abs(actual - expected) <= tolerance,
		"%s: got %v, want %v (+-%v)",
		message,
		actual,
		expected,
		tolerance,
	)
}

@(test)
walk_forward_moves_along_facing :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 60)

	testing.expectf(
		t,
		sim.player.position.z < game.SPAWN_POSITION.z - 4.0,
		"player did not walk forward: z=%v",
		sim.player.position.z,
	)
	expect_near(t, sim.player.position.x, game.SPAWN_POSITION.x, 0.001, "x drift")
	expect_near(t, game.horizontal_speed(sim.player.velocity), game.PLAYER_WALK_SPEED, 0.01, "walk speed")
}

@(test)
walk_follows_camera_yaw :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	turn := b3.Vec2{-math.PI / 2.0 / game.YAW_SENSITIVITY, 0.0}
	game.simulation_look(&sim, turn)
	expect_near(t, sim.player.yaw, math.PI / 2.0, 0.0001, "yaw")

	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 30)

	testing.expectf(
		t,
		sim.player.position.x < game.SPAWN_POSITION.x - 1.0,
		"player did not walk along yaw: x=%v",
		sim.player.position.x,
	)
	expect_near(t, sim.player.position.z, game.SPAWN_POSITION.z, 0.05, "z drift after turning")
}

@(test)
walk_accelerates_and_decelerates :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	step(&sim, {}, 10)
	testing.expect(t, sim.player.grounded, "player is not grounded before walking")

	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 1)
	expect_near(
		t,
		game.horizontal_speed(sim.player.velocity),
		game.PLAYER_GROUND_ACCELERATION * DT,
		0.01,
		"first acceleration step",
	)

	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 4)
	expect_near(
		t,
		game.horizontal_speed(sim.player.velocity),
		game.PLAYER_WALK_SPEED,
		0.01,
		"accelerated to walk speed",
	)

	step(&sim, {}, 1)
	expect_near(
		t,
		game.horizontal_speed(sim.player.velocity),
		game.PLAYER_WALK_SPEED - game.PLAYER_GROUND_DECELERATION * DT,
		0.01,
		"first deceleration step",
	)

	step(&sim, {}, 5)
	expect_near(t, game.horizontal_speed(sim.player.velocity), 0.0, 0.01, "stopped after deceleration")
}

@(test)
walk_in_eight_directions :: proc(t: ^testing.T) {
	Direction :: struct {
		forward: f32,
		right:   f32,
		dx:      f32,
		dz:      f32,
	}
	directions := [8]Direction{
		{1.0, 0.0, 0.0, -1.0},
		{-1.0, 0.0, 0.0, 1.0},
		{0.0, -1.0, -1.0, 0.0},
		{0.0, 1.0, 1.0, 0.0},
		{1.0, -1.0, -0.70710678, -0.70710678},
		{1.0, 1.0, 0.70710678, -0.70710678},
		{-1.0, -1.0, -0.70710678, 0.70710678},
		{-1.0, 1.0, 0.70710678, 0.70710678},
	}

	for direction in directions {
		sim := create(t)
		step(
			&sim,
			game.Input_Snapshot{move_forward = direction.forward, move_right = direction.right},
			30,
		)

		speed := game.horizontal_speed(sim.player.velocity)
		expect_near(t, speed, game.PLAYER_WALK_SPEED, 0.01, "direction speed")

		displacement := sim.player.position - game.SPAWN_POSITION
		distance := horizontal_distance(game.SPAWN_POSITION, sim.player.position)
		testing.expectf(t, distance > 1.0, "direction did not move: distance=%v", distance)
		expect_near(t, displacement.x / distance, direction.dx, 0.02, "direction x")
		expect_near(t, displacement.z / distance, direction.dz, 0.02, "direction z")

		game.simulation_destroy(&sim)
	}
}

@(test)
diagonal_speed_equals_straight_speed :: proc(t: ^testing.T) {
	straight := create(t)
	defer game.simulation_destroy(&straight)

	diagonal := create(t)
	defer game.simulation_destroy(&diagonal)

	step(&straight, game.Input_Snapshot{move_forward = 1.0}, 60)
	step(&diagonal, game.Input_Snapshot{move_forward = 1.0, move_right = 1.0}, 60)

	straight_speed := game.horizontal_speed(straight.player.velocity)
	diagonal_speed := game.horizontal_speed(diagonal.player.velocity)
	expect_near(t, diagonal_speed, straight_speed, 0.01, "diagonal speed")

	straight_distance := horizontal_distance(game.SPAWN_POSITION, straight.player.position)
	diagonal_distance := horizontal_distance(game.SPAWN_POSITION, diagonal.player.position)
	expect_near(t, diagonal_distance, straight_distance, 0.05, "diagonal distance")
}

@(test)
wall_blocks_player :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	step(&sim, game.Input_Snapshot{move_forward = -1.0}, 180)

	testing.expectf(
		t,
		sim.player.position.z < game.ARENA_HALF_SIZE,
		"player passed through the wall: z=%v",
		sim.player.position.z,
	)
	testing.expectf(
		t,
		sim.player.position.z > game.ARENA_HALF_SIZE - 1.0,
		"player stopped short of the wall: z=%v",
		sim.player.position.z,
	)
	testing.expectf(
		t,
		game.horizontal_speed(sim.player.velocity) < 0.1,
		"player kept moving into the wall: speed=%v",
		game.horizontal_speed(sim.player.velocity),
	)
}

@(test)
player_pushes_crate :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	crate_start := game.simulation_crate_position(&sim, 0)
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 120)
	crate_end := game.simulation_crate_position(&sim, 0)

	testing.expectf(
		t,
		sim.player.position.y < 0.2,
		"player stepped onto the crate: y=%v",
		sim.player.position.y,
	)
	testing.expectf(
		t,
		crate_end.z < crate_start.z - 0.25,
		"crate did not move forward: start z=%v end z=%v",
		crate_start.z,
		crate_end.z,
	)
	testing.expectf(
		t,
		abs(crate_end.x - crate_start.x) < 0.5,
		"crate slid sideways: start x=%v end x=%v",
		crate_start.x,
		crate_end.x,
	)
}
