#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

import "src:harness"

SUITE_DIR :: "/tmp/opencode/harbagsa-suite"

@(test)
suite_parse_reads_string_and_object_entries :: proc(t: ^testing.T) {
	_ = os.remove_all(SUITE_DIR)
	testing.expectf(t, os.make_directory_all(SUITE_DIR) == nil, "cannot create the suite directory")
	path := SUITE_DIR + "/read.json"
	body := `{
		"version": 1,
		"name": "renderer",
		"description": "test",
		"entries": [
			"smoke",
			{"scenario": "taa-motion", "label": "taa-motion-800", "size": "800x600"},
			{"scenario": "lamp-threshold", "params": {"lamp_x": 19.9}, "no_render": true}
		]
	}`
	testing.expectf(t, os.write_entire_file(path, body) == nil, "cannot write the manifest")
	defer os.remove(path)

	file, error := harness.suite_parse(path, body, context.allocator)
	defer harness.suite_file_destroy(&file, context.allocator)
	testing.expectf(t, error == "", "suite parse failed: %s", error)
	if error != "" {
		return
	}
	testing.expect_value(t, file.name, "renderer")
	testing.expect_value(t, len(file.entries), 3)
	if len(file.entries) == 3 {
		testing.expect_value(t, file.entries[0].scenario, "smoke")
		testing.expect_value(t, file.entries[1].label, "taa-motion-800")
		testing.expect_value(t, file.entries[1].size, "800x600")
		testing.expect(t, file.entries[2].no_render, "no_render was dropped")
		testing.expect_value(t, file.entries[2].parameter_count, 1)
	}
}

@(test)
suite_paths_resolve_from_the_repository_root :: proc(t: ^testing.T) {
	root := SUITE_DIR + "/root"
	_ = os.remove_all(SUITE_DIR)
	testing.expectf(t, os.make_directory_all(fmt.aprintf("%s/suites", root, allocator = context.temp_allocator)) == nil, "cannot create suites")
	testing.expectf(t, os.make_directory_all(fmt.aprintf("%s/scenarios", root, allocator = context.temp_allocator)) == nil, "cannot create scenarios")
	testing.expectf(t, os.make_directory_all(fmt.aprintf("%s/sub", root, allocator = context.temp_allocator)) == nil, "cannot create sub")
	defer os.remove_all(SUITE_DIR)
	previous, previous_error := os.get_working_directory(context.allocator)
	defer delete(previous, context.allocator)
	testing.expectf(t, previous_error == nil, "cannot read the working directory")
	defer os.set_working_directory(previous)
	testing.expectf(t, os.set_working_directory(fmt.aprintf("%s/sub", root, allocator = context.temp_allocator)) == nil, "cannot change directory")

	manifest := harness.suite_resolve_path("renderer", context.allocator)
	defer delete(manifest, context.allocator)
	testing.expect_value(t, manifest, fmt.aprintf("%s/suites/renderer.json", root, allocator = context.temp_allocator))
	scenario := harness.suite_scenario_path("smoke", context.allocator)
	defer delete(scenario, context.allocator)
	testing.expect_value(t, scenario, fmt.aprintf("%s/scenarios/smoke.json", root, allocator = context.temp_allocator))
}

@(test)
suite_parse_rejects_bad_entries :: proc(t: ^testing.T) {
	cases := []string {
		`{"entries":[]}`,
		`{"entries":[{"scenario":"smoke","unknown":1}]}`,
		`{"entries":["smoke","smoke"]}`,
		`{"entries":[{"scenario":"smoke","label":"bad label"}]}`,
		`{"entries":[{"scenario":"smoke","params":{"x":[1]}}]}`,
		`{"version":2,"entries":["smoke"]}`,
	}
	for body in cases {
		_, error := harness.suite_parse("/tmp/opencode/bad-suite.json", body, context.allocator)
		testing.expectf(t, error != "", "bad suite was accepted: %s", body)
		if error != "" {
			delete(error, context.allocator)
		}
	}
}

@(test)
suite_execute_runs_a_no_render_entry :: proc(t: ^testing.T) {
	_ = os.remove_all(SUITE_DIR)
	testing.expectf(t, os.make_directory_all(SUITE_DIR) == nil, "cannot create the suite directory")
	defer os.remove_all(SUITE_DIR)

	scenario_path := SUITE_DIR + "/one.json"
	scenario_body := `{"commands":[
		{"cmd":"step","frames":1},
		{"cmd":"check","field":"frame","op":"eq","value":1}
	]}`
	testing.expectf(t, os.write_entire_file(scenario_path, scenario_body) == nil, "cannot write the scenario")
	manifest := fmt.aprintf(
		`{{"version":1,"name":"test","entries":[{{"scenario":"%s","label":"one","no_render":true}}]}}`,
		scenario_path,
		allocator = context.temp_allocator,
	)
	file, parse_error := harness.suite_parse(SUITE_DIR + "/suite.json", manifest, context.allocator)
	defer harness.suite_file_destroy(&file, context.allocator)
	testing.expectf(t, parse_error == "", "suite parse failed: %s", parse_error)
	if parse_error != "" {
		return
	}
	options := harness.Suite_Options{out_dir = SUITE_DIR + "/out", no_render = true}
	execution, execute_error := harness.suite_execute(file.entries, file.path, file.name, options)
	defer harness.suite_execution_destroy(&execution, context.allocator)
	testing.expectf(t, execute_error == "", "suite execute failed: %s", execute_error)
	if execute_error != "" {
		return
	}
	testing.expect(t, execution.report.ok, "the suite failed")
	testing.expect_value(t, len(execution.report.rows), 1)
	if len(execution.report.rows) == 1 {
		row := execution.report.rows[0]
		testing.expect(t, row.ok, "the row failed")
		testing.expect_value(t, row.label, "one")
		testing.expect_value(t, row.checks_total, 1)
		testing.expect_value(t, row.checks_failed, 0)
		testing.expect(t, strings.has_suffix(row.run_dir, "/one"), "the run directory is wrong")
	}
}

@(test)
suite_list_reads_the_scenario_gate :: proc(t: ^testing.T) {
	_ = os.remove_all(SUITE_DIR)
	testing.expectf(t, os.make_directory_all(SUITE_DIR) == nil, "cannot create the suite directory")
	defer os.remove_all(SUITE_DIR)

	scenario_path := SUITE_DIR + "/gated.json"
	scenario_body := `{"requires":{"renderer_debug":true},"commands":[{"cmd":"renderer_debug","taa":false}]}`
	testing.expectf(t, os.write_entire_file(scenario_path, scenario_body) == nil, "cannot write the scenario")
	entry := harness.Suite_Entry{scenario = scenario_path}
	rows, error := harness.suite_list([]harness.Suite_Entry{entry}, context.allocator)
	defer harness.suite_rows_destroy(rows, context.allocator)
	testing.expectf(t, error == "", "suite list failed: %s", error)
	testing.expect_value(t, len(rows), 1)
	if len(rows) == 1 {
		testing.expect(t, rows[0].ok, "the gated row failed to parse")
		testing.expect(t, rows[0].requires_renderer_debug, "the gate was dropped")
	}
}

@(test)
suite_filters_select_by_scenario_stem_or_label :: proc(t: ^testing.T) {
	entries := []harness.Suite_Entry{
		{scenario = "smoke", label = "smoke"},
		{scenario = "taa-motion", label = "taa-motion-800"},
		{scenario = "lighting", label = "light"},
	}
	options := harness.Suite_Options{}
	options.only[0] = "taa-motion"
	options.only[1] = "light"
	options.only_count = 2
	filtered, error := harness.suite_entries_filter(entries, &options, context.allocator)
	testing.expectf(t, error == "", "only filter failed: %s", error)
	testing.expect_value(t, len(filtered.entries), 2)
	if len(filtered.entries) == 2 {
		testing.expect_value(t, filtered.entries[0].label, "taa-motion-800")
		testing.expect_value(t, filtered.entries[1].label, "light")
	}
	delete(filtered.entries, context.allocator)

	skip := harness.Suite_Options{}
	skip.skip[0] = "smoke"
	skip.skip_count = 1
	filtered, error = harness.suite_entries_filter(entries, &skip, context.allocator)
	testing.expectf(t, error == "", "skip filter failed: %s", error)
	testing.expect_value(t, len(filtered.entries), 2)
	delete(filtered.entries, context.allocator)

	missing := harness.Suite_Options{}
	missing.only[0] = "nope"
	missing.only_count = 1
	_, error = harness.suite_entries_filter(entries, &missing, context.allocator)
	testing.expect(t, error != "", "a missing filter name was accepted")
	if error != "" {
		delete(error, context.allocator)
	}
}
