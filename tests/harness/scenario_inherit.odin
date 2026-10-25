#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:os"
import "core:strings"
import "core:testing"

import "src:harness"

SCENARIO_BASE :: "/tmp/opencode/harness-base.json"
SCENARIO_CHILD :: "/tmp/opencode/harness-child.json"
SCENARIO_CYCLE_A :: "/tmp/opencode/harness-cycle-a.json"
SCENARIO_CYCLE_B :: "/tmp/opencode/harness-cycle-b.json"

@(test)
scenario_size_pins_the_extent :: proc(t: ^testing.T) {
	scenario, error := harness.scenario_parse(
		`{"size":"800x600","commands":[{"cmd":"step","frames":1}]}`,
		context.allocator,
	)
	testing.expectf(t, error == "", "scenario parse failed: %s", error)
	defer harness.scenario_destroy(&scenario, context.allocator)
	if error != "" {
		return
	}
	testing.expect(t, scenario.has_size, "scenario size was not recorded")
	testing.expect_value(t, scenario.size[0], u32(800))
	testing.expect_value(t, scenario.size[1], u32(600))
}

@(test)
scenario_load_records_the_path_and_a_stable_hash :: proc(t: ^testing.T) {
	body := `{"commands":[{"cmd":"step","frames":2}]}`
	if write_error := os.write_entire_file(SCENARIO_BASE, body); write_error != nil {
		testing.expectf(t, false, "cannot write the scenario: %v", write_error)
		return
	}
	defer os.remove(SCENARIO_BASE)

	first, first_error := harness.scenario_load(SCENARIO_BASE, context.allocator)
	testing.expectf(t, first_error == "", "scenario load failed: %s", first_error)
	defer harness.scenario_destroy(&first, context.allocator)
	second, second_error := harness.scenario_load(SCENARIO_BASE, context.allocator)
	testing.expectf(t, second_error == "", "second scenario load failed: %s", second_error)
	defer harness.scenario_destroy(&second, context.allocator)
	if first_error != "" || second_error != "" {
		return
	}
	testing.expect_value(t, first.source.path, SCENARIO_BASE)
	testing.expect(t, first.source.hash != "", "the scenario hash is empty")
	testing.expect_value(t, first.source.hash, second.source.hash)
}

@(test)
scenario_extends_keeps_the_base_checks :: proc(t: ^testing.T) {
	base := `{"commands":[{"cmd":"step","frames":2}],"checks":[{"field":"frame","op":"eq","value":2}]}`
	child := `{"extends":"/tmp/opencode/harness-base.json","commands":[{"cmd":"step","frames":5}]}`
	if write_error := os.write_entire_file(SCENARIO_BASE, base); write_error != nil {
		testing.expectf(t, false, "cannot write the base scenario: %v", write_error)
		return
	}
	defer os.remove(SCENARIO_BASE)
	scenario, error := harness.scenario_parse(child, context.allocator)
	testing.expectf(t, error == "", "extended scenario parse failed: %s", error)
	defer harness.scenario_destroy(&scenario, context.allocator)
	if error != "" {
		return
	}
	testing.expect_value(t, len(scenario.commands), 2)
	if len(scenario.commands) == 2 {
		testing.expect_value(t, scenario.commands[0].kind, harness.Command_Kind.Step)
		testing.expect_value(t, scenario.commands[0].step.frames, 5)
		testing.expect_value(t, scenario.commands[1].kind, harness.Command_Kind.Check)
		testing.expect_value(t, scenario.commands[1].check.field, "frame")
	}
}

@(test)
scenario_parameters_substitute_values :: proc(t: ^testing.T) {
	body := `{
		"parameters": {"n": 7, "name": "walk"},
		"commands": [
			{"cmd":"step","frames":"${n}"},
			{"cmd":"capture","name":"${name}"}
		]
	}`
	scenario, error := harness.scenario_parse(body, context.allocator)
	testing.expectf(t, error == "", "parameter scenario parse failed: %s", error)
	defer harness.scenario_destroy(&scenario, context.allocator)
	if error != "" {
		return
	}
	testing.expect_value(t, len(scenario.commands), 2)
	if len(scenario.commands) == 2 {
		testing.expect_value(t, scenario.commands[0].step.frames, 7)
		testing.expect_value(t, scenario.commands[1].capture.name, "walk")
	}
}

@(test)
scenario_parameter_override_reaches_a_command :: proc(t: ^testing.T) {
	body := `{
		"parameters": {"x": 20.0, "label": "wall"},
		"commands": [
			{"cmd":"editor","place":{"prefab":"Block","position":["${x}",0,0]}},
			{"cmd":"capture","name":"${label}"}
		]
	}`
	overrides := []harness.Parameter_Override {
		{name = "x", value = "19.999"},
		{name = "label", value = "ceiling"},
	}
	scenario, error := harness.scenario_parse(body, context.allocator, overrides)
	testing.expectf(t, error == "", "override scenario parse failed: %s", error)
	defer harness.scenario_destroy(&scenario, context.allocator)
	if error != "" {
		return
	}
	testing.expect_value(t, len(scenario.commands), 2)
	if len(scenario.commands) != 2 {
		return
	}
	testing.expect(t, abs(scenario.commands[0].editor.place.position.x - 19.999) < 1e-5, "the numeric override was dropped")
	testing.expect_value(t, scenario.commands[1].capture.name, "ceiling")
	testing.expect_value(t, len(scenario.source.parameters), 2)
	if len(scenario.source.parameters) == 2 {
		testing.expect_value(t, scenario.source.parameters[0].name, "label")
		testing.expect_value(t, scenario.source.parameters[0].value, "ceiling")
		testing.expect_value(t, scenario.source.parameters[1].name, "x")
		testing.expect_value(t, scenario.source.parameters[1].value, "19.999")
	}
}

@(test)
scenario_parameter_override_changes_the_hash :: proc(t: ^testing.T) {
	body := `{"parameters":{"x":20.0},"commands":[{"cmd":"camera","position":["${x}",0,0],"yaw":0,"pitch":0}]}`
	first, first_error := harness.scenario_parse(
		body,
		context.allocator,
		[]harness.Parameter_Override{{name = "x", value = "20"}},
	)
	testing.expectf(t, first_error == "", "first override parse failed: %s", first_error)
	defer harness.scenario_destroy(&first, context.allocator)
	second, second_error := harness.scenario_parse(
		body,
		context.allocator,
		[]harness.Parameter_Override{{name = "x", value = "19.999"}},
	)
	testing.expectf(t, second_error == "", "second override parse failed: %s", second_error)
	defer harness.scenario_destroy(&second, context.allocator)
	if first_error != "" || second_error != "" {
		return
	}
	testing.expect(t, first.source.hash != second.source.hash, "the hash ignores the parameter")
}

@(test)
scenario_parameter_override_needs_a_placeholder :: proc(t: ^testing.T) {
	body := `{"parameters":{"x":20.0},"commands":[{"cmd":"step","frames":1}]}`
	_, error := harness.scenario_parse(
		body,
		context.allocator,
		[]harness.Parameter_Override{{name = "x", value = "21"}},
	)
	testing.expect(t, error != "", "an unused parameter override was accepted")
	if error != "" {
		testing.expect(t, strings.contains(error, "placeholder"), "the error does not name the placeholder")
		delete(error, context.allocator)
	}
}

@(test)
scenario_parameter_override_needs_the_declared_type :: proc(t: ^testing.T) {
	body := `{"parameters":{"flag":false},"commands":[{"cmd":"input","jump":"${flag}"}]}`
	scenario, error := harness.scenario_parse(
		body,
		context.allocator,
		[]harness.Parameter_Override{{name = "flag", value = "true"}},
	)
	testing.expectf(t, error == "", "boolean override parse failed: %s", error)
	defer harness.scenario_destroy(&scenario, context.allocator)
	if error == "" {
		testing.expect_value(t, scenario.commands[0].input.jump, true)
	}

	_, bad_error := harness.scenario_parse(
		body,
		context.allocator,
		[]harness.Parameter_Override{{name = "flag", value = "yes"}},
	)
	testing.expect(t, bad_error != "", "a non-boolean override was accepted")
	if bad_error != "" {
		delete(bad_error, context.allocator)
	}
}

@(test)
scenario_extends_rejects_a_cycle :: proc(t: ^testing.T) {
	cycle_a := `{"extends":"/tmp/opencode/harness-cycle-b.json","commands":[{"cmd":"step","frames":1}]}`
	cycle_b := `{"extends":"/tmp/opencode/harness-cycle-a.json","commands":[{"cmd":"step","frames":1}]}`
	_ = os.write_entire_file(SCENARIO_CYCLE_A, cycle_a)
	_ = os.write_entire_file(SCENARIO_CYCLE_B, cycle_b)
	defer os.remove(SCENARIO_CYCLE_A)
	defer os.remove(SCENARIO_CYCLE_B)

	_, error := harness.scenario_parse(cycle_a, context.allocator)
	testing.expect(t, error != "", "a scenario cycle was accepted")
	if error != "" {
		testing.expect(
			t,
			strings.contains(error, "deeply") || strings.contains(error, "cycle"),
			"the cycle error does not name the cause",
		)
		delete(error, context.allocator)
	}
}

@(test)
run_output_dir_tags_a_run :: proc(t: ^testing.T) {
	path, owned := harness.run_output_dir("scenarios/smoke.json", "", "before", context.allocator)
	defer if owned {
		delete(path, context.allocator)
	}
	testing.expect_value(t, path, "runs/smoke/before")

	tagged, tagged_owned := harness.run_output_dir("scenarios/smoke.json", "/tmp/opencode/run", "after", context.allocator)
	defer if tagged_owned {
		delete(tagged, context.allocator)
	}
	testing.expect_value(t, tagged, "/tmp/opencode/run/after")
}
