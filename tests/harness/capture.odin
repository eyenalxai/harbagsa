#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:encoding/json"
import "core:strings"
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
	stats := harness.capture_stats(values, 2, 2, .Velocity, nil, context.allocator)
	testing.expect_value(t, stats.min[0], f32(0))
	testing.expect_value(t, stats.max[0], f32(3))
	testing.expect_value(t, stats.mean[0], f32(1.5))
	testing.expectf(t, abs(stats.stddev[0] - 1.118034) < 1e-5, "stddev is %v", stats.stddev[0])
	testing.expect_value(t, stats.gradient[0], f32(1.5))
	testing.expect_value(t, stats.stddev[1], f32(0))
	testing.expect_value(t, stats.gradient[1], f32(0))
	median, has_median := stats.velocity_median_texels.?
	testing.expect(t, has_median, "velocity median is missing")
	if has_median {
		testing.expect_value(t, median, f32(4))
	}

	depth := harness.capture_stats(values, 2, 2, .Depth, nil, context.allocator)
	_, has_depth_median := depth.velocity_median_texels.?
	testing.expect(t, !has_depth_median, "depth stats reported a velocity median")
}

@(test)
capture_stats_gradient_without_a_neighbour_is_zero :: proc(t: ^testing.T) {
	values := []f32{0.25, 0.5, 0.75, 1}
	region := harness.Capture_Region{x = 0, y = 0, w = 1, h = 1}
	stats := harness.capture_stats(values, 1, 1, .Color, region, context.allocator)
	testing.expect_value(t, stats.stddev[0], f32(0))
	testing.expect_value(t, stats.gradient[0], f32(0))
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

@(test)
capture_stats_sidecar_keeps_the_stats_and_the_png :: proc(t: ^testing.T) {
	command, error := harness.command_parse_string(
		`{"cmd": "capture", "name": "ao", "format": "stats", "region": {"x": 0, "y": 0, "w": 8, "h": 8}, "png": true}`,
		context.allocator,
	)
	defer harness.command_destroy(&command, context.allocator)
	testing.expectf(t, error == "", "sidecar capture parse failed: %s", error)
	if error != "" {
		return
	}
	testing.expect(t, command.capture.format == .Stats, "the stats format changed")
	testing.expect(t, command.capture.png, "the png sidecar flag was dropped")
}

@(test)
capture_rejects_bad_png_sidecars :: proc(t: ^testing.T) {
	lines := []string {
		`{"cmd": "capture", "name": "shot", "format": "png", "png": true}`,
		`{"cmd": "capture", "name": "shot", "format": "float", "target": "depth", "png": true}`,
		`{"cmd": "capture", "name": "shot", "format": "stats", "crop": {"x": 0, "y": 0, "w": 2, "h": 2, "scale": 2}, "png": true}`,
		`{"cmd": "capture", "name": "shot", "format": "png", "profile": {"axis": "y", "at": 0, "from": 0, "to": 4}}`,
		`{"cmd": "capture", "name": "shot", "format": "stats", "profile": {"axis": "y", "at": 0, "from": 0, "to": 4}}`,
	}
	for line in lines {
		_, error := harness.command_parse_string(line, context.allocator)
		testing.expectf(t, error != "", "invalid sidecar was accepted: %s", line)
		if error != "" {
			delete(error, context.allocator)
		}
	}
}

@(test)
capture_has_png_reads_the_format_and_the_sidecar_flag :: proc(t: ^testing.T) {
	testing.expect(t, harness.capture_has_png({path = "a.png", format = "png"}), "a png capture is not a png")
	testing.expect(
		t,
		harness.capture_has_png({path = "a.png", format = "stats", png = true}),
		"a stats sidecar is not a png",
	)
	testing.expect(
		t,
		!harness.capture_has_png({format = "stats"}),
		"a stats capture without a file is a png",
	)
}

@(test)
capture_region_is_recorded :: proc(t: ^testing.T) {
	command, error := harness.command_parse_string(
		`{"cmd":"capture","name":"s","format":"stats","region":{"x":1,"y":2,"w":3,"h":4}}`,
		context.allocator,
	)
	defer harness.command_destroy(&command, context.allocator)
	testing.expectf(t, error == "", "region parse failed: %s", error)
	if region, has := command.capture.region.?; has {
		testing.expect_value(t, region.x, 1)
		testing.expect_value(t, region.w, 3)
	} else {
		testing.expect(t, false, "the region was dropped")
	}
}

@(test)
capture_result_marshals_the_region :: proc(t: ^testing.T) {
	result := harness.Capture_Result{region = harness.Capture_Region{x = 1, y = 2, w = 3, h = 4}}
	data, error := json.marshal(result, {}, context.allocator)
	defer delete(data, context.allocator)
	testing.expectf(t, error == nil, "marshal failed: %v", error)
	testing.expect(t, strings.contains(string(data), `"region"`), "the region is missing")
}
