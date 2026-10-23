#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:math"
import "core:testing"
import b3 "libs:box3d"
import game "src:game"

@(test)
ground_velocity_keeps_the_stance_speed_on_the_plane :: proc(t: ^testing.T) {
	slope: f32 = f32(math.PI / 180.0) * 40.0
	normal := b3.Vec3{0.0, f32(math.cos(slope)), f32(math.sin(slope))}
	speed: f32 = game.PLAYER_WALK_SPEED
	cos_slope: f32 = f32(math.cos(slope))
	sin_slope: f32 = f32(math.sin(slope))

	flat := game.ground_velocity({0.0, 0.0, -1.0}, {0.0, 1.0, 0.0}, speed)
	expect_near(t, b3.Length(flat), speed, 0.0001, "flat speed")
	expect_near(t, flat.z, -speed, 0.0001, "flat direction")

	uphill := game.ground_velocity({0.0, 0.0, -1.0}, normal, speed)
	expect_near(t, b3.Length(uphill), speed, 0.0001, "uphill 3D speed")
	expect_near(t, uphill.z, -speed * cos_slope, 0.0001, "uphill horizontal speed")
	expect_near(t, uphill.y, speed * sin_slope, 0.0001, "uphill vertical speed")

	across := game.ground_velocity({1.0, 0.0, 0.0}, normal, speed)
	expect_near(t, across.x, speed, 0.0001, "across-slope speed")
	expect_near(t, across.y, 0.0, 0.0001, "across-slope lift")

	downhill := game.ground_velocity({0.0, 0.0, 1.0}, normal, speed)
	expect_near(t, b3.Length(downhill), speed, 0.0001, "downhill 3D speed")
	expect_near(t, downhill.y, -speed * sin_slope, 0.0001, "downhill vertical speed")
}

@(test)
ramp_horizontal_speed_matches_the_slope :: proc(t: ^testing.T) {
	Case :: struct {
		name:  string,
		start: b3.Vec3,
		angle: f32,
	}
	cases := [2]Case {
		{"20", game.ARENA_RAMP_20_APPROACH, f32(20.0 * math.PI / 180.0)},
		{"40", game.ARENA_RAMP_40_APPROACH, f32(40.0 * math.PI / 180.0)},
	}
	for c in cases {
		sim := create(t)
		sim.player.position = c.start
		sim.player.velocity = {}
		sim.player.yaw = 0
		step(&sim, {}, 2)

		prev := sim.player.position
		max_horizontal: f32 = 0
		max_rise: f32 = 0
		on_ramp := false
		for _ in 0 ..< 80 {
			step(&sim, game.Input_Snapshot{move_forward = 1.0}, 1)
			delta := sim.player.position - prev
			horizontal := b3.Vec2{delta.x, delta.z}
			horizontal_distance := b3.Length(horizontal)
			if sim.player.position.y > 0.25 && sim.player.position.y < 1.6 {
				on_ramp = true
				max_horizontal = max(max_horizontal, horizontal_distance)
				max_rise = max(max_rise, abs(delta.y))
			}
			prev = sim.player.position
		}

		testing.expect(t, on_ramp, "player never reached the ramp")
		expect_near(
			t,
			max_horizontal,
			f32(game.PLAYER_WALK_SPEED) * f32(math.cos(c.angle)) * DT,
			0.015,
			"ramp horizontal step",
		)
		testing.expectf(
			t,
			max_rise < 0.12,
			"ramp produced a step-up pop on the %s degree ramp: %v",
			c.name,
			max_rise,
		)
		game.simulation_destroy(&sim)
	}
}

@(test)
ramp_ground_speed_is_the_stance_speed :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = game.ARENA_RAMP_40_APPROACH
	sim.player.velocity = {}
	sim.player.yaw = 0
	step(&sim, {}, 2)
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 40)

	testing.expect(t, sim.player.position.y > 0.4, "player is not on the 40 degree ramp")
	testing.expect(t, sim.player.grounded, "player is not grounded on the ramp")
	testing.expectf(
		t,
		game.horizontal_speed(sim.player.velocity) < game.PLAYER_WALK_SPEED - 0.5,
		"horizontal speed did not drop on the ramp: %v",
		game.horizontal_speed(sim.player.velocity),
	)
}
