#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

join_path :: proc(parts: []string, allocator := context.allocator) -> string {
	joined, join_error := filepath.join(parts, allocator)
	if join_error != nil {
		return ""
	}
	return joined
}

absolute_path :: proc(path: string, allocator := context.allocator) -> (string, os.Error) {
	if filepath.is_abs(path) {
		return filepath.clean(path, allocator)
	}
	working_directory, working_error := os.get_working_directory(allocator)
	if working_error != nil {
		return "", working_error
	}
	defer delete(working_directory, allocator)
	return filepath.join({working_directory, path}, allocator)
}

write_json_file :: proc(path: string, value: any) -> string {
	data, marshal_error := json.marshal(value, {pretty = true}, context.allocator)
	if marshal_error != nil {
		return fmt.aprintf("cannot encode JSON: %v", marshal_error, allocator = context.allocator)
	}
	defer delete(data, context.allocator)
	if write_error := os.write_entire_file(path, data); write_error != nil {
		return fmt.aprintf("cannot write %s: %v", path, write_error, allocator = context.allocator)
	}
	return ""
}

build_summary :: proc(report: Report, out_dir: string) -> Run_Summary {
	summary := Run_Summary {
		ok        = report.ok,
		exit_code = report.exit_code,
		run_dir   = strings.clone(out_dir, context.allocator),
		report    = join_path({out_dir, "report.json"}, context.allocator),
		state     = join_path({out_dir, "state.json"}, context.allocator),
		digest    = strings.clone(report.digest, context.allocator),
		error     = strings.clone(report.error, context.allocator),
	}
	screenshots := make([dynamic]string, 0, len(report.screenshots), context.allocator)
	for capture in report.screenshots {
		if capture.path != "" {
			append(&screenshots, strings.clone(capture.path, context.allocator))
		}
	}
	summary.screenshots = screenshots[:]
	return summary
}

summary_destroy :: proc(summary: ^Run_Summary) {
	delete(summary.run_dir, context.allocator)
	delete(summary.report, context.allocator)
	delete(summary.state, context.allocator)
	delete(summary.digest, context.allocator)
	if summary.error != "" {
		delete(summary.error, context.allocator)
	}
	for path in summary.screenshots {
		delete(path, context.allocator)
	}
	delete(summary.screenshots, context.allocator)
	summary^ = {}
}

swap_run_dir :: proc(final, staging: string) -> string {
	previous := fmt.aprintf("%s.previous", final, allocator = context.temp_allocator)
	_ = os.remove_all(previous)
	had_previous := os.rename(final, previous) == nil
	if rename_error := os.rename(staging, final); rename_error != nil {
		if had_previous {
			_ = os.rename(previous, final)
		}
		return fmt.aprintf(
			"cannot replace %s: %v",
			final,
			rename_error,
			allocator = context.allocator,
		)
	}
	if had_previous {
		_ = os.remove_all(previous)
	}
	return ""
}

print_summary :: proc(summary: Run_Summary) {
	data, marshal_error := json.marshal(summary, {}, context.allocator)
	if marshal_error != nil {
		fmt.println(`{"ok":false,"exit_code":3,"error":"cannot encode the run summary"}`)
		return
	}
	defer delete(data, context.allocator)
	fmt.println(string(data))
}

print_summary_failure :: proc(message: string, exit_code: int) {
	summary := Run_Summary{ok = false, exit_code = exit_code, error = message}
	print_summary(summary)
}
