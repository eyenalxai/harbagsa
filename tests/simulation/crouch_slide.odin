#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"
import game "src:game"

@(test)
crouch_slide_requires_sprint :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	step(&sim, {}, 10)
	step(&sim, game.Input_Snapshot{move_forward = 1.0, crouch_pressed = true}, 1)
	testing.expect_value(t, sim.player.movement_state, game.Movement_State.None)
	testing.expect_value(t, sim.player.stance, game.Stance.Crouching)
}

@(test)
crouch_slide_starts_at_ten_and_ends_crouched :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	step(&sim, game.Input_Snapshot{move_forward = 1.0, sprint_held = true}, 30)
	testing.expect_value(t, sim.player.gait, game.Gait.Sprint)
	step(
		&sim,
		game.Input_Snapshot{move_forward = 1.0, sprint_held = true, crouch_pressed = true},
		1,
	)
	testing.expect_value(t, sim.player.movement_state, game.Movement_State.Sliding_Crouch)
	testing.expect_value(t, sim.player.stance, game.Stance.Crouching)
	testing.expectf(
		t,
		horizontal_speed(sim.player.velocity) > 9.5,
		"crouch slide did not start fast: speed=%v",
		horizontal_speed(sim.player.velocity),
	)

	for _ in 0 ..< 120 {
		game.simulation_step(&sim, {}, DT)
		if sim.player.movement_state == .None {
			break
		}
	}
	testing.expect_value(t, sim.player.movement_state, game.Movement_State.None)
	testing.expect_value(t, sim.player.stance, game.Stance.Crouching)
	expect_near(t, horizontal_speed(sim.player.velocity), 2.4, 0.1, "crouch slide end")
}

@(test)
crouch_slide_jump_cancels_after_the_delay :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	step(&sim, game.Input_Snapshot{move_forward = 1.0, sprint_held = true}, 30)
	step(
		&sim,
		game.Input_Snapshot{move_forward = 1.0, sprint_held = true, crouch_pressed = true},
		1,
	)
	testing.expect_value(t, sim.player.movement_state, game.Movement_State.Sliding_Crouch)

	step(&sim, game.Input_Snapshot{jump_pressed = true}, 1)
	testing.expect_value(t, sim.player.movement_state, game.Movement_State.Sliding_Crouch)

	step(&sim, {}, 10)
	step(&sim, game.Input_Snapshot{jump_pressed = true}, 1)
	testing.expect_value(t, sim.player.movement_state, game.Movement_State.None)
	testing.expect_value(t, sim.player.stance, game.Stance.Standing)
	testing.expectf(t, sim.player.velocity.y > 5.5, "slide jump did not jump: vy=%v", sim.player.velocity.y)
}

@(test)
crouch_slide_jump_fails_under_a_low_ceiling :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = game.ARENA_TUNNEL_122_POSITION
	sim.player.velocity = {0.0, 0.0, -2.4}
	sim.player.stance = .Crouching
	sim.player.crouch_engaged = true
	sim.player.grounded = true
	sim.player.movement_state = .Sliding_Crouch
	sim.player.slide_elapsed = 0.2
	sim.player.slide_direction = {0.0, 0.0, -1.0}
	sim.player.slide_speed = 5.0

	step(&sim, game.Input_Snapshot{jump_pressed = true}, 1)
	testing.expect_value(t, sim.player.movement_state, game.Movement_State.Sliding_Crouch)
	testing.expectf(t, sim.player.velocity.y < 1.0, "blocked slide jump gained height: vy=%v", sim.player.velocity.y)
}

@(test)
crouch_slide_works_in_eight_directions :: proc(t: ^testing.T) {
	directions := [8][2]f32 {
		{1.0, 0.0},
		{1.0, 1.0},
		{0.0, 1.0},
		{-1.0, 1.0},
		{-1.0, 0.0},
		{-1.0, -1.0},
		{0.0, -1.0},
		{1.0, -1.0},
	}
	for direction in directions {
		sim := create(t)
		step(
			&sim,
			game.Input_Snapshot {
				move_forward = direction.x,
				move_right = direction.y,
				sprint_held = true,
			},
			30,
		)
		step(
			&sim,
			game.Input_Snapshot {
				move_forward = direction.x,
				move_right = direction.y,
				sprint_held = true,
				crouch_pressed = true,
			},
			1,
		)
		testing.expect_value(t, sim.player.movement_state, game.Movement_State.Sliding_Crouch)
		testing.expectf(
			t,
			horizontal_speed(sim.player.velocity) > 9.5,
			"crouch slide did not start fast: %v",
			horizontal_speed(sim.player.velocity),
		)
		game.simulation_destroy(&sim)
	}
}
