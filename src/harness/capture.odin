#+vet explicit-allocators
package harness

import "core:c"
import "core:fmt"
import "core:mem"
import "core:path/filepath"
import "core:strings"

import stb_image "vendor:stb/image"

Capture_Result :: struct {
	name:   string `json:"name"`,
	path:   string `json:"path"`,
	frame:  int    `json:"frame"`,
	width:  u32    `json:"width"`,
	height: u32    `json:"height"`,
	hash:   string `json:"hash"`,
}

capture_write_png :: proc(
	frames_dir, name: string,
	frame: int,
	width, height: u32,
	pixels: []u8,
	allocator: mem.Allocator,
) -> (Capture_Result, string) {
	filename := fmt.aprintf("%s.png", name, allocator = context.temp_allocator)
	path, join_error := filepath.join({frames_dir, filename}, allocator)
	if join_error != nil {
		return {}, fmt.aprintf("cannot build capture path: %v", join_error, allocator = allocator)
	}
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	written := stb_image.write_png(
		cpath,
		c.int(width),
		c.int(height),
		4,
		raw_data(pixels),
		c.int(width * 4),
	)
	if written == 0 {
		error := fmt.aprintf("cannot write %s", path, allocator = allocator)
		delete(path, allocator)
		return {}, error
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

capture_result_destroy :: proc(result: ^Capture_Result, allocator: mem.Allocator) {
	if result.name != "" {
		delete(result.name, allocator)
	}
	if result.path != "" {
		delete(result.path, allocator)
	}
	if result.hash != "" {
		delete(result.hash, allocator)
	}
	result^ = {}
}

pixel_hash :: proc(pixels: []u8, allocator: mem.Allocator) -> string {
	hash: u64 = 0xcbf29ce484222325
	for pixel in pixels {
		hash = (hash ~ u64(pixel)) * 0x100000001b3
	}
	return fmt.aprintf("%016x", hash, allocator = allocator)
}
