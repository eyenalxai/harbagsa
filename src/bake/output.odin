#+vet explicit-allocators
#+vet !unused-procedures // the tool and the harness share this writer
package bake

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"

TIME_SUFFIX :: ".time"

Time_Read :: enum {
	Missing,
	Ok,
	Invalid,
}

time_path :: proc(path: string, allocator := context.allocator) -> string {
	return strings.concatenate({path, TIME_SUFFIX}, allocator)
}

// The artifact bytes stay deterministic, so the measured wall time travels
// beside the artifact instead of inside it.
write_time :: proc(path: string, bake_ms: u32) -> string {
	buffer: [32]u8
	text := fmt.bprintf(buffer[:], "%d\n", bake_ms)
	return write_file(time_path(path, context.temp_allocator), transmute([]u8)text)
}

read_time :: proc(path: string) -> (bake_ms: u32, status: Time_Read) {
	sidecar := time_path(path, context.temp_allocator)
	data, read_error := os.read_entire_file(sidecar, context.temp_allocator)
	if read_error != nil {
		if general, ok := read_error.(os.General_Error); ok && general == .Not_Exist {
			return 0, .Missing
		}
		return 0, .Invalid
	}
	value, parsed := strconv.parse_u64(strings.trim_space(string(data)))
	if !parsed || value > u64(0xFFFFFFFF) {
		return 0, .Invalid
	}
	return u32(value), .Ok
}

// Write an artifact through a temporary file so a failed write never leaves a
// half-written bake at the load path.
write_file :: proc(path: string, bytes: []u8) -> string {
	directory := filepath.dir(path)
	if directory != "" && directory != "." && !os.is_dir(directory) {
		if mkdir_error := os.mkdir_all(directory); mkdir_error != nil {
			return fmt.aprintf(
				"cannot create %s: %v",
				directory,
				mkdir_error,
				allocator = context.allocator,
			)
		}
	}
	temporary := strings.concatenate({path, ".tmp"}, context.allocator)
	defer delete(temporary, context.allocator)
	if write_error := os.write_entire_file(temporary, bytes); write_error != nil {
		return fmt.aprintf(
			"cannot write %s: %v",
			temporary,
			write_error,
			allocator = context.allocator,
		)
	}
	if rename_error := os.rename(temporary, path); rename_error != nil {
		_ = os.remove(temporary)
		return fmt.aprintf(
			"cannot publish %s: %v",
			path,
			rename_error,
			allocator = context.allocator,
		)
	}
	return ""
}
