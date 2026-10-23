#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:math"
import "core:testing"
import b3 "libs:box3d"
import game "src:game"

DT :: game.SIMULATION_STEP

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
horizontal_speed :: proc(velocity: b3.Vec3) -> f32 {
	horizontal := b3.Vec3{velocity.x, 0.0, velocity.z}
	return b3.Length(horizontal)
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
	expect_near(t, horizontal_speed(sim.player.velocity), game.PLAYER_WALK_SPEED, 0.01, "walk speed")
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
		horizontal_speed(sim.player.velocity),
		game.PLAYER_GROUND_ACCELERATION * DT,
		0.01,
		"first acceleration step",
	)

	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 4)
	expect_near(
		t,
		horizontal_speed(sim.player.velocity),
		game.PLAYER_WALK_SPEED,
		0.01,
		"accelerated to walk speed",
	)

	step(&sim, {}, 1)
	expect_near(
		t,
		horizontal_speed(sim.player.velocity),
		game.PLAYER_WALK_SPEED - game.PLAYER_GROUND_DECELERATION * DT,
		0.01,
		"first deceleration step",
	)

	step(&sim, {}, 5)
	expect_near(t, horizontal_speed(sim.player.velocity), 0.0, 0.01, "stopped after deceleration")
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

		speed := horizontal_speed(sim.player.velocity)
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

	straight_speed := horizontal_speed(straight.player.velocity)
	diagonal_speed := horizontal_speed(diagonal.player.velocity)
	expect_near(t, diagonal_speed, straight_speed, 0.01, "diagonal speed")

	straight_distance := horizontal_distance(game.SPAWN_POSITION, straight.player.position)
	diagonal_distance := horizontal_distance(game.SPAWN_POSITION, diagonal.player.position)
	expect_near(t, diagonal_distance, straight_distance, 0.05, "diagonal distance")
}

@(test)
wall_blocks_player :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	// Spawn is close to the +Z wall, so walking backward reaches it quickly.
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
		horizontal_speed(sim.player.velocity) < 0.1,
		"player kept moving into the wall: speed=%v",
		horizontal_speed(sim.player.velocity),
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

	testing.expectf(t, max_y > 0.5, "jump height is too low: max y=%v", max_y)
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

	start_speed := horizontal_speed(sim.player.velocity)
	testing.expectf(t, start_speed > 4.5, "player is too slow before steering: %v", start_speed)

	for _ in 0 ..< 20 {
		game.simulation_step(&sim, game.Input_Snapshot{move_right = 1.0}, DT)
		speed := horizontal_speed(sim.player.velocity)
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
snapshot_exposes_interpolation_state :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 30)
	snapshot := game.simulation_snapshot(&sim)

	testing.expect(t, snapshot.position == sim.player.position, "snapshot position is stale")
	testing.expect(t, snapshot.previous_position == sim.player.previous_position, "snapshot previous position is stale")
	expect_near(
		t,
		snapshot.eye_position.y,
		snapshot.position.y + game.PLAYER_EYE_HEIGHT,
		0.0001,
		"eye height",
	)
	testing.expect(t, snapshot.position.z < snapshot.previous_position.z, "player did not move between snapshots")
	testing.expect(t, snapshot.yaw == sim.player.yaw, "snapshot yaw is stale")
	testing.expect(t, snapshot.pitch == sim.player.pitch, "snapshot pitch is stale")
	testing.expect(t, snapshot.grounded == sim.player.grounded, "snapshot grounded state is stale")
}

@(test)
reset_returns_player_to_spawn :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	game.simulation_look(&sim, {10.0, 5.0})
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 30)
	step(&sim, game.Input_Snapshot{reset_pressed = true}, 1)

	testing.expect(t, sim.player.position == game.SPAWN_POSITION, "position is not spawn")
	testing.expect(t, sim.player.previous_position == game.SPAWN_POSITION, "previous position is not spawn")
	testing.expect(t, sim.player.velocity == b3.Vec3_zero, "velocity is not zero")
	testing.expect(t, sim.player.yaw == 0.0, "yaw is not zero")
	testing.expect(t, sim.player.pitch == 0.0, "pitch is not zero")
	testing.expect(t, !sim.player.grounded, "grounded state was not cleared")
}

@(test)
falling_below_arena_resets_player :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = {0.0, game.FALL_RESET_Y - 1.0, 0.0}
	sim.player.velocity = {1.0, -20.0, 2.0}
	step(&sim, {}, 1)

	testing.expect(t, sim.player.position == game.SPAWN_POSITION, "position is not spawn")
	testing.expect(t, sim.player.previous_position == game.SPAWN_POSITION, "previous position is not spawn")
	testing.expect(t, sim.player.velocity == b3.Vec3_zero, "velocity is not zero")
	testing.expect(t, sim.player.yaw == 0.0, "yaw is not zero")
	testing.expect(t, sim.player.pitch == 0.0, "pitch is not zero")
}
