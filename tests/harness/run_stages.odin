#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:os"
import "core:strings"
import "core:testing"

import "src:harness"

RUN_DIR :: "/tmp/opencode/harbagsa-run-test"

@(test)
run_exit_code_takes_the_highest_stage_code :: proc(t: ^testing.T) {
	passing := []harness.Stage_Result {
		{stage = .Prepare, exit_code = harness.EXIT_OK},
		{stage = .Execute, exit_code = harness.EXIT_OK},
		{stage = .Collect, exit_code = harness.EXIT_OK},
		{stage = .Publish, exit_code = harness.EXIT_OK},
		{stage = .Swap, exit_code = harness.EXIT_OK},
	}
	testing.expect_value(t, harness.run_exit_code(passing), harness.EXIT_OK)

	check := []harness.Stage_Result{{stage = .Execute, exit_code = harness.EXIT_CHECK}}
	testing.expect_value(t, harness.run_exit_code(check), harness.EXIT_CHECK)

	render := []harness.Stage_Result{{stage = .Collect, exit_code = harness.EXIT_RENDER}}
	testing.expect_value(t, harness.run_exit_code(render), harness.EXIT_RENDER)

	check_and_render := []harness.Stage_Result {
		{stage = .Execute, exit_code = harness.EXIT_CHECK},
		{stage = .Collect, exit_code = harness.EXIT_RENDER},
	}
	testing.expect_value(t, harness.run_exit_code(check_and_render), harness.EXIT_RENDER)

	scenario := []harness.Stage_Result{{stage = .Prepare, exit_code = harness.EXIT_SCENARIO}}
	testing.expect_value(t, harness.run_exit_code(scenario), harness.EXIT_SCENARIO)
}

@(test)
run_writes_a_report_without_a_renderer :: proc(t: ^testing.T) {
	_ = os.remove_all(RUN_DIR)
	scenario := harness.Scenario{}
	options := harness.Run_Options {
		common = {width = 320, height = 200, no_render = true},
	}
	result := harness.run_scenario(&scenario, options, RUN_DIR)
	defer harness.run_result_destroy(&result)
	testing.expect_value(t, result.exit_code, harness.EXIT_OK)
	testing.expect(t, result.summary.ok, "a clean run reported a failure")
	testing.expectf(t, result.summary.digest != "", "the run has no digest")
	testing.expect(t, os.exists(RUN_DIR + "/report.json"), "the run wrote no report.json")
	testing.expect(t, os.exists(RUN_DIR + "/state.json"), "the run wrote no state.json")
	log_text, log_error := os.read_entire_file(RUN_DIR + "/run.log", context.allocator)
	defer delete(log_text, context.allocator)
	testing.expectf(
		t,
		log_error == nil && strings.contains(string(log_text), "harness: 0 commands"),
		"run.log holds no runner lines",
	)
	_ = os.remove_all(RUN_DIR)
}
