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
	defer game.simulation_destroy(&sim)
	scene := frame.build(&sim, &debug, {}, nil, &hud, &scratch)
	testing.expect_value(t, len(scene.lights), 0)
	for box in scene.boxes {
		testing.expect_value(t, box.emissive, f32(0))
	}
}

@(test)
scene_lights_reach_the_frame_view :: proc(t: ^testing.T) {
	lights := []renderer.Light {
		{position = {1, 2, 3}, intensity = 2, color = {1, 0.5, 0.25}, range = 8},
	}
	view := frame.frame_view(frame.Scene{lights = lights[:]})
	testing.expect_value(t, len(view.lights), 1)
	if len(view.lights) == 1 {
		testing.expect_value(t, view.lights[0].position, [3]f32{1, 2, 3})
		testing.expect_value(t, view.lights[0].range, f32(8))
	}
}

@(test)
scene_box_emissive_survives_the_frame :: proc(t: ^testing.T) {
	sim, debug, hud, scratch := create_state(t)
	defer game.simulation_destroy(&sim)
	scene := frame.build(&sim, &debug, {}, nil, &hud, &scratch)
	testing.expect(t, len(scene.boxes) > 0, "the arena has no boxes")
	if len(scene.boxes) == 0 {
		return
	}
	scene.boxes[0].emissive = 1.5
	view := frame.frame_view(scene)
	testing.expect_value(t, view.boxes[0].emissive, f32(1.5))
}
