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
