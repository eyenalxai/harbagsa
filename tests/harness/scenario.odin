#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:testing"

import "src:harness"

SMOKE :: `{
  "view": {"hud": false, "debug": false, "hint": false},
  "steps": [
    {"frames": 90, "forward": 1, "look": [220, 0]},
    {"frames": 1, "jump": true},
    {"frames": 30, "forward": 1}
  ],
  "capture": [0, 90, 121],
  "checks": [
    {"field": "crates.0.position.z", "op": "lt", "value": 7.5}
  ]
}`

@(test)
scenario_compiles_to_commands :: proc(t: ^testing.T) {
	scenario, error := harness.scenario_parse(SMOKE, context.allocator)
	testing.expectf(t, error == "", "scenario parse failed: %s", error)
	defer harness.scenario_destroy(&scenario, context.allocator)
	if error != "" {
		return
	}

	kinds := []harness.Command_Kind{
		.View,
		.Capture,
		.Capture,
		.Capture,
		.Look,
		.Input,
		.Step,
		.Input,
		.Step,
		.Input,
		.Step,
		.Check,
	}
	testing.expect_value(t, len(scenario.commands), len(kinds))
	for kind, index in kinds {
		if index >= len(scenario.commands) {
			break
		}
		testing.expectf(
			t,
			scenario.commands[index].kind == kind,
			"command %d is %v, want %v",
			index,
			scenario.commands[index].kind,
			kind,
		)
	}

	capture_frames := [3]int{0, 90, 121}
	for frame, index in capture_frames {
		capture := scenario.commands[index + 1].capture
		testing.expect_value(t, capture.frame, frame)
		testing.expectf(t, capture.name == harness.capture_name(frame, context.temp_allocator), "bad capture name")
	}

	check := scenario.commands[len(scenario.commands) - 1].check
	testing.expect_value(t, check.field, "crates.0.position.z")
	testing.expect(t, check.op == .Lt, "check op was not parsed")
	testing.expect(t, check.value.kind == .Number, "check value is not a number")
	testing.expect(t, check.value.number == 7.5, "check value changed")
}

@(test)
capture_checks_parse_the_warmup :: proc(t: ^testing.T) {
	scenario, error := harness.scenario_parse(
		`{
			"steps": [{"frames": 12}],
			"checks": [
				{"field": "capture.worst_mean_delta", "op": "le", "value": 0.1, "warmup": 4}
			]
		}`,
		context.allocator,
	)
	testing.expectf(t, error == "", "scenario parse failed: %s", error)
	defer harness.scenario_destroy(&scenario, context.allocator)
	if error != "" {
		return
	}
	last := scenario.commands[len(scenario.commands) - 1]
	testing.expect_value(t, last.check.field, "capture.worst_mean_delta")
	testing.expect_value(t, last.check.warmup, 4)
}

@(test)
default_capture_is_the_final_frame :: proc(t: ^testing.T) {
	scenario, error := harness.scenario_parse(`{"steps": [{"frames": 12}]}`, context.allocator)
	defer harness.scenario_destroy(&scenario, context.allocator)
	testing.expectf(t, error == "", "scenario parse failed: %s", error)
	if error != "" {
		return
	}
	testing.expect_value(t, len(scenario.commands), 2)
	testing.expect_value(t, scenario.commands[0].capture.frame, 12)
}

@(test)
empty_capture_list_skips_rendering :: proc(t: ^testing.T) {
	scenario, error := harness.scenario_parse(`{"steps": [{"frames": 1}], "capture": []}`, context.allocator)
	defer harness.scenario_destroy(&scenario, context.allocator)
	testing.expectf(t, error == "", "scenario parse failed: %s", error)
	if error != "" {
		return
	}
	for command in scenario.commands {
		testing.expect(t, command.kind != .Capture, "empty capture list produced a capture")
	}
}

@(test)
scenario_rejects_unknown_keys :: proc(t: ^testing.T) {
	_, error := harness.scenario_parse(`{"steps": [{"frames": 1}], "speed": 2}`, context.allocator)
	testing.expectf(t, error != "", "unknown scenario key was accepted")
	if error != "" {
		delete(error, context.allocator)
	}
}

@(test)
scenario_rejects_bad_step_types :: proc(t: ^testing.T) {
	_, error := harness.scenario_parse(`{"steps": [{"frames": "many"}]}`, context.allocator)
	testing.expectf(t, error != "", "string frame count was accepted")
	if error != "" {
		delete(error, context.allocator)
	}
}

@(test)
scenario_view_accepts_perf :: proc(t: ^testing.T) {
	scenario, error := harness.scenario_parse(
		`{"view": {"perf": true}, "commands": [{"cmd": "quit"}]}`,
		context.allocator,
	)
	defer harness.scenario_destroy(&scenario, context.allocator)
	testing.expectf(t, error == "", "scenario view parse failed: %s", error)
	if error != "" {
		return
	}
	testing.expect(t, len(scenario.commands) > 0, "the view command is missing")
	if len(scenario.commands) > 0 {
		testing.expect(t, scenario.commands[0].kind == .View, "the first command is not a view")
		testing.expect(t, scenario.commands[0].view.has_perf, "the perf flag is missing")
		testing.expect(t, scenario.commands[0].view.perf, "the perf flag is false")
	}
}

@(test)
commands_scenario_runs_verbatim :: proc(t: ^testing.T) {
	scenario, error := harness.scenario_parse(
		`{"commands": [{"cmd": "step", "frames": 2}, {"cmd": "quit"}]}`,
		context.allocator,
	)
	defer harness.scenario_destroy(&scenario, context.allocator)
	testing.expectf(t, error == "", "commands scenario failed: %s", error)
	if error == "" {
		testing.expect_value(t, len(scenario.commands), 2)
		testing.expect(t, scenario.commands[0].kind == .Step, "first command is not a step")
	}
}

@(test)
settle_parses_frames :: proc(t: ^testing.T) {
	command, error := harness.command_parse_string(`{"cmd": "settle", "frames": 30}`, context.allocator)
	defer harness.command_destroy(&command, context.allocator)
	testing.expectf(t, error == "", "settle parse failed: %s", error)
	if error == "" {
		testing.expect(t, command.kind == .Settle, "settle kind is wrong")
		testing.expect_value(t, command.settle.frames, 30)
	}
}

@(test)
settle_rejects_bad_frames :: proc(t: ^testing.T) {
	_, missing := harness.command_parse_string(`{"cmd": "settle"}`, context.allocator)
	testing.expectf(t, missing != "", "settle without frames was accepted")
	if missing != "" {
		delete(missing, context.allocator)
	}
	_, zero := harness.command_parse_string(`{"cmd": "settle", "frames": 0}`, context.allocator)
	testing.expectf(t, zero != "", "settle with zero frames was accepted")
	if zero != "" {
		delete(zero, context.allocator)
	}
}

@(test)
command_parser_rejects_unknown_fields :: proc(t: ^testing.T) {
	command, error := harness.command_parse_string(`{"cmd": "step", "frames": 1, "speed": 3}`, context.allocator)
	testing.expectf(t, error != "", "unknown command field was accepted")
	if error != "" {
		delete(error, context.allocator)
	}
	harness.command_destroy(&command, context.allocator)
}

@(test)
command_parser_validates_ranges :: proc(t: ^testing.T) {
	command, error := harness.command_parse_string(`{"cmd": "input", "forward": 2}`, context.allocator)
	testing.expectf(t, error != "", "out-of-range input was accepted")
	harness.command_destroy(&command, context.allocator)
}

@(test)
menu_command_parses_its_fields :: proc(t: ^testing.T) {
	command, error := harness.command_parse_string(
		`{"cmd": "menu", "open": true, "select": 2, "activate": true}`,
		context.allocator,
	)
	defer harness.command_destroy(&command, context.allocator)
	testing.expectf(t, error == "", "menu command parse failed: %s", error)
	if error != "" {
		return
	}
	testing.expect(t, command.kind == .Menu, "menu command has the wrong kind")
	testing.expect(t, command.menu.has_open && command.menu.open, "menu open was not parsed")
	testing.expect(t, command.menu.has_select && command.menu.select == 2, "menu select was not parsed")
	testing.expect(t, command.menu.activate, "menu activate was not parsed")
}

@(test)
menu_command_rejects_bad_fields :: proc(t: ^testing.T) {
	_, error := harness.command_parse_string(`{"cmd": "menu", "position": 1}`, context.allocator)
	testing.expectf(t, error != "", "unknown menu key was accepted")
	if error != "" {
		delete(error, context.allocator)
	}
	_, error = harness.command_parse_string(`{"cmd": "menu", "select": 8}`, context.allocator)
	testing.expectf(t, error != "", "out-of-range menu row was accepted")
	if error != "" {
		delete(error, context.allocator)
	}
}

@(test)
menu_command_accepts_activate_false :: proc(t: ^testing.T) {
	command, error := harness.command_parse_string(
		`{"cmd": "menu", "activate": false}`,
		context.allocator,
	)
	defer harness.command_destroy(&command, context.allocator)
	testing.expectf(t, error == "", "activate:false failed to parse: %s", error)
	if error != "" {
		return
	}
	testing.expect(t, command.menu.has_activate, "activate presence was lost")
	testing.expect(t, !command.menu.activate, "activate:false became true")
}
