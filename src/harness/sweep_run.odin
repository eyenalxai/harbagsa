#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"

@(private)
sweep_parameters_copy :: proc(
	overrides: []Parameter_Override,
	allocator: mem.Allocator,
) -> []Scenario_Parameter {
	if len(overrides) == 0 {
		return nil
	}
	parameters := make([]Scenario_Parameter, len(overrides), allocator)
	for override, index in overrides {
		parameters[index] = {
			name  = strings.clone(override.name, allocator),
			value = strings.clone(override.value, allocator),
		}
	}
	return parameters
}

@(private)
sweep_run_destroy :: proc(run: ^Sweep_Run, allocator: mem.Allocator) {
	for parameter in run.parameters {
		delete(parameter.name, allocator)
		delete(parameter.value, allocator)
	}
	delete(run.parameters, allocator)
	if run.run_dir != "" {
		delete(run.run_dir, allocator)
	}
	if run.report != "" {
		delete(run.report, allocator)
	}
	if run.state != "" {
		delete(run.state, allocator)
	}
	if run.digest != "" {
		delete(run.digest, allocator)
	}
	if run.error != "" {
		delete(run.error, allocator)
	}
	run^ = {}
}

@(private)
sweep_report_destroy :: proc(report: ^Sweep_Report, allocator: mem.Allocator) {
	for &run in report.runs {
		sweep_run_destroy(&run, allocator)
	}
	delete(report.runs, allocator)
	delete(report.scenario, allocator)
	report^ = {}
}

@(private)
sweep_run_from_result :: proc(
	overrides: []Parameter_Override,
	result: Run_Result,
	allocator: mem.Allocator,
) -> Sweep_Run {
	return {
		parameters = sweep_parameters_copy(overrides, allocator),
		run_dir = strings.clone(result.summary.run_dir, allocator),
		report = strings.clone(result.summary.report, allocator),
		state = strings.clone(result.summary.state, allocator),
		digest = strings.clone(result.summary.digest, allocator),
		exit_code = result.exit_code,
		ok = result.summary.ok,
		error = strings.clone(result.summary.error, allocator),
	}
}

run_sweep :: proc(file: ^Scenario_File, options: Run_Options, combinations: int) -> int {
	base, owned := run_output_dir(
		options.scenario,
		options.out_dir,
		options.common.tag,
		context.allocator,
	)
	defer if owned {
		delete(base, context.allocator)
	}
	absolute_base, absolute_error := absolute_path(base, context.allocator)
	if absolute_error != nil {
		print_summary_failure("cannot resolve the sweep directory", EXIT_SCENARIO)
		return EXIT_SCENARIO
	}
	defer delete(absolute_base, context.allocator)
	if mkdir_error := os.make_directory_all(absolute_base); mkdir_error != nil {
		print_summary_failure("cannot create the sweep directory", EXIT_SCENARIO)
		return EXIT_SCENARIO
	}

	runs := make([dynamic]Sweep_Run, 0, combinations, context.allocator)
	report := Sweep_Report {
		ok       = true,
		scenario = strings.clone(file.path, context.allocator),
	}
	defer sweep_report_destroy(&report, context.allocator)

	parameter_array := options.parameters
	buffer: [MAX_SWEEP_PARAMETERS]Parameter_Override
	for index in 0 ..< combinations {
		overrides := sweep_combination(
			parameter_array[:options.parameter_count],
			index,
			buffer[:],
		)
		label := sweep_label(overrides, context.allocator)
		out_dir := join_path({absolute_base, label}, context.allocator)
		scenario, load_error := scenario_file_parse(file, overrides, context.allocator)
		if load_error != "" {
			append(
				&runs,
				Sweep_Run {
					parameters = sweep_parameters_copy(overrides, context.allocator),
					exit_code = EXIT_SCENARIO,
					error = load_error,
				},
			)
			report.ok = false
			report.exit_code = max(report.exit_code, EXIT_SCENARIO)
			delete(out_dir, context.allocator)
			delete(label, context.allocator)
			continue
		}
		result := run_scenario(&scenario, options, out_dir)
		scenario_destroy(&scenario, context.allocator)
		run := sweep_run_from_result(overrides, result, context.allocator)
		run_result_destroy(&result)
		if !run.ok {
			report.ok = false
		}
		report.exit_code = max(report.exit_code, run.exit_code)
		append(&runs, run)
		delete(out_dir, context.allocator)
		delete(label, context.allocator)
	}
	report.runs = runs[:]

	sweep_path := join_path({absolute_base, "sweep.json"}, context.allocator)
	defer delete(sweep_path, context.allocator)
	if write_error := write_json_file(sweep_path, report); write_error != "" {
		print_summary_failure(write_error, EXIT_RENDER)
		delete(write_error, context.allocator)
		return EXIT_RENDER
	}
	print_sweep_report(report)
	return report.exit_code
}

@(private)
print_sweep_report :: proc(report: Sweep_Report) {
	data, marshal_error := json.marshal(report, {}, context.allocator)
	if marshal_error != nil {
		fmt.println(`{"ok":false,"exit_code":3,"error":"cannot encode the sweep summary"}`)
		return
	}
	defer delete(data, context.allocator)
	fmt.println(string(data))
}
