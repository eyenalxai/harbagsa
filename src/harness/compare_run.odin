#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"

Compare_Run :: struct {
	dir:       string,
	captures:  []Diff_Capture,
	scenario:  string,
	revision:  string,
	dirty:     bool,
	width:     u32,
	height:    u32,
	has_report: bool,
}

compare_run_load :: proc(dir: string, allocator: mem.Allocator) -> (Compare_Run, string) {
	if !os.is_dir(dir) {
		return {}, fmt.aprintf("%s is not a run directory", dir, allocator = allocator)
	}
	captures, captures_error := diff_captures_load(dir, allocator)
	if captures_error != "" {
		return {}, captures_error
	}
	run := Compare_Run {
		dir = strings.clone(dir, allocator),
		captures = captures,
		revision = strings.clone("unknown", allocator),
		scenario = strings.clone("unknown", allocator),
	}
	report_path := join_path({dir, "report.json"}, allocator)
	defer delete(report_path, allocator)
	data, read_error := os.read_entire_file(report_path, allocator)
	if read_error != nil {
		return run, ""
	}
	defer delete(data, allocator)
	value, parse_error := json.parse_string(string(data), .JSON, true, allocator)
	if parse_error != .None {
		return run, ""
	}
	defer json.destroy_value(value, allocator)
	object, object_ok := json_object(value)
	if !object_ok {
		return run, ""
	}
	run.has_report = true
	if scenario_value, has := json_get(object, "scenario"); has {
		if scenario, scenario_ok := json_object(scenario_value); scenario_ok {
			if path, path_ok := string_field(scenario, "path"); path_ok && path != "" {
				delete(run.scenario, allocator)
				run.scenario = strings.clone(path, allocator)
			}
		}
	}
	if setup_value, has := json_get(object, "setup"); has {
		if setup, setup_ok := json_object(setup_value); setup_ok {
			if revision, revision_ok := string_field(setup, "revision"); revision_ok && revision != "" {
				delete(run.revision, allocator)
				run.revision = strings.clone(revision, allocator)
			}
			if dirty, dirty_ok := json_get(setup, "dirty"); dirty_ok {
				run.dirty, _ = json_boolean(dirty)
			}
			if width, width_ok := json_get(setup, "width"); width_ok {
				if value, value_ok := json_integer(width); value_ok {
					run.width = u32(value)
				}
			}
			if height, height_ok := json_get(setup, "height"); height_ok {
				if value, value_ok := json_integer(height); value_ok {
					run.height = u32(value)
				}
			}
		}
	}
	return run, ""
}

compare_run_destroy :: proc(run: ^Compare_Run, allocator: mem.Allocator) {
	if run.dir != "" {
		delete(run.dir, allocator)
	}
	if run.scenario != "" {
		delete(run.scenario, allocator)
	}
	if run.revision != "" {
		delete(run.revision, allocator)
	}
	if run.captures != nil {
		diff_captures_destroy(run.captures, allocator)
	}
	run^ = {}
}

@(private)
compare_pairs :: proc(
	first, second: Compare_Run,
	allocator: mem.Allocator,
) -> ([]Compare_Pair, []string) {
	pairs := make([dynamic]Compare_Pair, 0, len(first.captures), allocator)
	errors := make([dynamic]string, 0, 4, allocator)
	for capture in first.captures {
		other, found := diff_capture_find(second.captures, capture.name)
		other_capture: Diff_Capture
		if found {
			other_capture = other^
		}
		pair := compare_pair_build(capture, other_capture, found, allocator)
		if !pair.ok {
			append(&errors, fmt.aprintf(
				"pair %q: %s",
				pair.name,
				pair.error,
				allocator = allocator,
			))
		}
		append(&pairs, pair)
	}
	for capture in second.captures {
		if _, found := diff_capture_find(first.captures, capture.name); found {
			continue
		}
		pair := compare_pair_build({}, capture, false, allocator)
		append(&errors, fmt.aprintf("pair %q: %s", pair.name, pair.error, allocator = allocator))
		append(&pairs, pair)
	}
	return pairs[:], errors[:]
}

@(private)
compare_pair_build :: proc(
	first, second: Diff_Capture,
	has_second: bool,
	allocator: mem.Allocator,
) -> Compare_Pair {
	name := first.name != "" ? first.name : second.name
	pair := Compare_Pair{name = strings.clone(name, allocator)}
	if first.path == "" {
		pair.missing_a = true
		pair.error = strings.clone("missing capture in run A", allocator)
		return pair
	}
	if !has_second || second.path == "" {
		pair.missing_b = true
		pair.error = strings.clone("missing capture in run B", allocator)
		return pair
	}
	first_pixels, first_width, first_height, first_ok := load_png_rgba(first.path, allocator)
	defer delete(first_pixels, allocator)
	second_pixels, second_width, second_height, second_ok := load_png_rgba(second.path, allocator)
	defer delete(second_pixels, allocator)
	if !first_ok || !second_ok {
		pair.decode_error = true
		pair.error = strings.clone("cannot decode the PNG", allocator)
		return pair
	}
	if first_width != second_width || first_height != second_height {
		pair.size_mismatch = true
		pair.width = first_width
		pair.height = first_height
		pair.error = fmt.aprintf(
			"size mismatch: A is %dx%d, B is %dx%d",
			first_width,
			first_height,
			second_width,
			second_height,
			allocator = allocator,
		)
		return pair
	}
	diff := diff_pair_build(name, first_pixels, second_pixels, first_width, first_height)
	pair.ok = true
	pair.width = diff.width
	pair.height = diff.height
	pair.different_pixels = diff.different_pixels
	pair.max_delta = diff.max_delta
	pair.mean_delta = diff.mean_delta
	pair.over_16 = diff.over_16
	return pair
}

compare_pairs_ok :: proc(pairs: []Compare_Pair) -> bool {
	for pair in pairs {
		if !pair.ok {
			return false
		}
	}
	return true
}

compare_pairs_destroy :: proc(pairs: []Compare_Pair, allocator: mem.Allocator) {
	for pair in pairs {
		delete(pair.name, allocator)
		if pair.error != "" {
			delete(pair.error, allocator)
		}
	}
	delete(pairs, allocator)
}
