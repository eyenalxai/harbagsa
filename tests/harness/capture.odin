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
	stats := harness.capture_stats(values, 2, 2, .Velocity, nil, nil, context.allocator)
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

	depth := harness.capture_stats(values, 2, 2, .Depth, nil, nil, context.allocator)
	_, has_depth_median := depth.velocity_median_texels.?
	testing.expect(t, !has_depth_median, "depth stats reported a velocity median")
}

@(test)
capture_stats_gradient_without_a_neighbour_is_zero :: proc(t: ^testing.T) {
	values := []f32{0.25, 0.5, 0.75, 1}
	region := harness.Capture_Region{x = 0, y = 0, w = 1, h = 1}
	stats := harness.capture_stats(values, 1, 1, .Color, region, nil, context.allocator)
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
		testing.expect_value(t, region.unit, harness.Capture_Region_Unit.Pixels)
		testing.expect_value(t, region.pixels.x, 1)
		testing.expect_value(t, region.pixels.w, 3)
	} else {
		testing.expect(t, false, "the region was dropped")
	}
}

@(test)
capture_region_resolves_a_normalized_region :: proc(t: ^testing.T) {
	command, error := harness.command_parse_string(
		`{"cmd":"capture","name":"s","format":"stats","region":{"x":0.3125,"y":0.6388889,"w":0.390625,"h":0.3333333,"unit":"normalized"}}`,
		context.allocator,
	)
	defer harness.command_destroy(&command, context.allocator)
	testing.expectf(t, error == "", "normalized region parse failed: %s", error)
	if error != "" {
		return
	}
	spec, has := command.capture.region.?
	testing.expect(t, has, "the normalized region was dropped")
	if !has {
		return
	}
	testing.expect_value(t, spec.unit, harness.Capture_Region_Unit.Normalized)
	resolved, resolve_error := harness.capture_region_resolve(spec, 1280, 720)
	testing.expectf(t, resolve_error == "", "resolve failed: %s", resolve_error)
	testing.expect_value(t, resolved, harness.Capture_Region{x = 400, y = 460, w = 500, h = 240})
}

@(test)
capture_region_rejects_a_normalized_region_outside_the_frame :: proc(t: ^testing.T) {
	_, error := harness.command_parse_string(
		`{"cmd":"capture","name":"s","format":"stats","region":{"x":0.6,"y":0.5,"w":0.5,"h":0.2,"unit":"normalized"}}`,
		context.allocator,
	)
	testing.expect(t, error != "", "a normalized region past the frame edge was accepted")
	if error != "" {
		delete(error, context.allocator)
	}
}

@(test)
captures_parses_one_frame_with_several_outputs :: proc(t: ^testing.T) {
	command, error := harness.command_parse_string(
		`{"cmd":"captures","name":"pair","frame":12,"outputs":[
			{"target":"color","format":"png"},
			{"target":"history","format":"stats","region":{"x":0,"y":0,"w":8,"h":8}},
			{"target":"color","format":"profile","profile":{"axis":"x","at":1,"from":0,"to":7}}
		]}`,
		context.allocator,
	)
	defer harness.command_destroy(&command, context.allocator)
	testing.expectf(t, error == "", "captures parse failed: %s", error)
	if error != "" {
		return
	}
	testing.expect_value(t, command.kind, harness.Command_Kind.Captures)
	testing.expect_value(t, command.captures.frame, 12)
	testing.expect_value(t, len(command.captures.outputs), 3)
	if len(command.captures.outputs) == 3 {
		testing.expect_value(t, command.captures.outputs[0].name, "pair-color-0")
		testing.expect_value(t, command.captures.outputs[1].name, "pair-history-1")
		testing.expect_value(t, command.captures.outputs[2].name, "pair-color-2")
		_, has_region := command.captures.outputs[1].region.?
		testing.expect(t, has_region, "the region was dropped")
	}
}

@(test)
captures_reject_duplicate_names :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	command, parse_error := harness.command_parse_string(
		`{"cmd":"captures","outputs":[
			{"name":"same","target":"color","format":"png"},
			{"name":"same","target":"history","format":"stats"}
		]}`,
		context.allocator,
	)
	defer harness.command_destroy(&command, context.allocator)
	testing.expectf(t, parse_error == "", "captures parse failed: %s", parse_error)
	_, queue_error := harness.session_queue_captures(&session, command.captures)
	testing.expect(t, queue_error != "", "duplicate names were accepted")
	if queue_error != "" {
		delete(queue_error, context.allocator)
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
