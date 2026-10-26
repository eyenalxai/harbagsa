#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:testing"

import "src:harness"

@(test)
capture_check_reads_the_summary :: proc(t: ^testing.T) {
	state := harness.State{}
	captures := []harness.Capture_Result {
		{target = "color", format = "png", delta_mean = 0.05, delta_max = 30, delta_over_16 = 100},
	}
	command := harness.Check_Command {
		field = "capture.worst_mean_delta",
		op    = .Le,
		value = {kind = .Number, number = 0.1},
	}
	result := harness.check_evaluate(command, state, captures, nil, context.allocator)
	defer harness.check_result_destroy(&result, context.allocator)
	testing.expect(t, result.ok, "capture mean check did not pass")
}

@(test)
capture_check_fails_above_the_limit :: proc(t: ^testing.T) {
	state := harness.State{}
	captures := []harness.Capture_Result {
		{target = "color", format = "png", delta_mean = 0.2, delta_max = 30, delta_over_16 = 100},
	}
	command := harness.Check_Command {
		field = "capture.worst_mean_delta",
		op    = .Le,
		value = {kind = .Number, number = 0.1},
	}
	result := harness.check_evaluate(command, state, captures, nil, context.allocator)
	defer harness.check_result_destroy(&result, context.allocator)
	testing.expect(t, !result.ok, "capture mean check accepted a value above the limit")
}

@(test)
capture_check_needs_a_capture :: proc(t: ^testing.T) {
	state := harness.State{}
	command := harness.Check_Command {
		field = "capture.worst_mean_delta",
		op    = .Le,
		value = {kind = .Number, number = 0.1},
	}
	result := harness.check_evaluate(command, state, {}, nil, context.allocator)
	defer harness.check_result_destroy(&result, context.allocator)
	testing.expect(t, result.error != "", "empty capture summary was accepted")
}

@(test)
capture_check_reads_a_capture_by_name :: proc(t: ^testing.T) {
	captures := []harness.Capture_Result {
		{name = "before", delta_mean = 0.2, stats = harness.Capture_Stats{mean = {x = 1, y = 2, z = 3, w = 4}}},
		{name = "after", delta_mean = 0.02, stats = harness.Capture_Stats{mean = {x = 2, y = 3, z = 4, w = 5}}},
	}
	mean := harness.Check_Command {
		field = "capture.named.after.stats.mean.y",
		op    = .Eq,
		value = {kind = .Number, number = 3},
	}
	mean_result := harness.check_evaluate(mean, {}, captures, nil, context.allocator)
	defer harness.check_result_destroy(&mean_result, context.allocator)
	testing.expectf(t, mean_result.ok, "named stats check failed: %s", mean_result.error)

	delta := harness.Check_Command {
		field = "capture.named.after.delta_mean",
		op    = .Lt,
		value = {kind = .Number, number = 0.1},
	}
	delta_result := harness.check_evaluate(delta, {}, captures, nil, context.allocator)
	defer harness.check_result_destroy(&delta_result, context.allocator)
	testing.expectf(t, delta_result.ok, "named delta check failed: %s", delta_result.error)

	missing := harness.Check_Command {
		field = "capture.named.missing.stats.mean.y",
		op    = .Eq,
		value = {kind = .Number, number = 3},
	}
	missing_result := harness.check_evaluate(missing, {}, captures, nil, context.allocator)
	defer harness.check_result_destroy(&missing_result, context.allocator)
	testing.expect(t, missing_result.error != "", "a missing capture name was accepted")
}

@(test)
object_check_reads_the_state_by_id :: proc(t: ^testing.T) {
	state := harness.State {
		objects = []harness.Object_State {
			{
				id = 7,
				prefab = "Crate",
				body = "dynamic",
				position = {x = 0, y = 1, z = 2},
				rotation = {w = 1},
				scale = 1,
				spawn_age = 0,
			},
		},
	}
	position := harness.Check_Command {
		field = "objects.7.position.z",
		op    = .Eq,
		value = {kind = .Number, number = 2},
	}
	result := harness.check_evaluate(position, state, {}, nil, context.allocator)
	defer harness.check_result_destroy(&result, context.allocator)
	testing.expectf(t, result.ok, "object position check failed: %s", result.error)

	prefab := harness.Check_Command {
		field = "objects.7.prefab",
		op    = .Eq,
		value = {kind = .String, text = "Crate"},
	}
	result = harness.check_evaluate(prefab, state, {}, nil, context.allocator)
	defer harness.check_result_destroy(&result, context.allocator)
	testing.expectf(t, result.ok, "object prefab check failed: %s", result.error)

	count := harness.Check_Command {
		field = "objects.count",
		op    = .Eq,
		value = {kind = .Number, number = 1},
	}
	result = harness.check_evaluate(count, state, {}, nil, context.allocator)
	defer harness.check_result_destroy(&result, context.allocator)
	testing.expectf(t, result.ok, "object count check failed: %s", result.error)
}

@(test)
bare_state_field_reports_an_error_without_crashing :: proc(t: ^testing.T) {
	command := harness.Check_Command {
		field = "sun",
		op    = .Eq,
		value = {kind = .Number, number = 0},
	}
	result := harness.check_evaluate(command, {}, {}, nil, context.allocator)
	defer harness.check_result_destroy(&result, context.allocator)
	testing.expect(t, result.error != "", "a bare sun field did not report an error")
}

@(test)
object_check_reads_the_state_by_name :: proc(t: ^testing.T) {
	state := harness.State {
		objects = []harness.Object_State {
			{
				id = 4,
				name = "room-a-lamp",
				prefab = "Lamp",
				body = "static",
				position = {x = 1, y = 2, z = 3},
				rotation = {w = 1},
			},
		},
	}
	command := harness.Check_Command {
		field = "objects.room-a-lamp.position.z",
		op    = .Eq,
		value = {kind = .Number, number = 3},
	}
	result := harness.check_evaluate(command, state, {}, nil, context.allocator)
	defer harness.check_result_destroy(&result, context.allocator)
	testing.expectf(t, result.ok, "named object check failed: %s", result.error)
}

@(test)
advisory_is_recorded_on_the_result :: proc(t: ^testing.T) {
	command := harness.Check_Command {
		field = "capture.worst_mean_delta",
		op = .Le,
		value = {kind = .Number, number = 0.1},
		advisory = true,
	}
	captures := []harness.Capture_Result{{delta_mean = 0.2}}
	result := harness.check_evaluate(command, {}, captures, nil, context.allocator)
	defer harness.check_result_destroy(&result, context.allocator)
	testing.expect(t, result.advisory, "the result lost the advisory flag")
	testing.expect(t, !result.ok, "the advisory check passed")
}

@(test)
advisory_miss_keeps_the_session_running_but_an_error_does_not :: proc(t: ^testing.T) {
	session, create_error := harness.session_create(context.allocator)
	if create_error != "" {
		testing.expectf(t, false, "session create failed: %s", create_error)
		return
	}
	defer harness.session_destroy(&session)

	miss_line := `{"cmd": "check", "field": "player.position.y", "op": "gt", "value": 100, "advisory": true}`
	miss_command, miss_parse := harness.command_parse_string(miss_line, context.allocator)
	defer harness.command_destroy(&miss_command, context.allocator)
	if miss_parse != "" {
		testing.expectf(t, false, "miss parse failed: %s", miss_parse)
		return
	}
	miss_reply := harness.session_execute(&session, miss_command, miss_line)
	testing.expectf(t, miss_reply.ok, "an advisory miss failed the command: %s", miss_reply.error)
	testing.expect(t, miss_reply.check != nil && !miss_reply.check.ok, "the advisory miss was not recorded")
	harness.reply_destroy(&miss_reply, context.allocator)

	error_line := `{"cmd": "check", "field": "player.position.nope", "op": "eq", "value": 1, "advisory": true}`
	error_command, error_parse := harness.command_parse_string(error_line, context.allocator)
	defer harness.command_destroy(&error_command, context.allocator)
	if error_parse != "" {
		testing.expectf(t, false, "error parse failed: %s", error_parse)
		return
	}
	error_reply := harness.session_execute(&session, error_command, error_line)
	testing.expect(t, !error_reply.ok, "an advisory field error passed the command")
	testing.expect(t, error_reply.check != nil && error_reply.check.error != "", "the field error was not recorded")
	harness.reply_destroy(&error_reply, context.allocator)
}

@(test)
object_paths_that_are_not_decimal_ids_read_names :: proc(t: ^testing.T) {
	state := harness.State {
		objects = []harness.Object_State {
			{id = 1, prefab = "Crate", body = "dynamic", rotation = {w = 1}},
			{id = 2, name = "0x1", prefab = "Lamp", body = "static", rotation = {w = 1}},
		},
	}
	command := harness.Check_Command {
		field = "objects.0x1.prefab",
		op = .Eq,
		value = {kind = .String, text = "Lamp"},
	}
	result := harness.check_evaluate(command, state, {}, nil, context.allocator)
	defer harness.check_result_destroy(&result, context.allocator)
	testing.expectf(t, result.ok, "a non-decimal handle did not read the name: %s", result.error)
}
