#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"
import game "src:game"

@(test)
stance_choice_never_grows_without_headroom :: proc(t: ^testing.T) {
	testing.expect_value(t, game.choose_stance(.Standing, true, true), game.Stance.Standing)
	testing.expect_value(t, game.choose_stance(.Standing, false, true), game.Stance.Crouching)
	testing.expect_value(t, game.choose_stance(.Standing, false, false), game.Stance.Prone)
	testing.expect_value(t, game.choose_stance(.Crouching, true, false), game.Stance.Prone)
	testing.expect_value(t, game.choose_stance(.Prone, true, true), game.Stance.Prone)
}

@(test)
stance_speeds_match_the_package :: proc(t: ^testing.T) {
	expect_near(t, game.stance_speed(.Standing, .Walk), 5.0, 0.0001, "walk speed")
	expect_near(t, game.stance_speed(.Standing, .Sprint), 8.0, 0.0001, "sprint speed")
	expect_near(t, game.stance_speed(.Crouching, .Walk), 2.4, 0.0001, "crouch speed")
	expect_near(t, game.stance_speed(.Prone, .Walk), 1.2, 0.0001, "crawl speed")
}

@(test)
stances_move_in_every_direction :: proc(t: ^testing.T) {
	Case :: struct {
		stance: game.Stance,
		speed:  f32,
		crouch: bool,
		prone:  bool,
		sprint: bool,
	}
	cases := [3]Case {
		{.Standing, 8.0, false, false, true},
		{.Crouching, 2.4, true, false, false},
		{.Prone, 1.2, false, true, false},
	}
	for c in cases {
		sim := create(t)
		step(&sim, {}, 10)
		if c.crouch {
			step(&sim, game.Input_Snapshot{crouch_pressed = true}, 1)
		}
		if c.prone {
			step(&sim, game.Input_Snapshot{prone_pressed = true}, 1)
		}
		testing.expect_value(t, sim.player.stance, c.stance)

		for direction in DIRECTIONS {
			sim.player.position = game.SPAWN_POSITION
			sim.player.velocity = {}
			sim.player.yaw = 0
			step(
				&sim,
				game.Input_Snapshot {
					move_forward = direction.x,
					move_right = direction.y,
					sprint_held = c.sprint,
				},
				30,
			)
			testing.expect_value(t, sim.player.stance, c.stance)
			expect_near(t, game.horizontal_speed(sim.player.velocity), c.speed, 0.01, "stance speed")
		}
		game.simulation_destroy(&sim)
	}
}

@(test)
stance_engagement_modes_are_pure :: proc(t: ^testing.T) {
	crouch := false
	prone := false
	crouch, prone = game.engagement_step(.Hold, crouch, prone, true, true)
	testing.expect(t, crouch && !prone, "hold crouch did not engage")

	prone, crouch = game.engagement_step(.Toggle, prone, crouch, true, false)
	testing.expect(t, prone && !crouch, "toggle prone did not override crouch")

	prone, crouch = game.engagement_step(.Toggle, prone, crouch, true, false)
	testing.expect(t, !prone, "toggle prone did not release")

	crouch, prone = game.engagement_step(.Hold, crouch, prone, false, true)
	testing.expect(t, crouch, "held crouch did not return after prone release")

	engaged, requested := game.sprint_request_step(.Toggle, false, false, true)
	testing.expect(t, engaged && requested, "toggle sprint did not engage")
	engaged, requested = game.sprint_request_step(.Toggle, engaged, false, true)
	testing.expect(t, !engaged && !requested, "toggle sprint did not release")
	engaged, requested = game.sprint_request_step(.Hold, engaged, true, true)
	testing.expect(t, requested, "hold sprint did not request")
}

@(test)
sprint_auto_stands_from_crouch :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	step(&sim, {}, 10)
	step(&sim, game.Input_Snapshot{crouch_pressed = true}, 1)
	testing.expect_value(t, sim.player.stance, game.Stance.Crouching)

	step(&sim, game.Input_Snapshot{move_forward = 1.0, sprint_held = true}, 1)
	testing.expect_value(t, sim.player.stance, game.Stance.Standing)
	testing.expect_value(t, sim.player.gait, game.Gait.Sprint)
}

@(test)
headroom_drops_the_player_under_each_tunnel :: proc(t: ^testing.T) {
	Tunnel :: struct {
		position: [3]f32,
		stance:   game.Stance,
	}
	tunnels := [3]Tunnel {
		{game.ARENA_TUNNEL_135_POSITION, .Crouching},
		{game.ARENA_TUNNEL_122_POSITION, .Crouching},
		{game.ARENA_TUNNEL_090_POSITION, .Prone},
	}
	for tunnel in tunnels {
		sim := create(t)
		sim.player.position = tunnel.position
		sim.player.velocity = {}
		step(&sim, {}, 2)
		testing.expect_value(t, sim.player.stance, tunnel.stance)
		game.simulation_destroy(&sim)
	}
}

@(test)
sprint_keeps_crouch_under_a_low_ceiling :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = game.ARENA_TUNNEL_135_POSITION
	sim.player.velocity = {}
	step(&sim, {}, 2)
	testing.expect_value(t, sim.player.stance, game.Stance.Crouching)

	step(
		&sim,
		game.Input_Snapshot{move_forward = 1.0, sprint_held = true},
		30,
	)
	testing.expect_value(t, sim.player.gait, game.Gait.Walk)
	testing.expect_value(t, sim.player.stance, game.Stance.Crouching)
	expect_near(t, game.horizontal_speed(sim.player.velocity), 2.4, 0.01, "blocked sprint speed")
}

@(test)
twenty_degree_ramp_is_climbable :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = game.ARENA_RAMP_20_APPROACH
	sim.player.velocity = {}
	sim.player.yaw = 0
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 60)

	testing.expectf(t, sim.player.position.y > 0.5, "did not climb the 20 degree ramp: y=%v", sim.player.position.y)
	testing.expect(t, sim.player.grounded, "player is not grounded on the 20 degree ramp")
}

@(test)
forty_degree_ramp_is_climbable :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = game.ARENA_RAMP_40_APPROACH
	sim.player.velocity = {}
	sim.player.yaw = 0
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 60)

	testing.expectf(t, sim.player.position.y > 0.5, "did not climb the 40 degree ramp: y=%v", sim.player.position.y)
}

@(test)
fifty_degree_ramp_does_not_ground_the_player :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = game.ARENA_RAMP_50_APPROACH
	sim.player.velocity = {}
	sim.player.yaw = 0
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 60)

	testing.expectf(t, sim.player.position.y < 0.5, "climbed the 50 degree ramp: y=%v", sim.player.position.y)
}

@(test)
step_up_climbs_the_twenty_centimetre_stairs :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = game.ARENA_STAIR_APPROACH
	sim.player.velocity = {}
	sim.player.yaw = 0
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 60)

	testing.expectf(t, sim.player.position.y > 0.9, "did not climb the stairs: y=%v", sim.player.position.y)
	testing.expect(t, sim.player.grounded, "player is not grounded on the stairs")
}

@(test)
step_up_climbs_thirty_five_centimetres :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = game.ARENA_STEP_035_APPROACH
	sim.player.velocity = {}
	sim.player.yaw = 0
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 25)

	testing.expectf(t, sim.player.position.y > 0.3, "did not climb the 0.35 m step: y=%v", sim.player.position.y)
}

@(test)
step_up_rejects_fifty_centimetres :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = game.ARENA_STEP_050_APPROACH
	sim.player.velocity = {}
	sim.player.yaw = 0
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 60)

	testing.expectf(t, sim.player.position.y < 0.1, "climbed the 0.50 m step: y=%v", sim.player.position.y)
}

@(test)
movement_names_are_stable :: proc(t: ^testing.T) {
	testing.expect_value(t, game.stance_name(.Standing), "Standing")
	testing.expect_value(t, game.stance_name(.Crouching), "Crouching")
	testing.expect_value(t, game.stance_name(.Prone), "Prone")
	testing.expect_value(t, game.gait_name(.Walk), "Walk")
	testing.expect_value(t, game.gait_name(.Sprint), "Sprint")
	testing.expect_value(t, game.movement_state_name(.None), "None")
	testing.expect_value(t, game.movement_state_name(.Diving), "Diving")
	testing.expect_value(t, game.movement_state_name(.Sliding_Dive), "Sliding")
	testing.expect_value(t, game.movement_state_name(.Sliding_Crouch), "Sliding")
	testing.expect_value(t, game.movement_state_name(.Mantling), "Mantling")
}
