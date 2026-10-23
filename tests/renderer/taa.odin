#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package renderer_test

import "core:math"
import "core:testing"

import "src:renderer"
import vk "vendor:vulkan"

@(test)
halton_samples_are_in_the_unit_interval :: proc(t: ^testing.T) {
	bases := [2]u32{2, 3}
	for base in bases {
		for index in 1 ..= 8 {
			value := renderer.halton(u32(index), base)
			testing.expectf(t, value >= 0 && value < 1, "base %d index %d gave %v", base, index, value)
		}
	}
	testing.expectf(
		t,
		math.abs(renderer.halton(1, 2) - 0.5) < 1e-6,
		"Halton base 2 index 1",
	)
	testing.expectf(
		t,
		math.abs(renderer.halton(1, 3) - 1.0 / 3.0) < 1e-6,
		"Halton base 3 index 1",
	)
}

@(test)
jitter_stays_within_half_a_pixel :: proc(t: ^testing.T) {
	extent := vk.Extent2D{width = 1280, height = 720}
	for sample in 0 ..< renderer.TAA_JITTER_SAMPLES {
		jitter := renderer.taa_jitter(sample, extent)
		x := jitter.x * f32(extent.width) * 0.5
		y := jitter.y * f32(extent.height) * 0.5
		testing.expectf(t, math.abs(x) < 0.5, "sample %d x offset %v", sample, x)
		testing.expectf(t, math.abs(y) < 0.5, "sample %d y offset %v", sample, y)
	}
}

@(test)
history_weight_ramps_then_holds :: proc(t: ^testing.T) {
	testing.expectf(t, math.abs(renderer.taa_history_weight(0) - 0.5) < 1e-6, "first step")
	testing.expectf(t, math.abs(renderer.taa_history_weight(1) - 0.75) < 1e-6, "second step")
	testing.expectf(t, math.abs(renderer.taa_history_weight(2) - 0.9) < 1e-6, "steady weight")
	testing.expectf(t, math.abs(renderer.taa_history_weight(9) - 0.9) < 1e-6, "clamped weight")
}
