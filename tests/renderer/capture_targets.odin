#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package renderer_test

import "core:log"
import "core:testing"

import "src:frame"
import "src:game"
import "src:platform"
import "src:renderer"

@(test)
offscreen_target_reads_two_targets_from_one_frame :: proc(t: ^testing.T) {
	headless: platform.Headless
	if !platform.headless_init(&headless, TEST_WIDTH, TEST_HEIGHT) {
		log.info("skipping offscreen render test: no Vulkan loader")
		return
	}
	defer platform.headless_deinit(&headless)

	state, init_error := renderer.init(
		renderer.Config {
			platform = platform.headless_platform(&headless),
			target = .Offscreen,
			width = TEST_WIDTH,
			height = TEST_HEIGHT,
		},
		context.allocator,
	)
	if init_error != .None {
		log.infof("skipping offscreen render test: renderer init failed: %v", init_error)
		return
	}
	defer renderer.deinit(&state)

	sim := game.simulation_create()
	testing.expect(t, game.simulation_is_valid(&sim), "simulation world is invalid")
	defer game.simulation_destroy(&sim)
	debug := game.debug_mode_create(context.allocator)
	defer game.debug_mode_destroy(&debug)
	hud: game.HUD_State
	scratch: frame.Scratch
	scene := frame.build(&sim, &debug, {alpha = 1.0, captured = true}, nil, &hud, &scratch)
	status := frame.draw(&state, scene, {targets = {.Color, .Scene_Color}})
	testing.expectf(t, status == .Ok, "multi-target draw failed: %v", status)
	if status != .Ok {
		return
	}
	color, width, height, _, color_error := renderer.read_capture_target(&state, .Color, 0)
	testing.expectf(t, color_error == "", "color readback failed: %s", color_error)
	scene_color, scene_width, scene_height, _, scene_error := renderer.read_capture_target(
		&state,
		.Scene_Color,
		1,
	)
	testing.expectf(t, scene_error == "", "scene color readback failed: %s", scene_error)
	testing.expect_value(t, width, u32(TEST_WIDTH))
	testing.expect_value(t, height, u32(TEST_HEIGHT))
	testing.expect_value(t, scene_width, u32(TEST_WIDTH))
	testing.expect_value(t, scene_height, u32(TEST_HEIGHT))
	testing.expect_value(t, len(color), int(TEST_WIDTH * TEST_HEIGHT * 4))
	testing.expect_value(t, len(scene_color), int(TEST_WIDTH * TEST_HEIGHT * 8))
}

