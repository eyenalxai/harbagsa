#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"

import b3 "libs:box3d"
import game "src:game"

@(test)
third_person_camera_sits_behind_the_body :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	step(&sim, {}, 4)
	sim.player.camera_pitch = 0.0

	camera := game.spider_camera(&sim, 1.0)
	pivot :=
		sim.player.position +
		b3.Vec3{0.0, game.SPIDER_BODY_HEIGHT + game.CAMERA_PIVOT_RISE, 0.0}
	testing.expectf(
		t,
		abs(b3.Length(camera.position - pivot) - game.CAMERA_DISTANCE) < 0.01,
		"the arm is not at its length: %v",
		b3.Length(camera.position - pivot),
	)
	testing.expectf(t, camera.position.z > pivot.z, "the camera is not behind the spider")
	testing.expect_value(t, camera.yaw, sim.player.camera_yaw)
	testing.expect_value(t, camera.pitch, sim.player.camera_pitch)
}

@(test)
camera_pitch_is_clamped :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	game.simulation_look(&sim, {0.0, -100000.0})
	testing.expect_value(t, sim.player.camera_pitch, game.CAMERA_PITCH_MAX)
	game.simulation_look(&sim, {0.0, 100000.0})
	testing.expect_value(t, sim.player.camera_pitch, game.CAMERA_PITCH_MIN)
}

@(test)
camera_pulls_in_before_a_wall :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	game.player_place(&sim.player, {0.0, 0.05, 19.0}, 0.0, 0.0)
	game.simulation_face(&sim, 0.0, 0.0)
	step(&sim, {}, 2)

	camera := game.spider_camera(&sim, 1.0)
	pivot :=
		sim.player.position +
		b3.Vec3{0.0, game.SPIDER_BODY_HEIGHT + game.CAMERA_PIVOT_RISE, 0.0}
	arm := b3.Length(camera.position - pivot)
	testing.expectf(t, arm < game.CAMERA_DISTANCE - 0.5, "the arm crossed the wall: %v", arm)
	testing.expectf(
		t,
		camera.position.z < game.ARENA_HALF_SIZE,
		"the camera is inside the wall: z=%v",
		camera.position.z,
	)
	testing.expectf(t, arm >= game.CAMERA_MIN_DISTANCE - 0.01, "the arm is below the minimum: %v", arm)
}

@(test)
camera_stays_above_the_floor_when_looking_up :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	game.player_place(&sim.player, game.SPAWN_POSITION, 0.0, 0.0)
	sim.player.camera_pitch = game.CAMERA_PITCH_MAX
	step(&sim, {}, 2)

	camera := game.spider_camera(&sim, 1.0)
	testing.expectf(t, camera.position.y > 0.0, "the camera went under the floor: %v", camera.position.y)
}

@(test)
camera_interpolates_with_the_body :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 20)

	previous := game.spider_camera(&sim, 0.0).position
	current := game.spider_camera(&sim, 1.0).position
	mid := game.spider_camera(&sim, 0.5).position
	expected := previous + (current - previous) * 0.5
	testing.expectf(
		t,
		b3.Length(mid - expected) < 0.0001,
		"the camera midpoint is off: %v",
		b3.Length(mid - expected),
	)
	testing.expectf(
		t,
		b3.Length(current - previous) > 0.0001,
		"the camera did not move with the body",
	)
}

@(test)
camera_lowers_under_a_low_ceiling :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	game.player_place(&sim.player, game.ARENA_TUNNEL_090_POSITION, 0.0, 0.0)
	game.simulation_face(&sim, 0.0, -0.5)
	step(&sim, {}, 4)

	camera := game.spider_camera(&sim, 1.0)
	testing.expectf(
		t,
		camera.position.y < game.ARENA_TUNNEL_090_CLEARANCE,
		"the camera is above the tunnel: %v",
		camera.position.y,
	)
	testing.expectf(t, camera.position.y > 0.2, "the camera fell through the floor: %v", camera.position.y)
	testing.expectf(t, camera.pitch >= 0.0, "the tunnel view still looks down: %v", camera.pitch)
}
