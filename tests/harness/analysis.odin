#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:testing"

import "src:harness"

@(test)
analysis_period_finds_the_repeating_lag :: proc(t: ^testing.T) {
	pattern := [8]f32{0.1, 0.5, 0.3, 0.9, 0.2, 0.7, 0.4, 0.8}
	series: [32]f32
	for index in 0 ..< len(series) {
		series[index] = pattern[index % len(pattern)]
	}
	period := harness.analysis_period(series[:])
	testing.expect_value(t, period.frames, 8)
	testing.expectf(t, period.correlation > 0.9, "correlation is %v", period.correlation)
}

@(test)
analysis_period_rejects_a_flat_series :: proc(t: ^testing.T) {
	series := [16]f32{}
	period := harness.analysis_period(series[:])
	testing.expect_value(t, period.frames, 0)
}

@(test)
analysis_summary_aggregates_pairs :: proc(t: ^testing.T) {
	captures := []harness.Capture_Result {
		{frame = 0, width = 10, height = 10},
		{frame = 1, width = 10, height = 10, delta_mean = 0.2, delta_max = 20, delta_over_16 = 2},
		{frame = 2, width = 10, height = 10, delta_mean = 0.1, delta_max = 30, delta_over_16 = 4},
	}
	summary := harness.analysis_summary(captures)
	testing.expect_value(t, summary.pairs, 2)
	testing.expect_value(t, summary.worst_mean, f32(0.2))
	testing.expect_value(t, summary.worst_max, f32(30))
	testing.expect_value(t, summary.worst_over_16, 4)
	testing.expect_value(t, summary.worst_over_16_fraction, f32(0.04))
}

@(test)
analysis_window_selects_the_configured_slice :: proc(t: ^testing.T) {
	captures := []harness.Capture_Result {
		{frame = 0}, {frame = 1}, {frame = 2}, {frame = 3}, {frame = 4},
	}
	window := harness.analysis_window(captures, {enabled = true, has_window = true, start = 1, count = 2})
	testing.expect_value(t, len(window), 2)
	if len(window) == 2 {
		testing.expect_value(t, window[0].frame, 1)
		testing.expect_value(t, window[1].frame, 2)
	}
}

@(test)
capture_check_window_uses_start_and_count :: proc(t: ^testing.T) {
	captures := []harness.Capture_Result {
		{frame = 0}, {frame = 1}, {frame = 2}, {frame = 3},
	}
	command := harness.Check_Command {
		window = {start = 1, count = 2, has = true},
	}
	window := harness.check_capture_window(captures, command)
	testing.expect_value(t, len(window), 2)
	if len(window) == 2 {
		testing.expect_value(t, window[0].frame, 1)
		testing.expect_value(t, window[1].frame, 2)
	}

	warmup := harness.Check_Command{warmup = 2}
	window = harness.check_capture_window(captures, warmup)
	testing.expect_value(t, len(window), 2)
	if len(window) == 2 {
		testing.expect_value(t, window[0].frame, 2)
	}
}

@(test)
check_window_parses_and_rejects_bad_ranges :: proc(t: ^testing.T) {
	command, error := harness.command_parse_string(
		`{"cmd": "check", "field": "capture.count", "op": "ge", "value": 1,
		  "window": {"start": 2, "count": 4}}`,
		context.allocator,
	)
	defer harness.command_destroy(&command, context.allocator)
	testing.expectf(t, error == "", "window parse failed: %s", error)
	if error == "" {
		testing.expect(t, command.check.window.has, "window was dropped")
		testing.expect_value(t, command.check.window.start, 2)
		testing.expect_value(t, command.check.window.count, 4)
	}

	bad := []string{
		`{"cmd": "check", "field": "capture.count", "op": "ge", "value": 1, "window": {"start": 0}}`,
		`{"cmd": "check", "field": "capture.count", "op": "ge", "value": 1, "window": {"start": -1, "count": 2}}`,
		`{"cmd": "check", "field": "capture.count", "op": "ge", "value": 1, "window": {"start": 0, "count": 0}}`,
		`{"cmd": "check", "field": "capture.count", "op": "ge", "value": 1, "window": {"start": 0, "count": 2}, "warmup": 1}`,
	}
	for line in bad {
		_, line_error := harness.command_parse_string(line, context.allocator)
		testing.expectf(t, line_error != "", "bad window was accepted: %s", line)
	}
}

@(test)
scenario_analysis_parses_a_window_and_maps :: proc(t: ^testing.T) {
	scenario, error := harness.scenario_parse(
		`{"analysis": {"start": 4, "count": 8, "maps": true}, "steps": [{"frames": 1}]}`,
		context.allocator,
	)
	defer harness.scenario_destroy(&scenario, context.allocator)
	testing.expectf(t, error == "", "scenario parse failed: %s", error)
	if error == "" {
		testing.expect(t, scenario.analysis.enabled, "analysis is not enabled")
		testing.expect(t, scenario.analysis.has_window, "analysis window was dropped")
		testing.expect_value(t, scenario.analysis.start, 4)
		testing.expect_value(t, scenario.analysis.count, 8)
		testing.expect(t, scenario.analysis.maps, "maps were dropped")
	}

	disabled, disabled_error := harness.scenario_parse(
		`{"analysis": false, "steps": [{"frames": 1}]}`,
		context.allocator,
	)
	defer harness.scenario_destroy(&disabled, context.allocator)
	testing.expectf(t, disabled_error == "", "analysis:false failed: %s", disabled_error)
	testing.expect(t, !disabled.analysis.enabled, "analysis:false left analysis on")
}

@(test)
analysis_checks_read_the_period :: proc(t: ^testing.T) {
	command := harness.Check_Command {
		field = "analysis.period.frames",
		op    = .Eq,
		value = {kind = .Number, number = 8},
	}
	summary := harness.Analysis_Summary {
		pairs = 59,
		period = {frames = 8, correlation = 0.56},
	}
	result := harness.check_evaluate(command, {}, {}, &summary, context.allocator)
	defer harness.check_result_destroy(&result, context.allocator)
	testing.expect(t, result.ok, "period check did not pass")

	missing := harness.check_evaluate(command, {}, {}, nil, context.allocator)
	defer harness.check_result_destroy(&missing, context.allocator)
	testing.expect(t, missing.error != "", "analysis check passed without an analysis")
}
