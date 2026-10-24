#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:testing"

import "src:harness"

@(test)
capture_defaults_to_color_png :: proc(t: ^testing.T) {
	command, error := harness.command_parse_string(`{"cmd": "capture", "name": "shot"}`, context.allocator)
	defer harness.command_destroy(&command, context.allocator)
	testing.expectf(t, error == "", "capture parse failed: %s", error)
	if error != "" {
		return
	}
	testing.expect(t, command.capture.target == .Color, "default target is not color")
	testing.expect(t, command.capture.format == .Png, "default format is not png")
}

@(test)
capture_parses_an_intermediate_target :: proc(t: ^testing.T) {
	command, error := harness.command_parse_string(
		`{"cmd": "capture", "name": "motion", "target": "velocity", "format": "float"}`,
		context.allocator,
	)
	defer harness.command_destroy(&command, context.allocator)
	testing.expectf(t, error == "", "velocity capture parse failed: %s", error)
	if error != "" {
		return
	}
	testing.expect(t, command.capture.target == .Velocity, "velocity target was dropped")
	testing.expect(t, command.capture.format == .Float, "float format was dropped")
}

@(test)
capture_targets_default_to_stats :: proc(t: ^testing.T) {
	command, error := harness.command_parse_string(
		`{"cmd": "capture", "name": "depth", "target": "depth"}`,
		context.allocator,
	)
	defer harness.command_destroy(&command, context.allocator)
	testing.expectf(t, error == "", "depth capture parse failed: %s", error)
	if error == "" {
		testing.expect(t, command.capture.format == .Stats, "intermediate target did not default to stats")
	}
}

@(test)
capture_rejects_bad_target_and_format_pairs :: proc(t: ^testing.T) {
	pairs := []string{
		`{"cmd": "capture", "name": "shot", "target": "velocity", "format": "png"}`,
		`{"cmd": "capture", "name": "shot", "target": "color", "format": "raw"}`,
		`{"cmd": "capture", "name": "shot", "target": "normal"}`,
		`{"cmd": "capture", "name": "shot", "format": "jpeg"}`,
	}
	for pair in pairs {
		_, error := harness.command_parse_string(pair, context.allocator)
		testing.expectf(t, error != "", "invalid capture was accepted: %s", pair)
		if error != "" {
			delete(error, context.allocator)
		}
	}
}

@(test)
capture_stats_reports_channels_and_velocity_median :: proc(t: ^testing.T) {
	values := []f32 {
		0, 0, 1, 0,
		1, 0, 1, 0,
		2, 0, 1, 0,
		3, 0, 1, 0,
	}
	stats := harness.capture_stats(values, 2, 2, .Velocity, context.allocator)
	testing.expect_value(t, stats.min[0], f32(0))
	testing.expect_value(t, stats.max[0], f32(3))
	testing.expect_value(t, stats.mean[0], f32(1.5))
	median, has_median := stats.velocity_median_texels.?
	testing.expect(t, has_median, "velocity median is missing")
	if has_median {
		testing.expect_value(t, median, f32(4))
	}

	depth := harness.capture_stats(values, 2, 2, .Depth, context.allocator)
	_, has_depth_median := depth.velocity_median_texels.?
	testing.expect(t, !has_depth_median, "depth stats reported a velocity median")
}

@(test)
capture_summary_uses_the_capture_extent :: proc(t: ^testing.T) {
	summary := harness.capture_summary(
		[]harness.Capture_Result{{width = 10, height = 10, delta_over_16 = 4}},
	)
	testing.expect_value(t, summary.worst_over_16_fraction, f32(0.04))
}

@(test)
pixel_hash_hashes_every_byte :: proc(t: ^testing.T) {
	hash := harness.pixel_hash([]u8{0x00, 0xFF, 0x80}, context.temp_allocator)
	testing.expect_value(t, hash, "d6c4781869e88da0")
}
