#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:testing"

import "src:harness"

@(test)
capture_check_reads_the_summary :: proc(t: ^testing.T) {
	state := harness.State{}
	summary := harness.Capture_Summary {
		count            = 25,
		worst_mean_delta = 0.05,
		worst_max_delta  = 30,
		worst_over_16    = 100,
	}
	command := harness.Check_Command {
		field = "capture.worst_mean_delta",
		op    = .Le,
		value = {kind = .Number, number = 0.1},
	}
	result := harness.check_evaluate(command, state, summary, nil, context.allocator)
	defer harness.check_result_destroy(&result, context.allocator)
	testing.expect(t, result.ok, "capture mean check did not pass")
}

@(test)
capture_check_fails_above_the_limit :: proc(t: ^testing.T) {
	state := harness.State{}
	summary := harness.Capture_Summary {
		count            = 25,
		worst_mean_delta = 0.2,
		worst_max_delta  = 30,
		worst_over_16    = 100,
	}
	command := harness.Check_Command {
		field = "capture.worst_mean_delta",
		op    = .Le,
		value = {kind = .Number, number = 0.1},
	}
	result := harness.check_evaluate(command, state, summary, nil, context.allocator)
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
