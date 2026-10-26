#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:testing"

import "src:harness"

@(test)
coverage_fractions_count_zero_black_and_lit :: proc(t: ^testing.T) {
	values := []f32 {
		0, 0, 0, 255,
		255, 255, 255, 255,
		10, 10, 10, 255,
		100, 100, 100, 255,
	}
	coverage: harness.Capture_Coverage
	coverage.black = 1.0
	coverage.lit = 255.0
	stats := harness.capture_stats(
		values,
		2,
		2,
		.Color,
		nil,
		nil,
		nil,
		coverage,
		context.allocator,
	)
	testing.expect_value(t, stats.coverage.zero_fraction, f32(0.25))
	black, has_black := stats.coverage.black_fraction.?
	testing.expect(t, has_black, "the black fraction is missing")
	if has_black {
		testing.expect_value(t, black, f32(0.25))
	}
	lit, has_lit := stats.coverage.lit_fraction.?
	testing.expect(t, has_lit, "the lit fraction is missing")
	if has_lit {
		testing.expect_value(t, lit, f32(0.25))
	}
}

@(test)
coverage_reports_zero_fraction_without_a_threshold :: proc(t: ^testing.T) {
	values := []f32 {
		0, 0, 0, 1,
		0.5, 0, 0, 1,
		0, 0.5, 0, 1,
		0, 0, 0.5, 1,
	}
	stats := harness.capture_stats(
		values,
		2,
		2,
		.Scene_Color,
		nil,
		nil,
		nil,
		nil,
		context.allocator,
	)
	testing.expect_value(t, stats.coverage.zero_fraction, f32(0.25))
	_, has_black := stats.coverage.black_fraction.?
	testing.expect(t, !has_black, "a thresholdless capture reported a black fraction")
}

@(test)
coverage_needs_the_stats_format :: proc(t: ^testing.T) {
	_, parse_error := harness.command_parse_string(
		`{"cmd":"capture","name":"bad","coverage":{}}`,
		context.allocator,
	)
	testing.expect(t, parse_error != "", "a coverage block was accepted on a PNG capture")
	if parse_error != "" {
		delete(parse_error, context.allocator)
	}
}

@(test)
coverage_check_paths_resolve :: proc(t: ^testing.T) {
	captures := []harness.Capture_Result {
		{
			name = "cover",
			stats = harness.Capture_Stats {
				coverage = harness.Capture_Coverage_Stats {
					zero_fraction = 0.25,
					black = 1.0,
					black_fraction = 0.5,
					lit = 16.0,
					lit_fraction = 0.75,
				},
			},
		},
	}
	command := harness.Check_Command {
		field = "capture.named.cover.stats.coverage.zero_fraction",
		op = .Eq,
		value = {kind = .Number, number = 0.25},
	}
	result := harness.check_evaluate(command, {}, captures, nil, context.allocator)
	defer harness.check_result_destroy(&result, context.allocator)
	testing.expectf(t, result.ok, "coverage check failed: %s", result.error)
}
