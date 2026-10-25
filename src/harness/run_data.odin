#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"

Run_Metadata :: struct {
	dir:         string,
	scenario:    string,
	revision:    string,
	dirty:       bool,
	width:       u32,
	height:      u32,
	captures: int,
}

Run_Data :: struct {
	metadata: Run_Metadata,
	captures: []Diff_Capture,
}

run_data_load :: proc(dir: string, allocator: mem.Allocator) -> (Run_Data, string) {
	if !os.is_dir(dir) {
		return {}, fmt.aprintf("%s is not a run directory", dir, allocator = allocator)
	}
	data := Run_Data {
		metadata = {
			dir      = strings.clone(dir, allocator),
			scenario = strings.clone("unknown", allocator),
			revision = strings.clone("unknown", allocator),
		},
	}
	report_path := join_path({dir, "report.json"}, allocator)
	defer delete(report_path, allocator)
	report, read_error := os.read_entire_file(report_path, allocator)
	if read_error != nil {
		captures, captures_error := diff_captures_frames(dir, allocator)
		if captures_error != "" {
			run_data_destroy(&data, allocator)
			return {}, captures_error
		}
		data.captures = captures
		return data, ""
	}
	defer delete(report, allocator)

	value, parse_error := json.parse_string(string(report), .JSON, true, allocator)
	if parse_error != .None {
		run_data_destroy(&data, allocator)
		return {}, fmt.aprintf("cannot parse %s: %v", report_path, parse_error, allocator = allocator)
	}
	defer json.destroy_value(value, allocator)
	object, object_ok := json_object(value)
	if !object_ok {
		run_data_destroy(&data, allocator)
		return {}, fmt.aprintf("%s is not a report", report_path, allocator = allocator)
	}

	run_metadata_read(&data.metadata, object, allocator)
	captures, captures_ok := run_report_captures(object, dir, allocator)
	if captures_ok && len(captures) > 0 {
		data.captures = captures
		return data, ""
	}
	diff_captures_destroy(captures, allocator)
	frame_captures, captures_error := diff_captures_frames(dir, allocator)
	if captures_error != "" {
		run_data_destroy(&data, allocator)
		return {}, captures_error
	}
	data.captures = frame_captures
	return data, ""
}

@(private)
run_metadata_read :: proc(metadata: ^Run_Metadata, object: json.Object, allocator: mem.Allocator) {
	if scenario_value, has := json_get(object, "scenario"); has {
		if scenario, scenario_ok := json_object(scenario_value); scenario_ok {
			if path, path_ok := string_field(scenario, "path"); path_ok && path != "" {
				delete(metadata.scenario, allocator)
				metadata.scenario = strings.clone(path, allocator)
			}
		}
	}
	if setup_value, has := json_get(object, "setup"); has {
		if setup, setup_ok := json_object(setup_value); setup_ok {
			if revision, revision_ok := string_field(setup, "revision"); revision_ok && revision != "" {
				delete(metadata.revision, allocator)
				metadata.revision = strings.clone(revision, allocator)
			}
			if dirty, dirty_ok := json_get(setup, "dirty"); dirty_ok {
				metadata.dirty, _ = json_boolean(dirty)
			}
			if width, width_ok := json_get(setup, "width"); width_ok {
				if value, value_ok := json_integer(width); value_ok {
					metadata.width = u32(value)
				}
			}
			if height, height_ok := json_get(setup, "height"); height_ok {
				if value, value_ok := json_integer(height); value_ok {
					metadata.height = u32(value)
				}
			}
		}
	}
	if captures_value, has := json_get(object, "captures"); has {
		if captures, captures_ok := json_array(captures_value); captures_ok {
			metadata.captures = len(captures)
		}
	}
}

@(private)
run_report_captures :: proc(
	object: json.Object,
	run_dir: string,
	allocator: mem.Allocator,
) -> (
	[]Diff_Capture,
	bool,
) {
	captures_value, has := json_get(object, "captures")
	if !has {
		return nil, true
	}
	array, array_ok := json_array(captures_value)
	if !array_ok {
		return nil, false
	}
	items := make([dynamic]Diff_Capture, 0, len(array), allocator)
	for value_entry in array {
		entry, entry_ok := json_object(value_entry)
		if !entry_ok {
			continue
		}
		format, _ := string_field(entry, "format")
		png := false
		if png_value, has_png := json_get(entry, "png"); has_png {
			png, _ = json_boolean(png_value)
		}
		path, _ := string_field(entry, "path")
		if format != "" && format != "png" && !png {
			continue
		}
		name, _ := string_field(entry, "name")
		if name == "" && path != "" {
			name = filepath.stem(filepath.base(path))
		}
		if name == "" {
			continue
		}
		append(&items, {
			name = strings.clone(name, allocator),
			path = diff_capture_path(run_dir, name, path, allocator),
		})
	}
	return items[:], true
}

run_data_destroy :: proc(data: ^Run_Data, allocator: mem.Allocator) {
	if data.metadata.dir != "" {
		delete(data.metadata.dir, allocator)
	}
	if data.metadata.scenario != "" {
		delete(data.metadata.scenario, allocator)
	}
	if data.metadata.revision != "" {
		delete(data.metadata.revision, allocator)
	}
	if data.captures != nil {
		diff_captures_destroy(data.captures, allocator)
	}
	data^ = {}
}
