#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"
import "core:mem"

suite_print_table :: proc(report: Suite_Report) {
	passed := 0
	for row in report.rows {
		if row.ok {
			passed += 1
		}
	}
	fmt.printf(
		"suite %s: %d entries, %d passed, %d failed, %.3fs\n",
		report.suite,
		len(report.rows),
		passed,
		len(report.rows) - passed,
		report.seconds,
	)
	fmt.printf(
		"%-6s %-28s %-4s %-8s %-10s %-6s %-6s %s\n",
		"STATUS",
		"ENTRY",
		"CODE",
		"TIME",
		"SIZE",
		"GATE",
		"MODE",
		"RUN",
	)
	for row in report.rows {
		status := row.ok ? "PASS" : "FAIL"
		gate := row.requires_renderer_debug ? "debug" : "-"
		mode := row.no_render ? "cpu" : "render"
		fmt.printf(
			"%-6s %-28s %-4d % 7.2fs %-10s %-6s %-6s %s\n",
			status,
			row.label,
			row.exit_code,
			row.seconds,
			row.size,
			gate,
			mode,
			row.run_dir,
		)
		detail := row.error != "" ? row.error : row.failure
		if detail != "" {
			fmt.printf("       %s\n", detail)
		}
	}
	if report.run_dir != "" {
		fmt.printf("report: %s/suite.json\n", report.run_dir)
	}
}

suite_print_list :: proc(rows: []Suite_Row, suite: string) {
	fmt.printf("suite %s: %d entries\n", suite, len(rows))
	fmt.printf("%-28s %-10s %-6s %-6s %s\n", "ENTRY", "SIZE", "GATE", "MODE", "SCENARIO")
	for row in rows {
		if !row.ok {
			fmt.printf("%-28s %-10s %-6s %-6s %s\n", row.label, row.size, "?", "?", row.scenario)
			if row.error != "" {
				fmt.printf("       %s\n", row.error)
			}
			continue
		}
		gate := row.requires_renderer_debug ? "debug" : "-"
		mode := row.no_render ? "cpu" : "render"
		fmt.printf("%-28s %-10s %-6s %-6s %s\n", row.label, row.size, gate, mode, row.scenario)
	}
}

suite_print_json :: proc(report: Suite_Report) {
	data, marshal_error := json.marshal(report, {}, context.allocator)
	if marshal_error != nil {
		fmt.eprintln("harbagsa-agent suite: cannot encode the report")
		return
	}
	defer delete(data, context.allocator)
	fmt.println(string(data))
}

suite_print_rows_json :: proc(rows: []Suite_Row, suite, manifest: string) {
	report := Suite_Report {
		ok       = suite_rows_ok(rows),
		suite    = suite,
		manifest = manifest,
		rows     = rows,
	}
	suite_print_json(report)
}

suite_report_destroy :: proc(report: ^Suite_Report, allocator: mem.Allocator) {
	if report.suite != "" {
		delete(report.suite, allocator)
	}
	if report.manifest != "" {
		delete(report.manifest, allocator)
	}
	if report.run_dir != "" {
		delete(report.run_dir, allocator)
	}
	if report.rows != nil {
		suite_rows_destroy(report.rows, allocator)
	}
	report^ = {}
}
