#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package renderer_test

import "core:c"
import "core:log"
import "core:os"
import "core:strings"
import "core:testing"

import stb_image "vendor:stb/image"

import "src:frame"
import "src:game"
import "src:platform"
import "src:renderer"

TEST_WIDTH :: 320
TEST_HEIGHT :: 180
TEST_PNG :: "/tmp/opencode/harbagsa-offscreen-test.png"

@(test)
offscreen_target_renders_and_reads_rgba :: proc(t: ^testing.T) {
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

	testing.expect_value(t, state.target.config.width, u32(TEST_WIDTH))
	testing.expect_value(t, state.target.config.height, u32(TEST_HEIGHT))
	testing.expect(t, state.target.config.format != .UNDEFINED, "offscreen target has no color format")
	testing.expect(t, state.target.kind == .Offscreen, "target kind is not offscreen")

	sim := game.simulation_create()
	testing.expect(t, game.simulation_is_valid(&sim), "simulation world is invalid")
	defer game.simulation_destroy(&sim)
	debug := game.debug_mode_create()
	hud: game.HUD_State
	scratch: frame.Scratch
	scene := frame.build(&sim, &debug, {alpha = 1.0, captured = true}, nil, &hud, &scratch)
	status := frame.draw(&state, scene, true)
	testing.expectf(t, status == .Ok, "offscreen draw failed: %v", status)
	if status != .Ok {
		return
	}

	pixels, width, height, ok := renderer.read_capture(&state)
	testing.expect(t, ok, "capture readback failed")
	if !ok {
		return
	}
	testing.expect_value(t, width, u32(TEST_WIDTH))
	testing.expect_value(t, height, u32(TEST_HEIGHT))
	testing.expect_value(t, len(pixels), int(TEST_WIDTH * TEST_HEIGHT * 4))

	first := [4]u8{pixels[0], pixels[1], pixels[2], pixels[3]}
	testing.expect_value(t, first[3], u8(255))
	different := false
	for index := 0; index + 3 < len(pixels); index += 4 {
		if pixels[index] != first[0] || pixels[index + 1] != first[1] || pixels[index + 2] != first[2] {
			different = true
			break
		}
	}
	testing.expect(t, different, "offscreen capture is a single flat color")

	_ = os.remove(TEST_PNG)
	cpath := strings.clone_to_cstring(TEST_PNG, context.temp_allocator)
	written := stb_image.write_png(
		cpath,
		c.int(width),
		c.int(height),
		4,
		raw_data(pixels),
		c.int(width * 4),
	)
	testing.expect(t, written != 0, "PNG write failed")
	if written != 0 {
		png, read_error := os.read_entire_file(TEST_PNG, context.allocator)
		testing.expectf(t, read_error == nil, "cannot read the test PNG: %v", read_error)
		if read_error == nil {
			defer delete(png, context.allocator)
			testing.expect(t, len(png) > 8, "PNG is empty")
			signature := [8]u8{0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A}
			testing.expect(t, png[0] == signature[0] && png[1] == signature[1], "bad PNG signature")
		}
		_ = os.remove(TEST_PNG)
	}
}
