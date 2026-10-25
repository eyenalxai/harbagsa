#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:os"
import "core:strings"
import "core:testing"

import "src:harness"

RECORD_TEST_PATH :: "/tmp/opencode/harbagsa-record-actions.json"

@(test)
record_keeps_every_capture_option :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	session.render.enabled = false
	line := strings.concatenate(
		{`{"cmd":"record","path":"`, RECORD_TEST_PATH, `","actions":true}`},
		context.temp_allocator,
	)
	reply := execute(t, &session, line)
	harness.reply_destroy(&reply, context.allocator)
	for capture_line in ([]string{
		`{"cmd":"capture","name":"stats","format":"stats","region":{"x":1,"y":2,"w":3,"h":4},"histogram":8,"steps":{"blur":5,"min":0.5,"max":4},"color_key":{"r":1,"g":2,"b":3,"tolerance":2.5},"png":true}`,
		`{"cmd":"capture","name":"crop","format":"png","crop":{"x":1,"y":2,"w":3,"h":4,"scale":2}}`,
		`{"cmd":"capture","name":"profile","format":"profile","profile":{"axis":"y","channel":"z","at":3,"from":1,"to":9,"low":0.1,"high":0.9}}`,
	}) {
		capture_reply := execute(t, &session, capture_line)
		harness.reply_destroy(&capture_reply, context.allocator)
	}
	reply = execute(t, &session, `{"cmd":"record"}`)
	harness.reply_destroy(&reply, context.allocator)
	defer os.remove(RECORD_TEST_PATH)

	data, read_error := os.read_entire_file(RECORD_TEST_PATH, context.allocator)
	defer delete(data, context.allocator)
	testing.expectf(t, read_error == nil, "cannot read the recording: %v", read_error)
	if read_error != nil {
		return
	}
	scenario, parse_error := harness.scenario_parse(string(data), context.allocator)
	defer harness.scenario_destroy(&scenario, context.allocator)
	testing.expectf(t, parse_error == "", "the recording did not parse: %s", parse_error)
	if parse_error != "" {
		return
	}
	found: [3]bool
	for command in scenario.commands {
		if command.kind != .Capture {
			continue
		}
		switch command.capture.name {
		case "stats":
			found[0] = true
			testing.expect_value(t, command.capture.format, harness.Capture_Format.Stats)
			testing.expect(t, command.capture.png, "the png sidecar was dropped")
			region, has_region := command.capture.region.?
			testing.expect(t, has_region, "the region was dropped")
			if has_region {
				testing.expect_value(t, region.pixels, harness.Capture_Region{x = 1, y = 2, w = 3, h = 4})
			}
			bins, has_histogram := command.capture.histogram.?
			testing.expect(t, has_histogram && bins == 8, "the histogram was dropped")
			steps, has_steps := command.capture.steps.?
			testing.expect(t, has_steps && steps.blur == 5, "the steps were dropped")
			key, has_key := command.capture.color_key.?
			testing.expect(t, has_key && key.r == 1 && key.tolerance == 2.5, "the color key was dropped")
		case "crop":
			found[1] = true
			crop, has_crop := command.capture.crop.?
			testing.expect(t, has_crop && crop.scale == 2, "the crop was dropped")
		case "profile":
			found[2] = true
			profile, has_profile := command.capture.profile.?
			testing.expect(t, has_profile, "the profile was dropped")
			if has_profile {
				testing.expect_value(t, profile.axis, harness.Profile_Axis.Y)
				testing.expect_value(t, profile.channel, harness.Profile_Channel.Z)
				testing.expect_value(t, profile.low, f32(0.1))
			}
		}
	}
	testing.expectf(t, found[0], "the stats capture was not recorded: %s", string(data))
	testing.expectf(t, found[1], "the crop capture was not recorded: %s", string(data))
	testing.expectf(t, found[2], "the profile capture was not recorded: %s", string(data))
}

@(test)
record_keeps_the_relative_capture_frame :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	session.render.enabled = false
	session.frame = 5
	line := strings.concatenate(
		{`{"cmd":"record","path":"`, RECORD_TEST_PATH, `","actions":true}`},
		context.temp_allocator,
	)
	reply := execute(t, &session, line)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd":"capture","format":"stats","frame":20}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd":"record"}`)
	harness.reply_destroy(&reply, context.allocator)
	defer os.remove(RECORD_TEST_PATH)

	data, read_error := os.read_entire_file(RECORD_TEST_PATH, context.allocator)
	defer delete(data, context.allocator)
	testing.expectf(t, read_error == nil, "cannot read the recording: %v", read_error)
	if read_error != nil {
		return
	}
	scenario, parse_error := harness.scenario_parse(string(data), context.allocator)
	defer harness.scenario_destroy(&scenario, context.allocator)
	testing.expectf(t, parse_error == "", "the recording did not parse: %s", parse_error)
	if parse_error != "" {
		return
	}
	found := false
	for command in scenario.commands {
		if command.kind == .Capture {
			found = true
			testing.expect_value(t, command.capture.name, "frame_0020")
			testing.expect_value(t, command.capture.frame, 15)
			testing.expect(t, command.capture.has_frame, "the capture frame was dropped")
		}
	}
	testing.expect(t, found, "the scheduled capture was not recorded")
}

@(test)
record_keeps_a_capture_group :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	session.render.enabled = false
	line := strings.concatenate(
		{`{"cmd":"record","path":"`, RECORD_TEST_PATH, `","actions":true}`},
		context.temp_allocator,
	)
	reply := execute(t, &session, line)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(
		t,
		&session,
		`{"cmd":"captures","frame":2,"outputs":[
			{"name":"stats","format":"stats","region":{"x":1,"y":2,"w":3,"h":4},"steps":{"blur":5,"min":0.5,"max":4}},
			{"name":"crop","format":"png","crop":{"x":1,"y":2,"w":3,"h":4,"scale":2}}
		]}`,
	)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd":"record"}`)
	harness.reply_destroy(&reply, context.allocator)
	defer os.remove(RECORD_TEST_PATH)

	data, read_error := os.read_entire_file(RECORD_TEST_PATH, context.allocator)
	defer delete(data, context.allocator)
	testing.expectf(t, read_error == nil, "cannot read the recording: %v", read_error)
	if read_error != nil {
		return
	}
	scenario, parse_error := harness.scenario_parse(string(data), context.allocator)
	defer harness.scenario_destroy(&scenario, context.allocator)
	testing.expectf(t, parse_error == "", "the recording did not parse: %s\n%s", parse_error, string(data))
	if parse_error != "" {
		return
	}
	found := false
	for command in scenario.commands {
		if command.kind != .Captures {
			continue
		}
		found = true
		testing.expect_value(t, command.captures.frame, 2)
		testing.expect_value(t, len(command.captures.outputs), 2)
		if len(command.captures.outputs) != 2 {
			continue
		}
		region, has_region := command.captures.outputs[0].region.?
		testing.expect(t, has_region, "the group region was dropped")
		if has_region {
			testing.expect_value(t, region.pixels, harness.Capture_Region{x = 1, y = 2, w = 3, h = 4})
		}
		crop, has_crop := command.captures.outputs[1].crop.?
		testing.expect(t, has_crop && crop.scale == 2, "the group crop was dropped")
	}
	testing.expect(t, found, "the capture group was not recorded")
}

@(test)
record_actions_omits_the_initial_scene :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	line := strings.concatenate(
		{`{"cmd":"record","path":"`, RECORD_TEST_PATH, `","actions":true}`},
		context.temp_allocator,
	)
	reply := execute(t, &session, line)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd":"record"}`)
	harness.reply_destroy(&reply, context.allocator)
	defer os.remove(RECORD_TEST_PATH)

	data, read_error := os.read_entire_file(RECORD_TEST_PATH, context.allocator)
	defer delete(data, context.allocator)
	testing.expectf(t, read_error == nil, "cannot read the recording: %v", read_error)
	if read_error != nil {
		return
	}
	text := string(data)
	testing.expect(t, strings.contains(text, `"reset"`), "the reset is missing")
	testing.expect(t, !strings.contains(text, `"scene"`), "the action recording kept the scene")
}

@(test)
record_keeps_the_initial_scene_by_default :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	line := strings.concatenate(
		{`{"cmd":"record","path":"`, RECORD_TEST_PATH, `"}`},
		context.temp_allocator,
	)
	reply := execute(t, &session, line)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd":"record"}`)
	harness.reply_destroy(&reply, context.allocator)
	defer os.remove(RECORD_TEST_PATH)

	data, read_error := os.read_entire_file(RECORD_TEST_PATH, context.allocator)
	defer delete(data, context.allocator)
	testing.expectf(t, read_error == nil, "cannot read the recording: %v", read_error)
	if read_error == nil {
		testing.expect(t, strings.contains(string(data), `"scene"`), "the default recording lost the scene")
	}
}
