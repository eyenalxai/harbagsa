#+vet explicit-allocators
package harness

EXIT_OK :: 0
EXIT_CHECK :: 1
EXIT_SCENARIO :: 2
EXIT_RENDER :: 3

// One scenario run's result, so a sweep can keep the summary without printing
// one JSON line per combination.
Run_Result :: struct {
	exit_code: int,
	summary:   Run_Summary,
}

run_batch :: proc(options: Run_Options) -> int {
	file, read_error := scenario_file_read(options.scenario, context.allocator)
	if read_error != "" {
		print_summary_failure(read_error, EXIT_SCENARIO)
		delete(read_error, context.allocator)
		return EXIT_SCENARIO
	}
	defer scenario_file_destroy(&file, context.allocator)

	parameter_array := options.parameters
	parameters := parameter_array[:options.parameter_count]
	combinations := sweep_combination_count(parameters)
	if combinations > 1 {
		return run_sweep(&file, options, combinations)
	}

	buffer: [MAX_SWEEP_PARAMETERS]Parameter_Override
	overrides: []Parameter_Override
	if len(parameters) > 0 {
		overrides = sweep_combination(parameters, 0, buffer[:])
	}
	scenario, load_error := scenario_file_parse(&file, overrides, context.allocator)
	if load_error != "" {
		print_summary_failure(load_error, EXIT_SCENARIO)
		delete(load_error, context.allocator)
		return EXIT_SCENARIO
	}
	defer scenario_destroy(&scenario, context.allocator)

	result := run_scenario(&scenario, options, "")
	defer run_result_destroy(&result)
	print_summary(result.summary)
	return result.exit_code
}

run_result_destroy :: proc(result: ^Run_Result) {
	summary_destroy(&result.summary)
	result^ = {}
}

// A render failure outranks a check, and a run that never started ranks above
// both.
run_exit_code :: proc(results: []Stage_Result) -> int {
	code := EXIT_OK
	for result in results {
		code = max(code, result.exit_code)
	}
	return code
}

run_scenario :: proc(scenario: ^Scenario, options: Run_Options, out_dir: string) -> Run_Result {
	results := make([dynamic]Stage_Result, 0, len(Run_Stage), context.allocator)
	defer stage_results_destroy(&results)
	state := Run_State {
		options  = options,
		scenario = scenario,
		out_dir  = out_dir,
	}
	defer run_state_destroy(&state)

	prepare := run_prepare(&state)
	// A context copy per procedure hides the stage's swap, so install it again.
	context.logger = state.has_logger ? state.logger : context.logger
	append(&results, prepare)
	if prepare.exit_code != EXIT_OK {
		return failed_result(prepare.error, prepare.exit_code)
	}
	append(&results, run_execute(&state))
	append(&results, run_collect(&state))
	publish := run_publish(&state, results[:])
	append(&results, publish)
	swap := run_swap(&state)
	append(&results, swap)
	if swap.exit_code != EXIT_OK {
		return failed_result(swap.error, EXIT_RENDER)
	}
	summary := build_summary(state.report, state.run_dir)
	if state.options.verbose {
		print_verbose_summary(state.report)
	} else if state.options.summary {
		print_compact_summary(state.report)
	}
	return {exit_code = run_exit_code(results[:]), summary = summary}
}
