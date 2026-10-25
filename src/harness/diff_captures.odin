#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

Diff_Capture :: struct {
	name: string,
	path: string,
}

diff_captures_load :: proc(
	run_dir: string,
	allocator: mem.Allocator,
) -> (
	captures: []Diff_Capture,
	error: string,
) {
	if !os.is_dir(run_dir) {
		return nil, fmt.aprintf("%s is not a run directory", run_dir, allocator = allocator)
	}
	report_path := join_path({run_dir, "report.json"}, allocator)
	defer delete(report_path, allocator)
	from_report, has_report, report_error := diff_captures_report(report_path, run_dir, allocator)
	if report_error != "" {
		return nil, report_error
	}
	if has_report && len(from_report) > 0 {
		return from_report, ""
	}
	diff_captures_destroy(from_report, allocator)
	return diff_captures_frames(run_dir, allocator)
}

diff_captures_destroy :: proc(captures: []Diff_Capture, allocator: mem.Allocator) {
	for capture in captures {
		delete(capture.name, allocator)
		delete(capture.path, allocator)
	}
	delete(captures, allocator)
}

@(private)
diff_captures_report :: proc(
	report_path, run_dir: string,
	allocator: mem.Allocator,
) -> (
	captures: []Diff_Capture,
	found: bool,
	error: string,
) {
	data, read_error := os.read_entire_file(report_path, allocator)
	if read_error != nil {
		return nil, false, ""
	}
	defer delete(data, allocator)
	value, parse_error := json.parse_string(string(data), .JSON, true, allocator)
	if parse_error != .None {
		return nil, true, fmt.aprintf(
			"cannot parse %s: %v",
			report_path,
			parse_error,
			allocator = allocator,
		)
	}
	defer json.destroy_value(value, allocator)
	object, object_ok := json_object(value)
	if !object_ok {
		return nil, true, fmt.aprintf("%s is not a report", report_path, allocator = allocator)
	}
	screenshots_value, has_screenshots := json_get(object, "screenshots")
	if !has_screenshots {
		return nil, true, ""
	}
	array, array_ok := json_array(screenshots_value)
	if !array_ok {
		return nil, true, fmt.aprintf(
			"%s has no screenshot list",
			report_path,
			allocator = allocator,
		)
	}
	items := make([dynamic]Diff_Capture, 0, len(array), allocator)
	for value_entry in array {
		entry, entry_ok := json_object(value_entry)
		if !entry_ok {
			continue
		}
		format, _ := string_field(entry, "format")
		png := false
		if png_value, has := json_get(entry, "png"); has {
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
	return items[:], true, ""
}

@(private)
diff_capture_path :: proc(run_dir, name, reported: string, allocator: mem.Allocator) -> string {
	filename := fmt.aprintf("%s.png", name, allocator = context.temp_allocator)
	local := join_path({run_dir, "frames", filename}, allocator)
	if os.is_file(local) {
		return local
	}
	delete(local, allocator)
	return strings.clone(reported, allocator)
}

@(private)
diff_captures_frames :: proc(
	run_dir: string,
	allocator: mem.Allocator,
) -> (
	[]Diff_Capture,
	string,
) {
	frames_dir := join_path({run_dir, "frames"}, allocator)
	defer delete(frames_dir, allocator)
	if !os.is_dir(frames_dir) {
		return nil, ""
	}
	infos, dir_error := os.read_all_directory_by_path(frames_dir, allocator)
	if dir_error != nil {
		return nil, fmt.aprintf(
			"cannot read %s: %v",
			frames_dir,
			dir_error,
			allocator = allocator,
		)
	}
	defer os.file_info_slice_delete(infos, allocator)
	items := make([dynamic]Diff_Capture, 0, len(infos), allocator)
	for info in infos {
		if info.type != .Regular || !strings.has_suffix(info.name, ".png") {
			continue
		}
		name := strings.trim_suffix(info.name, ".png")
		if name == "analysis-diff" || name == "analysis-variance" {
			continue
		}
		append(&items, {
			name = strings.clone(name, allocator),
			path = strings.clone(info.fullpath, allocator),
		})
	}
	slice.sort_by(items[:], diff_capture_less)
	return items[:], ""
}

@(private)
diff_capture_less :: proc(first, second: Diff_Capture) -> bool {
	return first.name < second.name
}

diff_capture_find :: proc(captures: []Diff_Capture, name: string) -> (^Diff_Capture, bool) {
	for &capture in captures {
		if capture.name == name {
			return &capture, true
		}
	}
	return nil, false
}
