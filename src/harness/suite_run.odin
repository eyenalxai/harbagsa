#+vet explicit-allocators
package harness

import "core:fmt"
import "core:mem"
import "core:strings"

Suite_Options :: struct {
	out_dir:        string,
	tag:            string,
	list:           bool,
	json:           bool,
	fail_fast:      bool,
	present:        bool,
	no_render:      bool,
	no_analysis:    bool,
	debug_renderer: bool,
	verbose:        bool,
}

Suite_Row :: struct {
	scenario:               string `json:"scenario"`,
	label:                  string `json:"label"`,
	size:                   string `json:"size"`,
	requires_renderer_debug: bool  `json:"requires_renderer_debug"`,
	no_render:              bool   `json:"no_render"`,
	run_dir:                string `json:"run_dir,omitempty"`,
	report:                 string `json:"report,omitempty"`,
	state:                  string `json:"state,omitempty"`,
	digest:                 string `json:"digest,omitempty"`,
	exit_code:              int    `json:"exit_code"`,
	ok:                     bool   `json:"ok"`,
	checks_total:           int    `json:"checks_total"`,
	checks_failed:          int    `json:"checks_failed"`,
	error:                  string `json:"error,omitempty"`,
	failure:                string `json:"failure,omitempty"`,
}

Suite_Report :: struct {
	ok:       bool        `json:"ok"`,
	exit_code: int        `json:"exit_code"`,
	suite:    string      `json:"suite"`,
	manifest: string      `json:"manifest"`,
	run_dir:  string      `json:"run_dir"`,
	rows:     []Suite_Row `json:"rows"`,
}

Suite_Execution :: struct {
	report:   Suite_Report,
	base_dir: string,
}

suite_run_command :: proc(selector: string, selectors: []string, options: Suite_Options) -> int {
	file, read_error := suite_file_read(selector, context.allocator)
	if read_error != "" {
		fmt.eprintf("harbagsa-agent suite: %s\n", read_error)
		delete(read_error, context.allocator)
		return EXIT_SCENARIO
	}
	defer suite_file_destroy(&file, context.allocator)

	entries := file.entries
	owned_entries: []Suite_Entry
	if len(selectors) > 0 {
		owned_entries = make([]Suite_Entry, len(selectors), context.allocator)
		for selector_name, index in selectors {
			owned_entries[index] = {scenario = strings.clone(selector_name, context.allocator)}
		}
		entries = owned_entries
	}
	defer if owned_entries != nil {
		for entry in owned_entries {
			suite_entry_destroy(entry, context.allocator)
		}
		delete(owned_entries, context.allocator)
	}

	if options.list {
		rows, list_error := suite_list(entries, context.allocator)
		defer suite_rows_destroy(rows, context.allocator)
		if list_error != "" {
			fmt.eprintf("harbagsa-agent suite: %s\n", list_error)
			delete(list_error, context.allocator)
			return EXIT_SCENARIO
		}
		if options.json {
			suite_print_rows_json(rows, file.name, file.path)
		} else {
			suite_print_list(rows, file.name)
		}
		return suite_rows_ok(rows) ? EXIT_OK : EXIT_SCENARIO
	}

	execution, execute_error := suite_execute(entries, file.path, file.name, options)
	if execute_error != "" {
		fmt.eprintf("harbagsa-agent suite: %s\n", execute_error)
		delete(execute_error, context.allocator)
		return EXIT_SCENARIO
	}
	defer suite_execution_destroy(&execution, context.allocator)

	report_path := join_path({execution.base_dir, "suite.json"}, context.allocator)
	defer delete(report_path, context.allocator)
	if write_error := write_json_file(report_path, execution.report); write_error != "" {
		fmt.eprintf("harbagsa-agent suite: %s\n", write_error)
		delete(write_error, context.allocator)
		return EXIT_RENDER
	}
	if options.json {
		suite_print_json(execution.report)
	} else {
		suite_print_table(execution.report)
	}
	return execution.report.exit_code
}

suite_rows_ok :: proc(rows: []Suite_Row) -> bool {
	for row in rows {
		if !row.ok {
			return false
		}
	}
	return true
}

suite_rows_destroy :: proc(rows: []Suite_Row, allocator: mem.Allocator) {
	for row in rows {
		delete(row.scenario, allocator)
		delete(row.label, allocator)
		delete(row.size, allocator)
		delete(row.run_dir, allocator)
		delete(row.report, allocator)
		delete(row.state, allocator)
		delete(row.digest, allocator)
		if row.error != "" {
			delete(row.error, allocator)
		}
		if row.failure != "" {
			delete(row.failure, allocator)
		}
	}
	delete(rows, allocator)
}

suite_execution_destroy :: proc(execution: ^Suite_Execution, allocator: mem.Allocator) {
	suite_report_destroy(&execution.report, allocator)
	if execution.base_dir != "" {
		delete(execution.base_dir, allocator)
	}
	execution^ = {}
}

cli_suite :: proc(args: []string) -> int {
	selector := ""
	selectors := make([dynamic]string, 0, 4, context.allocator)
	defer delete(selectors)
	options: Suite_Options
	index := 0
	for index < len(args) {
		argument := args[index]
		switch {
		case argument == "--help" || argument == "-h":
			print_suite_usage()
			return EXIT_OK
		case argument == "--out":
			if index + 1 >= len(args) {
				return suite_cli_error("--out needs a directory")
			}
			options.out_dir = args[index + 1]
			index += 2
		case argument == "--tag":
			if index + 1 >= len(args) {
				return suite_cli_error("--tag needs a name")
			}
			options.tag = args[index + 1]
			index += 2
		case argument == "--list":
			options.list = true
			index += 1
		case argument == "--json":
			options.json = true
			index += 1
		case argument == "--fail-fast":
			options.fail_fast = true
			index += 1
		case argument == "--present":
			options.present = true
			index += 1
		case argument == "--no-render":
			options.no_render = true
			index += 1
		case argument == "--no-analysis":
			options.no_analysis = true
			index += 1
		case argument == "--debug-renderer":
			options.debug_renderer = true
			index += 1
		case argument == "--verbose":
			options.verbose = true
			index += 1
		case strings.has_prefix(argument, "-"):
			return suite_cli_error(fmt.aprintf(
				"unknown option %q",
				argument,
				allocator = context.temp_allocator,
			))
		case selector == "":
			selector = argument
			index += 1
		case:
			append(&selectors, argument)
			index += 1
		}
	}
	if selector == "" {
		return suite_cli_error("suite needs a name or a manifest path")
	}
	return suite_run_command(selector, selectors[:], options)
}

@(private)
suite_cli_error :: proc(message: string) -> int {
	fmt.eprintf("harbagsa-agent suite: %s\n", message)
	print_suite_usage()
	return EXIT_SCENARIO
}

@(private)
print_suite_usage :: proc() {
	fmt.eprintln("usage: harbagsa-agent suite <name|path> [scenario...] [--out DIR] [--tag NAME]")
	fmt.eprintln("       [--list] [--json] [--fail-fast] [--present] [--no-render]")
	fmt.eprintln("       [--no-analysis] [--debug-renderer] [--verbose]")
}
