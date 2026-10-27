#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"

import b3 "libs:box3d"
import game "src:game"

@(private)
leg_hip :: proc(sim: ^game.Simulation, index: int) -> b3.Vec3 {
	center := sim.player.position + b3.Vec3{0.0, game.SPIDER_BODY_HEIGHT, 0.0}
	return center + game.rotate_yaw(game.LEG_HIPS[index], sim.player.yaw)
}

@(test)
spider_starts_on_eight_planted_feet :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	step(&sim, {}, 4)

	testing.expect_value(t, game.spider_planted_count(&sim.player), game.LEG_COUNT)
	for leg, index in sim.player.legs {
		testing.expectf(t, leg.planted, "leg %d is not planted", index)
		testing.expectf(t, leg.foot.y < 0.1, "leg %d is not on the floor: y=%v", index, leg.foot.y)
		reach := b3.Length(leg.foot - leg_hip(&sim, index))
		testing.expectf(
			t,
			reach <= game.LEG_MAX_REACH + 0.001,
			"leg %d is out of reach: %v",
			index,
			reach,
		)
	}
}

@(test)
planted_feet_do_not_move_between_steps :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	step(&sim, {}, 4)
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 10)

	held := false
	for _ in 0 ..< 30 {
		before := sim.player.legs
		step(&sim, game.Input_Snapshot{move_forward = 1.0}, 1)
		for leg, index in before {
			if !leg.planted || !sim.player.legs[index].planted {
				continue
			}
			testing.expectf(
				t,
				leg.foot == sim.player.legs[index].foot,
				"planted leg %d moved between steps: %v -> %v",
				index,
				leg.foot,
				sim.player.legs[index].foot,
			)
			held = true
		}
	}
	testing.expect(t, held, "no foot stayed planted across a step")
}

@(test)
spider_steps_one_tetrapod_group_at_a_time :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	step(&sim, {}, 4)

	group_swung := [2]bool{false, false}
	for _ in 0 ..< 120 {
		step(&sim, game.Input_Snapshot{move_forward = 1.0}, 1)
		swinging := [2]int{0, 0}
		for leg, index in sim.player.legs {
			if leg.swinging {
				swinging[game.LEG_GROUP[index]] += 1
			}
		}
		testing.expectf(
			t,
			swinging[0] == 0 || swinging[1] == 0,
			"both tetrapod groups swing together: %v",
			swinging,
		)
		for group in 0 ..< 2 {
			if swinging[group] > 0 {
				group_swung[group] = true
			}
		}
	}
	testing.expect(t, group_swung[0] && group_swung[1], "one tetrapod group never stepped")
}

@(test)
spider_tucks_and_replants_after_a_jump :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	step(&sim, {}, 4)
	step(&sim, game.Input_Snapshot{jump_pressed = true}, 1)
	step(&sim, {}, 10)
	testing.expect(t, !sim.player.grounded, "the spider did not leave the ground")
	testing.expect_value(t, game.spider_planted_count(&sim.player), 0)

	for leg in sim.player.legs {
		testing.expectf(
			t,
			leg.foot.y > sim.player.position.y,
			"an airborne leg hangs below the feet: %v",
			leg.foot.y,
		)
	}

	step(&sim, {}, 90)
	testing.expect(t, sim.player.grounded, "the spider did not land")
	testing.expectf(
		t,
		game.spider_planted_count(&sim.player) >= game.LEG_COUNT - 2,
		"the spider did not replant: %d",
		game.spider_planted_count(&sim.player),
	)
}

@(test)
ik_pulls_an_out_of_reach_foot_inside_the_chain :: proc(t: ^testing.T) {
	hip := b3.Vec3{0.0, 0.6, 0.0}
	far := b3.Vec3{4.0, -1.0, 0.0}
	knee, reached := game.spider_leg_ik(hip, far, {0.0, 1.0, 0.0})
	testing.expectf(
		t,
		b3.Length(reached - hip) <= game.LEG_MAX_REACH + 0.0001,
		"the solved foot is out of reach: %v",
		b3.Length(reached - hip),
	)
	testing.expectf(
		t,
		b3.Length(knee - hip) <= game.LEG_FEMUR_LENGTH + 0.0001,
		"the knee left the femur: %v",
		b3.Length(knee - hip),
	)
	testing.expect(t, knee.y > reached.y, "the knee bends below the foot")
}

@(test)
ik_keeps_the_bones_connected :: proc(t: ^testing.T) {
	hip := b3.Vec3{0.0, 0.5, 0.0}
	foot := b3.Vec3{0.8, 0.0, 0.3}
	knee, reached := game.spider_leg_ik(hip, foot, {0.3, 1.0, 0.0})
	expect_near(t, b3.Length(knee - hip), game.LEG_FEMUR_LENGTH, 0.001, "femur length")
	expect_near(t, b3.Length(reached - knee), game.LEG_TIBIA_LENGTH, 0.001, "tibia length")
}

@(test)
planted_feet_rest_on_the_floor :: proc(t: ^testing.T) {
	cases := [2]bool{false, true}
	for sprint in cases {
		sim := create(t)
		step(&sim, {}, 4)
		step(
			&sim,
			game.Input_Snapshot{move_forward = 1.0, sprint_held = sprint},
			120,
		)
		for leg, index in sim.player.legs {
			if !leg.planted {
				continue
			}
			testing.expectf(
				t,
				leg.foot.y < 0.06,
				"sprint=%v: leg %d is planted above the floor: y=%v",
				sprint,
				index,
				leg.foot.y,
			)
			testing.expectf(
				t,
				b3.Length(leg.foot - leg_hip(&sim, index)) <= game.LEG_MAX_REACH + 0.01,
				"sprint=%v: planted leg %d is out of reach: %v",
				sprint,
				index,
				b3.Length(leg.foot - leg_hip(&sim, index)),
			)
		}
		game.simulation_destroy(&sim)
	}
}
