#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:testing"

import "src:harness"

@(private)
build_image :: proc(width, height: int, value: proc(x, y: int) -> u8) -> []u8 {
	image := make([]u8, width * height * 4, context.allocator)
	for y in 0 ..< height {
		for x in 0 ..< width {
			base := (y * width + x) * 4
			image[base + 0] = value(x, y)
			image[base + 1] = value(x, y)
			image[base + 2] = value(x, y)
			image[base + 3] = 255
		}
	}
	return image
}

@(test)
profile_recovers_a_known_ramp :: proc(t: ^testing.T) {
	image := build_image(16, 16, proc(x, y: int) -> u8 { return u8(x * 16) })
	defer delete(image, context.allocator)
	profile, error := harness.capture_profile_build(
		{pixels = image, width = 16, height = 16},
		harness.Capture_Profile{axis = .X, at = 0, from = 0, to = 15},
		context.allocator,
	)
	testing.expectf(t, error == "", "profile build failed: %s", error)
	defer harness.capture_profile_destroy(&profile, context.allocator)
	if error != "" {
		return
	}
	testing.expect(t, !profile.flat, "a linear ramp was reported flat")
	testing.expectf(t, profile.width >= 8 && profile.width <= 14, "ramp width is %v", profile.width)
	testing.expect(t, profile.low_index >= 0, "the low crossing is missing")
	testing.expect(t, profile.high_index > profile.low_index, "the high crossing is not after the low one")
}

@(test)
flat_profile_reports_flat_and_zero_width :: proc(t: ^testing.T) {
	image := build_image(8, 8, proc(x, y: int) -> u8 { return 120 })
	defer delete(image, context.allocator)
	profile, error := harness.capture_profile_build(
		{pixels = image, width = 8, height = 8},
		harness.Capture_Profile{axis = .Y, at = 3, from = 0, to = 7},
		context.allocator,
	)
	testing.expectf(t, error == "", "profile build failed: %s", error)
	defer harness.capture_profile_destroy(&profile, context.allocator)
	if error != "" {
		return
	}
	testing.expect(t, profile.flat, "a flat span was not reported flat")
	testing.expect_value(t, profile.width, f32(0))
}

@(test)
profile_range_outside_the_target_is_an_error :: proc(t: ^testing.T) {
	image := build_image(4, 4, proc(x, y: int) -> u8 { return 0 })
	defer delete(image, context.allocator)
	_, error := harness.capture_profile_build(
		{pixels = image, width = 4, height = 4},
		harness.Capture_Profile{axis = .X, at = 0, from = 0, to = 9},
		context.allocator,
	)
	testing.expectf(t, error != "", "an out-of-range profile span was accepted")
	if error != "" {
		delete(error, context.allocator)
	}
}

@(test)
profile_reads_linear_intermediate_values :: proc(t: ^testing.T) {
	values := make([]f32, 8 * 8 * 4, context.allocator)
	defer delete(values, context.allocator)
	for y in 0 ..< 8 {
		for x in 0 ..< 8 {
			base := (y * 8 + x) * 4
			values[base + 0] = f32(x) / 7.0
			values[base + 1] = f32(x) / 7.0
			values[base + 2] = f32(x) / 7.0
			values[base + 3] = 1.0
		}
	}
	profile, error := harness.capture_profile_build(
		{values = values, width = 8, height = 8},
		harness.Capture_Profile{axis = .X, at = 3, from = 0, to = 7},
		context.allocator,
	)
	testing.expectf(t, error == "", "float profile failed: %s", error)
	defer harness.capture_profile_destroy(&profile, context.allocator)
	if error != "" {
		return
	}
	testing.expect_value(t, profile.source, "linear")
	testing.expect_value(t, profile.values[0], f32(0))
	testing.expect_value(t, profile.values[7], f32(1))
}

@(test)
crop_scales_with_nearest_neighbor :: proc(t: ^testing.T) {
	image := build_image(4, 4, proc(x, y: int) -> u8 { return u8(x * 64) })
	defer delete(image, context.allocator)
	cropped, width, height, error := harness.capture_crop_pixels(
		image,
		4,
		4,
		harness.Capture_Crop{x = 1, y = 1, w = 2, h = 2, scale = 2},
		context.allocator,
	)
	testing.expectf(t, error == "", "crop failed: %s", error)
	defer delete(cropped, context.allocator)
	if error != "" {
		return
	}
	testing.expect_value(t, width, u32(4))
	testing.expect_value(t, height, u32(4))
	testing.expect_value(t, cropped[0], u8(64))
	testing.expect_value(t, cropped[4], u8(64))
	testing.expect_value(t, cropped[8], u8(128))
}

@(test)
crop_outside_the_target_is_an_error :: proc(t: ^testing.T) {
	image := build_image(4, 4, proc(x, y: int) -> u8 { return 0 })
	defer delete(image, context.allocator)
	_, _, _, error := harness.capture_crop_pixels(
		image,
		4,
		4,
		harness.Capture_Crop{x = 3, y = 3, w = 2, h = 2, scale = 1},
		context.allocator,
	)
	testing.expectf(t, error != "", "an out-of-range crop was accepted")
	if error != "" {
		delete(error, context.allocator)
	}
}

@(test)
region_limits_the_statistics :: proc(t: ^testing.T) {
	values := []f32 {
		0, 0, 0, 0,
		0, 0, 0, 0,
		5, 5, 5, 5,
		5, 5, 5, 5,
	}
	stats := harness.capture_stats(
		values,
		2,
		2,
		.Depth,
		harness.Capture_Region{x = 0, y = 0, w = 1, h = 1},
		nil,
		nil,
		nil,
		context.allocator,
	)
	testing.expect_value(t, stats.min.x, f32(0))
	testing.expect_value(t, stats.max.x, f32(0))
	testing.expect_value(t, stats.mean.x, f32(0))
}

@(test)
histogram_counts_the_region_channels :: proc(t: ^testing.T) {
	image := []u8 {
		0, 0, 0, 255,   255, 255, 255, 255,
		0, 0, 0, 255,   255, 255, 255, 255,
	}
	histogram := harness.capture_histogram_build(
		image,
		2,
		harness.Capture_Region{x = 0, y = 0, w = 2, h = 2},
		2,
		context.allocator,
	)
	defer harness.capture_histogram_destroy(&histogram, context.allocator)
	testing.expect_value(t, histogram.bins, 2)
	testing.expect_value(t, histogram.x[0], 2)
	testing.expect_value(t, histogram.x[1], 2)
	testing.expect_value(t, histogram.w[1], 4)
}
