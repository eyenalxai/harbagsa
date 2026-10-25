#+vet explicit-allocators
package harness

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"

suite_execute :: proc(
	entries: []Suite_Entry,
	manifest, name: string,
	options: Suite_Options,
) -> (Suite_Execution, string) {
	base, owned := run_output_dir(manifest, options.out_dir, options.tag, context.allocator)
	defer if owned {
		delete(base, context.allocator)
	}
	absolute_base, absolute_error := absolute_path(base, context.allocator)
	if absolute_error != nil {
		return {}, format_error("%s", "cannot resolve the suite directory")
	}
	if mkdir_error := os.make_directory_all(absolute_base); mkdir_error != nil {
		delete(absolute_base, context.allocator)
		return {}, format_error("%s", "cannot create the suite directory")
	}

	report := Suite_Report {
		ok       = true,
		suite    = strings.clone(name, context.allocator),
		manifest = strings.clone(manifest, context.allocator),
		run_dir  = strings.clone(absolute_base, context.allocator),
	}
	rows := make([dynamic]Suite_Row, 0, len(entries), context.allocator)
	for entry in entries {
		row := suite_run_entry(entry, absolute_base, options)
		if !row.ok {
			report.ok = false
		}
		report.exit_code = max(report.exit_code, row.exit_code)
		append(&rows, row)
		if options.fail_fast && !row.ok {
			break
		}
	}
	report.rows = rows[:]
	return {report = report, base_dir = absolute_base}, ""
}

@(private)
suite_run_entry :: proc(entry: Suite_Entry, base_dir: string, options: Suite_Options) -> Suite_Row {
	scenario_path := suite_scenario_path(entry.scenario, context.allocator)
	defer delete(scenario_path, context.allocator)
	label := suite_entry_label(entry, context.temp_allocator)
	row := Suite_Row {
		scenario = strings.clone(scenario_path, context.allocator),
		label    = strings.clone(label, context.allocator),
		size     = strings.clone(entry.size, context.allocator),
		no_render = options.no_render || entry.no_render,
	}
	if row.size == "" {
		row.size = strings.clone("1280x720", context.allocator)
	}

	parameters := entry.parameters
	overrides := parameters[:entry.parameter_count]
	file, read_error := scenario_file_read(scenario_path, context.allocator)
	if read_error != "" {
		row.exit_code = EXIT_SCENARIO
		row.error = read_error
		return row
	}
	defer scenario_file_destroy(&file, context.allocator)
	scenario, load_error := scenario_file_parse(&file, overrides, context.allocator)
	if load_error != "" {
		row.exit_code = EXIT_SCENARIO
		row.error = load_error
		return row
	}
	defer scenario_destroy(&scenario, context.allocator)
	row.requires_renderer_debug = scenario.requires.renderer_debug
	if !entry.has_size && scenario.has_size {
		delete(row.size, context.allocator)
		row.size = fmt.aprintf("%dx%d", scenario.size[0], scenario.size[1], allocator = context.allocator)
	}

	run_options := Run_Options {
		scenario = scenario_path,
		common   = {
			width          = DEFAULT_WIDTH,
			height         = DEFAULT_HEIGHT,
			present        = options.present,
			no_render      = options.no_render || entry.no_render,
			no_analysis    = options.no_analysis,
			debug_renderer = options.debug_renderer,
			verbose        = options.verbose,
		},
	}
	if entry.has_size {
		width, height, _ := parse_size(entry.size)
		run_options.common.width = width
		run_options.common.height = height
		run_options.common.has_size = true
	}
	out_dir := join_path({base_dir, row.label}, context.allocator)
	defer delete(out_dir, context.allocator)
	result := run_scenario(&scenario, run_options, out_dir)
	defer run_result_destroy(&result)
	row.run_dir = strings.clone(result.summary.run_dir, context.allocator)
	row.report = strings.clone(result.summary.report, context.allocator)
	row.state = strings.clone(result.summary.state, context.allocator)
	row.digest = strings.clone(result.summary.digest, context.allocator)
	row.exit_code = result.exit_code
	row.ok = result.exit_code == EXIT_OK
	row.checks_total = result.summary.checks_total
	row.checks_failed = result.summary.checks_failed
	if result.summary.error != "" {
		row.error = strings.clone(result.summary.error, context.allocator)
	}
	if result.summary.failure != "" {
		row.failure = strings.clone(result.summary.failure, context.allocator)
	}
	return row
}

suite_list :: proc(entries: []Suite_Entry, allocator: mem.Allocator) -> ([]Suite_Row, string) {
	rows := make([]Suite_Row, len(entries), allocator)
	for entry, index in entries {
		scenario_path := suite_scenario_path(entry.scenario, allocator)
		label := suite_entry_label(entry, context.temp_allocator)
		row := Suite_Row {
			scenario  = strings.clone(scenario_path, allocator),
			label     = strings.clone(label, allocator),
			size      = strings.clone(entry.size, allocator),
			no_render = entry.no_render,
			ok        = true,
		}
		if row.size == "" {
			row.size = strings.clone("1280x720", allocator)
		}
		parameters := entry.parameters
		file, read_error := scenario_file_read(scenario_path, context.allocator)
		if read_error != "" {
			delete(scenario_path, allocator)
			row.ok = false
			row.error = read_error
			rows[index] = row
			continue
		}
		scenario, load_error := scenario_file_parse(&file, parameters[:entry.parameter_count], context.allocator)
		scenario_file_destroy(&file, context.allocator)
		if load_error != "" {
			delete(scenario_path, allocator)
			row.ok = false
			row.error = load_error
			rows[index] = row
			continue
		}
		row.requires_renderer_debug = scenario.requires.renderer_debug
		if scenario.has_size {
			delete(row.size, allocator)
			row.size = fmt.aprintf("%dx%d", scenario.size[0], scenario.size[1], allocator = allocator)
		}
		scenario_destroy(&scenario, context.allocator)
		delete(scenario_path, allocator)
		rows[index] = row
	}
	return rows, ""
}
