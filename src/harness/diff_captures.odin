#+vet explicit-allocators
package harness

import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"

Diff_Capture :: struct {
	name: string,
	path: string,
}

diff_captures_destroy :: proc(captures: []Diff_Capture, allocator: mem.Allocator) {
	for capture in captures {
		delete(capture.name, allocator)
		delete(capture.path, allocator)
	}
	delete(captures, allocator)
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
