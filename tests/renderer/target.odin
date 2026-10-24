#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package renderer_test

import "core:c"
import "core:log"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

import stb_image "vendor:stb/image"

import "src:frame"
import "src:game"
import "src:perf"
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

	recorder: perf.Recorder
	perf.recorder_begin(&recorder, time.tick_now())
	perf.recorder_mark(&recorder, .Events)
	perf.recorder_mark(&recorder, .Simulation)
	perf.recorder_mark(&recorder, .Build)

	state, init_error := renderer.init(
		renderer.Config {
			platform = platform.headless_platform(&headless),
			target = .Offscreen,
			width = TEST_WIDTH,
			height = TEST_HEIGHT,
			recorder = &recorder,
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
	testing.expect(
		t,
		perf.recorder_has(&recorder, .Record),
		"renderer did not mark the end of command recording",
	)

	// The fences retire a slot after MAX_FRAMES_IN_FLIGHT frames, so draw
	// enough frames to read the first frame's query pool.
	for _ in 0 ..< renderer.MAX_FRAMES_IN_FLIGHT {
		status = frame.draw(&state, scene, false)
		if status != .Ok {
			break
		}
	}
	testing.expectf(t, status == .Ok, "offscreen perf draw failed: %v", status)

	times := renderer.gpu_times(&state)
	if !times.available {
		log.info("skipping GPU timestamp assertions: timestamps are unavailable")
		return
	}
	testing.expect(t, times.frame > 0, "GPU timing has no frame number")
	total: time.Duration
	for index in 0 ..< perf.PASS_COUNT {
		pass := perf.Pass(index)
		testing.expectf(t, times.passes[pass] >= 0, "pass %v is negative", pass)
		total += times.passes[pass]
	}
	difference := total - times.total
	if difference < 0 {
		difference = -difference
	}
	testing.expectf(
		t,
		difference <= time.Microsecond,
		"pass sum %v does not match total %v",
		total,
		times.total,
	)

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

@(test)
offscreen_target_keeps_one_frame_in_flight :: proc(t: ^testing.T) {
	testing.expect_value(t, renderer.frames_in_flight(.Offscreen), 1)
	testing.expect_value(t, renderer.frames_in_flight(.Swapchain), renderer.MAX_FRAMES_IN_FLIGHT)
}

@(test)
offscreen_capture_free_sequence_is_deterministic :: proc(t: ^testing.T) {
	first, first_digest, first_ok, first_attempted := render_offscreen_sequence()
	defer if first != nil {
		delete(first, context.allocator)
	}
	second, second_digest, second_ok, second_attempted := render_offscreen_sequence()
	defer if second != nil {
		delete(second, context.allocator)
	}
	if !first_attempted || !second_attempted {
		log.info("skipping the offscreen determinism test: no Vulkan device")
		return
	}
	testing.expect(t, first_ok && second_ok, "the offscreen sequence did not render")
	if !first_ok || !second_ok {
		return
	}
	testing.expect_value(t, len(first), len(second))
	different := false
	for value, index in first {
		if index >= len(second) || value != second[index] {
			different = true
			break
		}
	}
	testing.expect(t, !different, "two capture-free offscreen runs produced different pixels")
	testing.expect_value(t, first_digest, second_digest)
}

// The sequence draws without a capture first, so the second slot would write the
// single offscreen image while the first frame still reads it.
@(private)
render_offscreen_sequence :: proc() -> (
	pixels: []u8,
	render_digest: u64,
	ok: bool,
	attempted: bool,
) {
	headless: platform.Headless
	if !platform.headless_init(&headless, TEST_WIDTH, TEST_HEIGHT) {
		return nil, 0, false, false
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
		return nil, 0, false, false
	}
	defer renderer.deinit(&state)

	sim := game.simulation_create()
	if !game.simulation_is_valid(&sim) {
		return nil, 0, false, true
	}
	defer game.simulation_destroy(&sim)
	debug := game.debug_mode_create()
	hud: game.HUD_State
	scratch: frame.Scratch
	scene := frame.build(&sim, &debug, {alpha = 1.0, captured = true}, nil, &hud, &scratch)
	for _ in 0 ..< 12 {
		if frame.draw(&state, scene, false) != .Ok {
			return nil, 0, false, true
		}
	}
	if frame.draw(&state, scene, true) != .Ok {
		return nil, 0, false, true
	}
	data, _, _, read_ok := renderer.read_capture(&state)
	if !read_ok {
		return nil, 0, false, true
	}
	value, has_digest := renderer.last_render_digest(&state)
	pixels = make([]u8, len(data), context.allocator)
	copy(pixels, data)
	return pixels, has_digest ? value.value : 0, true, true
}
