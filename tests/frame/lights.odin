#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package frame_test

import "core:testing"

import "src:frame"
import "src:game"
import "src:renderer"

@(test)
build_leaves_the_frame_without_point_lights :: proc(t: ^testing.T) {
	sim, debug, hud, scratch := create_state(t)
	defer frame.scratch_destroy(&scratch)
	defer game.simulation_destroy(&sim)
	scene := frame.build(&sim, &debug, {}, nil, &hud, &scratch)
	testing.expect_value(t, len(scene.lights), 0)
	for box in scene.boxes {
		testing.expect_value(t, box.emissive, f32(0))
	}
}

@(test)
frame_keeps_every_lamp_and_the_rest_emissive :: proc(t: ^testing.T) {
	sim, debug, hud, scratch := create_state(t)
	defer frame.scratch_destroy(&scratch)
	defer game.simulation_destroy(&sim)
	defer frame.scratch_destroy(&scratch)
	positions := []f32{1, -1, 2, -2, 3, -3, 4, -4, 5, 6}
	for x in positions {
		_ = game.simulation_create_object(
			&sim,
			{prefab = .Lamp, body_mode = .Static, center = {x, 1, 0}, yaw_rad = 0},
		)
	}

	camera := renderer.Camera{position = {0, 1, 0}, fov_x = frame.PLAYER_FOV_X}
	scene := frame.build(&sim, &debug, {}, &camera, &hud, &scratch)
	testing.expect_value(t, len(scene.lights), len(positions))
	for light, index in scene.lights {
		testing.expect_value(t, light.position.x, positions[index])
	}

	arena_count := len(game.arena_static_boxes())
	for index in 0 ..< len(positions) {
		box := scene.boxes[arena_count + game.INITIAL_CRATE_COUNT + index]
		testing.expect(t, box.emissive > 0, "a lamp stopped glowing")
	}
}
