#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:testing"

import "src:harness"

@(test)
compare_reads_two_fields_with_the_same_resolver :: proc(t: ^testing.T) {
	state := harness.State{frame = 5}
	command := harness.Check_Command {
		field     = "frame",
		op        = .Lt,
		other     = "camera.fov_deg",
		has_other = true,
	}
	state.camera.fov_deg = 90
	result := harness.check_evaluate(command, state, nil, nil, context.allocator)
	defer harness.check_result_destroy(&result, context.allocator)
	testing.expectf(t, result.ok, "compare failed: %s", result.error)
	testing.expect_value(t, result.other, "camera.fov_deg")
}

@(test)
compare_reads_one_capture_against_another :: proc(t: ^testing.T) {
	captures := []harness.Capture_Result {
		{stats = harness.Capture_Stats{mean = {0, 0.4, 0, 1}}},
		{stats = harness.Capture_Stats{mean = {0, 0.6, 0, 1}}},
	}
	command := harness.Check_Command {
		field     = "capture.1.stats.mean.y",
		op        = .Gt,
		other     = "capture.0.stats.mean.y",
		has_other = true,
	}
	result := harness.check_evaluate(command, {}, captures, nil, context.allocator)
	defer harness.check_result_destroy(&result, context.allocator)
	testing.expectf(t, result.ok, "capture comparison failed: %s", result.error)

	reversed := command
	reversed.field = "capture.0.stats.mean.y"
	reversed.other = "capture.1.stats.mean.y"
	reversed.op = .Gt
	failed := harness.check_evaluate(reversed, {}, captures, nil, context.allocator)
	defer harness.check_result_destroy(&failed, context.allocator)
	testing.expect(t, !failed.ok, "the reversed comparison passed")
}

@(test)
compare_reports_a_type_mismatch :: proc(t: ^testing.T) {
	state := harness.State{frame = 5, menu = {item = "Resume"}}
	command := harness.Check_Command {
		field     = "frame",
		op        = .Eq,
		other     = "menu.item",
		has_other = true,
	}
	result := harness.check_evaluate(command, state, nil, nil, context.allocator)
	defer harness.check_result_destroy(&result, context.allocator)
	testing.expect(t, result.error != "", "a number was compared with a string")
}

@(test)
compare_reports_a_missing_field :: proc(t: ^testing.T) {
	command := harness.Check_Command {
		field     = "frame",
		op        = .Eq,
		other     = "camera.missing",
		has_other = true,
	}
	result := harness.check_evaluate(command, {}, nil, nil, context.allocator)
	defer harness.check_result_destroy(&result, context.allocator)
	testing.expect(t, result.error != "", "a missing comparison field was accepted")
}

@(test)
compare_parses_other_instead_of_value :: proc(t: ^testing.T) {
	command, error := harness.command_parse_string(
		`{"cmd":"check","field":"capture.1.stats.mean.y","op":"gt","other":"capture.0.stats.mean.y"}`,
		context.allocator,
	)
	testing.expectf(t, error == "", "compare parse failed: %s", error)
	defer harness.command_destroy(&command, context.allocator)
	if error != "" {
		return
	}
	testing.expect(t, command.check.has_other, "the check did not record the other field")
	testing.expect_value(t, command.check.other, "capture.0.stats.mean.y")

	_, both_error := harness.command_parse_string(
		`{"cmd":"check","field":"frame","op":"eq","value":1,"other":"frame"}`,
		context.allocator,
	)
	testing.expect(t, both_error != "", "a check accepted both value and other")
	if both_error != "" {
		delete(both_error, context.allocator)
	}
}

@(test)
compare_applies_a_tolerance_to_equality :: proc(t: ^testing.T) {
	captures := []harness.Capture_Result {
		{name = "on", stats = harness.Capture_Stats{mean = {0, 143, 0, 1}}},
		{name = "off", stats = harness.Capture_Stats{mean = {0, 145, 0, 1}}},
	}
	command, error := harness.command_parse_string(
		`{"cmd":"check","field":"capture.named.on.stats.mean.y","op":"eq","other":"capture.named.off.stats.mean.y","tolerance":2}`,
		context.allocator,
	)
	testing.expectf(t, error == "", "tolerance parse failed: %s", error)
	defer harness.command_destroy(&command, context.allocator)
	if error != "" {
		return
	}
	result := harness.check_evaluate(command.check, {}, captures, nil, context.allocator)
	defer harness.check_result_destroy(&result, context.allocator)
	testing.expectf(t, result.ok, "two levels apart did not pass: %s", result.error)
	if value, has := result.tolerance.?; has {
		testing.expect_value(t, value, f64(2))
	} else {
		testing.expect(t, false, "the result did not record the tolerance")
	}
}

@(test)
compare_rejects_a_tolerance_on_an_ordering_op :: proc(t: ^testing.T) {
	command, error := harness.command_parse_string(
		`{"cmd":"check","field":"frame","op":"lt","value":10,"tolerance":2}`,
		context.allocator,
	)
	testing.expectf(t, error == "", "tolerance parse failed: %s", error)
	defer harness.command_destroy(&command, context.allocator)
	if error != "" {
		return
	}
	state := harness.State{frame = 5}
	result := harness.check_evaluate(command.check, state, nil, nil, context.allocator)
	defer harness.check_result_destroy(&result, context.allocator)
	testing.expect(t, result.error != "", "an ordering op accepted a tolerance")
}

@(test)
compare_rejects_a_tolerance_on_a_boolean :: proc(t: ^testing.T) {
	command, error := harness.command_parse_string(
		`{"cmd":"check","field":"menu.open","op":"eq","value":true,"tolerance":1}`,
		context.allocator,
	)
	testing.expectf(t, error == "", "tolerance parse failed: %s", error)
	defer harness.command_destroy(&command, context.allocator)
	if error != "" {
		return
	}
	state := harness.State{menu = {open = true}}
	result := harness.check_evaluate(command.check, state, nil, nil, context.allocator)
	defer harness.check_result_destroy(&result, context.allocator)
	testing.expect(t, result.error != "", "a boolean check accepted a tolerance")
}

@(test)
compare_rejects_a_negative_tolerance :: proc(t: ^testing.T) {
	_, error := harness.command_parse_string(
		`{"cmd":"check","field":"frame","op":"eq","value":1,"tolerance":-1}`,
		context.allocator,
	)
	testing.expect(t, error != "", "a negative tolerance was accepted")
	if error != "" {
		delete(error, context.allocator)
	}
}
