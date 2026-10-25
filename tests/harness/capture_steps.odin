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
	return harness.capture_steps_build(values, u32(width), u32(height), region, context.allocator)
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
