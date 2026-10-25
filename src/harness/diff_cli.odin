#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:strconv"
import "core:strings"

cli_diff :: proc(args: []string) -> int {
	for argument in args {
		if argument == "--help" || argument == "-h" {
			print_diff_usage()
			return EXIT_OK
		}
	}
	options, option_error := diff_options_parse(args)
	if option_error != "" {
		fmt.eprintf("harbagsa-agent diff: %s\n", option_error)
		delete(option_error, context.allocator)
		return EXIT_SCENARIO
	}
	report, run_error := diff_runs(options, context.allocator)
	if run_error != "" {
		fmt.eprintf("harbagsa-agent diff: %s\n", run_error)
		delete(run_error, context.allocator)
		return EXIT_SCENARIO
	}
	defer diff_report_destroy(&report, context.allocator)

	if options.json {
		diff_print_json(report)
	} else {
		diff_print_table(report)
	}
	for message in report.errors {
		fmt.eprintf("harbagsa-agent diff: %s\n", message)
	}
	return report.ok ? EXIT_OK : EXIT_CHECK
}

print_diff_usage :: proc() {
	fmt.eprintln("usage: harbagsa-agent diff <run-a> <run-b> [--max-pixels N] [--json]")
	fmt.eprintln("")
	fmt.eprintln("Compare PNG captures with the same name. The table names both runs,")
	fmt.eprintln("their scenarios, revisions, dirty flags, extents, and capture counts.")
	fmt.eprintln("--max-pixels N exits 1 when a pair has more than N different pixels.")
}

@(private)
diff_options_parse :: proc(args: []string) -> (Diff_Options, string) {
	options: Diff_Options
	index := 0
	for index < len(args) {
		argument := args[index]
		switch {
		case argument == "--json":
			options.json = true
			index += 1
		case argument == "--max-pixels":
			if index + 1 >= len(args) {
				return options, format_error("%s", "--max-pixels needs a count")
			}
			value, value_ok := strconv.parse_int(args[index + 1])
			if !value_ok || value < 0 {
				return options, format_error("%s", "--max-pixels must be a non-negative count")
			}
			options.max_pixels = value
			options.has_max_pixels = true
			index += 2
		case strings.has_prefix(argument, "-"):
			return options, fmt.aprintf(
				"unknown option %q",
				argument,
				allocator = context.allocator,
			)
		case options.run_a == "":
			options.run_a = argument
			index += 1
		case options.run_b == "":
			options.run_b = argument
			index += 1
		case:
			return options, format_error("%s", "diff takes two run directories")
		}
	}
	if options.run_a == "" || options.run_b == "" {
		return options, format_error("%s", "diff takes two run directories")
	}
	return options, format_error("%s", "")
}

@(private)
diff_runs :: proc(options: Diff_Options, allocator: mem.Allocator) -> (Diff_Report, string) {
	first, first_error := run_data_load(options.run_a, allocator)
	if first_error != "" {
		return {}, first_error
	}
	defer run_data_destroy(&first, allocator)
	second, second_error := run_data_load(options.run_b, allocator)
	if second_error != "" {
		return {}, second_error
	}
	defer run_data_destroy(&second, allocator)

	report := Diff_Report {
		run_a         = strings.clone(options.run_a, allocator),
		run_b         = strings.clone(options.run_b, allocator),
		revision_a    = strings.clone(first.metadata.revision, allocator),
		dirty_a       = first.metadata.dirty,
		scenario_a    = strings.clone(first.metadata.scenario, allocator),
		width_a       = first.metadata.width,
		height_a      = first.metadata.height,
		screenshots_a = first.metadata.screenshots,
		revision_b    = strings.clone(second.metadata.revision, allocator),
		dirty_b       = second.metadata.dirty,
		scenario_b    = strings.clone(second.metadata.scenario, allocator),
		width_b       = second.metadata.width,
		height_b      = second.metadata.height,
		screenshots_b = second.metadata.screenshots,
	}
	pairs := make([dynamic]Diff_Pair, 0, len(first.captures), allocator)
	errors := make([dynamic]string, 0, 4, allocator)
	report.ok = diff_compare(&pairs, &errors, first.captures, second.captures, options, allocator)
	report.pairs = pairs[:]
	report.errors = errors[:]
	return report, ""
}

@(private)
diff_compare :: proc(
	pairs: ^[dynamic]Diff_Pair,
	errors: ^[dynamic]string,
	first, second: []Diff_Capture,
	options: Diff_Options,
	allocator: mem.Allocator,
) -> bool {
	ok := true
	for capture in first {
		if _, found := diff_capture_find(second, capture.name); !found {
			append(errors, fmt.aprintf(
				"missing pair %q in %s",
				capture.name,
				options.run_b,
				allocator = allocator,
			))
			ok = false
		}
	}
	for capture in second {
		if _, found := diff_capture_find(first, capture.name); !found {
			append(errors, fmt.aprintf(
				"missing pair %q in %s",
				capture.name,
				options.run_a,
				allocator = allocator,
			))
			ok = false
		}
	}
	for capture in first {
		other, found := diff_capture_find(second, capture.name)
		if !found {
			continue
		}
		pair, pair_error := diff_pair_load(capture, other^, allocator)
		if pair_error != "" {
			append(errors, pair_error)
			ok = false
			continue
		}
		append(pairs, pair)
		if options.has_max_pixels && pair.different_pixels > options.max_pixels {
			append(errors, fmt.aprintf(
				"%s has %d different pixels, over the %d limit",
				pair.name,
				pair.different_pixels,
				options.max_pixels,
				allocator = allocator,
			))
			ok = false
		}
	}
	return ok
}

@(private)
diff_pair_load :: proc(
	first, second: Diff_Capture,
	allocator: mem.Allocator,
) -> (
	Diff_Pair,
	string,
) {
	first_pixels, first_width, first_height, first_ok := load_png_rgba(first.path, allocator)
	if !first_ok {
		return {}, fmt.aprintf(
			"%s: cannot read %s",
			first.name,
			first.path,
			allocator = allocator,
		)
	}
	defer delete(first_pixels, allocator)
	second_pixels, second_width, second_height, second_ok := load_png_rgba(
		second.path,
		allocator,
	)
	if !second_ok {
		return {}, fmt.aprintf(
			"%s: cannot read %s",
			second.name,
			second.path,
			allocator = allocator,
		)
	}
	defer delete(second_pixels, allocator)
	if first_width != second_width || first_height != second_height {
		return {}, fmt.aprintf(
			"%s: size mismatch %dx%d and %dx%d",
			first.name,
			first_width,
			first_height,
			second_width,
			second_height,
			allocator = allocator,
		)
	}
	pair := diff_pair_build(first.name, first_pixels, second_pixels, first_width, first_height)
	pair.name = strings.clone(first.name, allocator)
	return pair, ""
}

@(private)
diff_print_table :: proc(report: Diff_Report) {
	fmt.printf(
		"A  %s  rev %s%s  %dx%d  %d captures  %s\n",
		report.scenario_a,
		report.revision_a,
		report.dirty_a ? " dirty" : "",
		report.width_a,
		report.height_a,
		report.screenshots_a,
		report.run_a,
	)
	fmt.printf(
		"B  %s  rev %s%s  %dx%d  %d captures  %s\n",
		report.scenario_b,
		report.revision_b,
		report.dirty_b ? " dirty" : "",
		report.width_b,
		report.height_b,
		report.screenshots_b,
		report.run_b,
	)
	fmt.printf(
		"%-24s %7s %7s %11s %4s %8s %8s %s\n",
		"name",
		"width",
		"height",
		"different",
		"max",
		"mean",
		"over16",
		"identical",
	)
	for pair in report.pairs {
		fmt.printf(
			"%-24s % 7d % 7d % 11d % 4d % 8.3f % 8d %s\n",
			pair.name,
			pair.width,
			pair.height,
			pair.different_pixels,
			pair.max_delta,
			pair.mean_delta,
			pair.over_16,
			pair.identical ? "yes" : "no",
		)
	}
}

@(private)
diff_print_json :: proc(report: Diff_Report) {
	data, marshal_error := json.marshal(report, {}, context.allocator)
	if marshal_error != nil {
		fmt.println(`{"ok":false,"error":"cannot encode the diff report"}`)
		return
	}
	defer delete(data, context.allocator)
	fmt.println(string(data))
}
