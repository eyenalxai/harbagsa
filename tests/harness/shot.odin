#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:testing"

import "src:harness"

@(test)
shot_expands_camera_sun_settle_and_capture :: proc(t: ^testing.T) {
	scenario, error := harness.scenario_parse(
		`{"commands":[
			{"cmd":"shot","name":"lane","note":"west lane","camera":{"position":[1,2,3],"yaw_deg":0,"pitch_deg":0},
			 "sun":{"azimuth_deg":52,"elevation_deg":15},"settle":40,"format":"stats",
			 "region":{"x":0,"y":0,"w":10,"h":10}}
		]}`,
		context.allocator,
	)
	defer harness.scenario_destroy(&scenario, context.allocator)
	testing.expectf(t, error == "", "shot parse failed: %s", error)
	if error != "" {
		return
	}
	testing.expect_value(t, len(scenario.commands), 4)
	if len(scenario.commands) != 4 {
		return
	}
	testing.expect_value(t, scenario.commands[0].kind, harness.Command_Kind.Camera)
	testing.expect_value(t, scenario.commands[1].kind, harness.Command_Kind.Sun)
	testing.expect_value(t, scenario.commands[2].kind, harness.Command_Kind.Settle)
	testing.expect_value(t, scenario.commands[3].kind, harness.Command_Kind.Capture)
	testing.expect_value(t, scenario.commands[3].capture.name, "lane")
	testing.expect_value(t, scenario.commands[3].capture.note, "west lane")
	testing.expect_value(t, scenario.commands[3].capture.format, harness.Capture_Format.Stats)
}

@(test)
shot_rejects_a_missing_name :: proc(t: ^testing.T) {
	_, error := harness.scenario_parse(
		`{"commands":[{"cmd":"shot","format":"stats"}]}`,
		context.allocator,
	)
	testing.expect(t, error != "", "a shot without a name was accepted")
	if error != "" {
		delete(error, context.allocator)
	}
}
