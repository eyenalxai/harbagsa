#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"

Check_Table_Row :: struct {
	field:    string     `json:"field"`,
	op:       string     `json:"op"`,
	value:    string     `json:"value"`,
	actual:   string     `json:"actual"`,
	advisory: bool       `json:"advisory,omitempty"`,
	ok:       bool       `json:"ok"`,
	error:    string     `json:"error,omitempty"`,
	margin:   Maybe(f64) `json:"margin,omitempty"`,
}

Check_Table :: struct {
	ok:    bool             `json:"ok"`,
	run:   string           `json:"run"`,
	rows:  []Check_Table_Row `json:"checks"`,
}

cli_checks :: proc(args: []string) -> int {
	json_output := false
	run_dir := ""
	for argument in args {
		switch {
		case argument == "--help" || argument == "-h":
			print_checks_usage()
			return EXIT_OK
		case argument == "--json":
			json_output = true
		case strings.has_prefix(argument, "-"):
			fmt.eprintf("harbagsa-agent checks: unknown option %q\n", argument)
			print_checks_usage()
			return EXIT_SCENARIO
		case run_dir == "":
			run_dir = argument
		case:
			fmt.eprintln("harbagsa-agent checks: checks takes one run directory")
			print_checks_usage()
			return EXIT_SCENARIO
		}
	}
	if run_dir == "" {
		fmt.eprintln("harbagsa-agent checks: checks needs a run directory")
		print_checks_usage()
		return EXIT_SCENARIO
	}

	report_path := join_path({run_dir, "report.json"}, context.allocator)
	defer delete(report_path, context.allocator)
	data, read_error := os.read_entire_file(report_path, context.allocator)
	if read_error != nil {
		fmt.eprintf("harbagsa-agent checks: cannot read %s: %v\n", report_path, read_error)
		return EXIT_SCENARIO
	}
	defer delete(data, context.allocator)

	value, parse_error := json.parse_string(string(data), .JSON, true, context.allocator)
	if parse_error != .None {
		fmt.eprintf("harbagsa-agent checks: cannot parse %s: %v\n", report_path, parse_error)
		return EXIT_SCENARIO
	}
	defer json.destroy_value(value, context.allocator)
	object, object_ok := json_object(value)
	if !object_ok {
		fmt.eprintf("harbagsa-agent checks: %s is not a report\n", report_path)
		return EXIT_SCENARIO
	}

	rows, rows_error := check_table_rows(object, context.allocator)
	if rows_error != "" {
		fmt.eprintf("harbagsa-agent checks: %s\n", rows_error)
		delete(rows_error, context.allocator)
		return EXIT_SCENARIO
	}
	defer check_table_rows_destroy(rows, context.allocator)

	table := Check_Table{ok = true, run = run_dir, rows = rows}
	for row in rows {
		if !row.ok && !row.advisory {
			table.ok = false
		}
	}
	if json_output {
		data_out, marshal_error := json.marshal(table, {}, context.allocator)
		if marshal_error != nil {
			fmt.eprintln("harbagsa-agent checks: cannot encode the check table")
			return EXIT_RENDER
		}
		defer delete(data_out, context.allocator)
		fmt.println(string(data_out))
	} else {
		print_check_table(table)
	}
	return table.ok ? EXIT_OK : EXIT_CHECK
}

@(private)
check_table_rows :: proc(object: json.Object, allocator: mem.Allocator) -> ([]Check_Table_Row, string) {
	checks_value, has_checks := json_get(object, "checks")
	if !has_checks {
		return {}, format_error("%s", "the report holds no checks")
	}
	array, array_ok := json_array(checks_value)
	if !array_ok {
		return {}, format_error("%s", "the report checks are not an array")
	}
	rows := make([]Check_Table_Row, len(array), allocator)
	for item, index in array {
		entry, entry_ok := json_object(item)
		if !entry_ok {
			check_table_rows_destroy(rows, allocator)
			return {}, fmt.aprintf("check %d is not an object", index, allocator = allocator)
		}
		row, row_error := check_table_row(entry, allocator)
		if row_error != "" {
			check_table_rows_destroy(rows, allocator)
			return {}, row_error
		}
		rows[index] = row
	}
	return rows, ""
}

@(private)
check_table_row :: proc(entry: json.Object, allocator: mem.Allocator) -> (Check_Table_Row, string) {
	row := Check_Table_Row{}
	if field, ok := string_field(entry, "field"); ok {
		row.field = strings.clone(field, allocator)
	}
	if op, ok := string_field(entry, "op"); ok {
		row.op = strings.clone(op, allocator)
	}
	row.value = check_table_value(entry, "value", allocator)
	row.actual = check_table_value(entry, "actual", allocator)
	if error, ok := string_field(entry, "error"); ok {
		row.error = strings.clone(error, allocator)
	}
	if ok_value, has := json_get(entry, "ok"); has {
		row.ok, _ = json_boolean(ok_value)
	}
	if advisory_value, has := json_get(entry, "advisory"); has {
		row.advisory, _ = json_boolean(advisory_value)
	}
	if row.error == "" {
		row.margin = check_table_margin(row.op, row.value, row.actual)
	}
	return row, ""
}

@(private)
check_table_value :: proc(entry: json.Object, key: string, allocator: mem.Allocator) -> string {
	value, has := json_get(entry, key)
	if !has {
		return ""
	}
	if text, ok := json_string(value); ok {
		return strings.clone(text, allocator)
	}
	if number, ok := json_number(value); ok {
		return fmt.aprintf("%g", number, allocator = allocator)
	}
	if boolean, ok := json_boolean(value); ok {
		return strings.clone(boolean ? "true" : "false", allocator)
	}
	return ""
}

// The margin is the distance from the gate in the pass direction. A negative
// margin means the check failed.
@(private)
check_table_margin :: proc(op, gate, actual: string) -> Maybe(f64) {
	expected, expected_ok := strconv.parse_f64(gate)
	value, actual_ok := strconv.parse_f64(actual)
	if !expected_ok || !actual_ok {
		return nil
	}
	switch op {
	case "lt", "le":
		return expected - value
	case "gt", "ge":
		return value - expected
	case "eq", "ne":
		return abs(value - expected)
	}
	return nil
}

@(private)
print_check_table :: proc(table: Check_Table) {
	fmt.printf("run: %s\n", table.run)
	fmt.printf("%-6s %-42s %-3s %-12s %-12s %-12s %s\n", "STATUS", "FIELD", "OP", "GATE", "ACTUAL", "MARGIN", "ERROR")
	for row in table.rows {
		status := row.ok ? "PASS" : "FAIL"
		if !row.ok && row.advisory {
			status = "ADVISE"
		}
		margin := "-"
		if value, has := row.margin.?; has {
			margin_text: [32]byte
			margin = fmt.bprintf(margin_text[:], "%.4g", value)
		}
		fmt.printf(
			"%-6s %-42s %-3s %-12s %-12s %-12s %s\n",
			status,
			row.field,
			row.op,
			row.value,
			row.actual,
			margin,
			row.error,
		)
	}
}

@(private)
check_table_rows_destroy :: proc(rows: []Check_Table_Row, allocator: mem.Allocator) {
	for row in rows {
		if row.field != "" {
			delete(row.field, allocator)
		}
		if row.op != "" {
			delete(row.op, allocator)
		}
		if row.value != "" {
			delete(row.value, allocator)
		}
		if row.actual != "" {
			delete(row.actual, allocator)
		}
		if row.error != "" {
			delete(row.error, allocator)
		}
	}
	delete(rows, allocator)
}

@(private)
print_checks_usage :: proc() {
	fmt.eprintln("usage: harbagsa-agent checks <run-dir> [--json]")
	fmt.eprintln("")
	fmt.eprintln("Print every check in report.json with its gate and margin.")
	fmt.eprintln("--json prints one object with the run and the check rows.")
}
