#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:testing"

import "src:harness"

@(private)
steps_of :: proc(image: []u8, width, height: int, region: harness.Capture_Region) -> harness.Capture_Steps {
	values := make([]f32, len(image), context.allocator)
	defer delete(values, context.allocator)
	for value, index in image {
		values[index] = f32(value)
	}
	return harness.capture_steps_build(values, u32(width), u32(height), region, harness.capture_steps_default(), context.allocator)
}

@(test)
steps_ignore_a_soft_gradient :: proc(t: ^testing.T) {
	image := build_image(64, 64, proc(x, y: int) -> u8 { return u8(x / 4) })
	defer delete(image, context.allocator)
	steps := steps_of(image, 64, 64, {x = 0, y = 0, w = 64, h = 64})
	testing.expect_value(t, steps.count, 0)
	testing.expect_value(t, steps.pairs, 2 * 64 * 63)
}

@(test)
steps_find_a_band_edge :: proc(t: ^testing.T) {
	image := build_image(64, 64, proc(x, y: int) -> u8 {
		if y < 32 {
			return 80
		}
		return 110
	})
	defer delete(image, context.allocator)
	steps := steps_of(image, 64, 64, {x = 0, y = 0, w = 64, h = 64})
	testing.expect(t, steps.count > 0, "a 30 level edge left no step")
	testing.expect(t, steps.max > harness.STEP_MIN_LEVELS, "the step height is below the floor")
}

@(test)
steps_skip_a_geometry_edge :: proc(t: ^testing.T) {
	image := build_image(64, 64, proc(x, y: int) -> u8 {
		if x < 32 {
			return 20
		}
		return 220
	})
	defer delete(image, context.allocator)
	steps := steps_of(image, 64, 64, {x = 0, y = 0, w = 64, h = 64})
	testing.expect_value(t, steps.count, 0)
	testing.expect(t, steps.max > harness.STEP_MAX_LEVELS, "the edge height is not reported")
}

@(test)
steps_honour_the_blur_and_thresholds :: proc(t: ^testing.T) {
	image := build_image(32, 32, proc(x, y: int) -> u8 { return u8(x / 2) })
	defer delete(image, context.allocator)
	values := make([]f32, len(image), context.allocator)
	defer delete(values, context.allocator)
	for value, index in image {
		values[index] = f32(value)
	}
	options := harness.Capture_Steps_Options{blur = 3, min = 0, max = 100}
	steps := harness.capture_steps_build(
		values,
		32,
		32,
		harness.Capture_Region{x = 0, y = 0, w = 32, h = 32},
		options,
		context.allocator,
	)
	testing.expect_value(t, steps.blur, 3)
	testing.expect_value(t, steps.floor, f32(0))
	testing.expect_value(t, steps.cap, f32(100))
	testing.expect(t, steps.count > 0, "a one-level gradient left no step with a zero floor")
}

@(test)
steps_parse_rejects_an_even_blur :: proc(t: ^testing.T) {
	_, error := harness.command_parse_string(
		`{"cmd":"capture","format":"stats","region":{"x":0,"y":0,"w":8,"h":8},"steps":{"blur":4}}`,
		context.allocator,
	)
	testing.expect(t, error != "", "an even blur was accepted")
	if error != "" {
		delete(error, context.allocator)
	}
}

@(test)
steps_stay_inside_the_region :: proc(t: ^testing.T) {
	image := build_image(64, 64, proc(x, y: int) -> u8 {
		if (x < 32) != (y < 32) {
			return 30
		}
		return 0
	})
	defer delete(image, context.allocator)
	steps := steps_of(image, 64, 64, {x = 8, y = 40, w = 16, h = 16})
	testing.expect_value(t, steps.count, 0)
}
