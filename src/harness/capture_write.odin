#+vet explicit-allocators
package harness

import "core:c"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"

import stb_image "vendor:stb/image"

capture_write_png :: proc(
	frames_dir, name: string,
	frame: int,
	width, height: u32,
	pixels: []u8,
	allocator: mem.Allocator,
) -> (Capture_Result, string) {
	path, path_error := write_png_file(frames_dir, name, width, height, pixels, allocator)
	if path_error != "" {
		return {}, path_error
	}
	result := Capture_Result {
		name = strings.clone(name, allocator),
		path = path,
		frame = frame,
		width = width,
		height = height,
		hash = pixel_hash(pixels, allocator),
	}
	return result, ""
}

write_png_file :: proc(
	frames_dir, name: string,
	width, height: u32,
	pixels: []u8,
	allocator: mem.Allocator,
) -> (path: string, error: string) {
	written_path, path_error := capture_path(frames_dir, name, ".png", allocator)
	if path_error != "" {
		return "", path_error
	}
	cpath := strings.clone_to_cstring(written_path, context.temp_allocator)
	written := stb_image.write_png(
		cpath,
		c.int(width),
		c.int(height),
		4,
		raw_data(pixels),
		c.int(width * 4),
	)
	if written == 0 {
		message := fmt.aprintf("cannot write %s", written_path, allocator = allocator)
		delete(written_path, allocator)
		return "", message
	}
	return written_path, ""
}

capture_write_file :: proc(
	frames_dir, name, extension: string,
	data: []u8,
	allocator: mem.Allocator,
) -> (path: string, error: string) {
	written_path, path_error := capture_path(frames_dir, name, extension, allocator)
	if path_error != "" {
		return "", path_error
	}
	if write_error := os.write_entire_file(written_path, data); write_error != nil {
		message := fmt.aprintf(
			"cannot write %s: %v",
			written_path,
			write_error,
			allocator = allocator,
		)
		delete(written_path, allocator)
		return "", message
	}
	return written_path, ""
}

@(private)
capture_path :: proc(
	frames_dir, name, extension: string,
	allocator: mem.Allocator,
) -> (string, string) {
	filename := fmt.aprintf("%s%s", name, extension, allocator = context.temp_allocator)
	path, join_error := filepath.join({frames_dir, filename}, allocator)
	if join_error != nil {
		return "", fmt.aprintf("cannot build capture path: %v", join_error, allocator = allocator)
	}
	return path, ""
}

