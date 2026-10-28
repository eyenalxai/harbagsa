#+vet explicit-allocators
package harness

import "core:c"
import "core:mem"
import "core:os"

import stb_image "vendor:stb/image"

load_png_rgba :: proc(
	path: string,
	allocator: mem.Allocator,
) -> (
	pixels: []u8,
	width, height: u32,
	ok: bool,
) {
	data, read_error := os.read_entire_file(path, allocator)
	if read_error != nil {
		return nil, 0, 0, false
	}
	defer delete(data, allocator)
	pixels_width, pixels_height, channels: c.int
	loaded := stb_image.load_from_memory(
		raw_data(data),
		c.int(len(data)),
		&pixels_width,
		&pixels_height,
		&channels,
		4,
	)
	if loaded == nil || pixels_width <= 0 || pixels_height <= 0 {
		return nil, 0, 0, false
	}
	size := int(pixels_width) * int(pixels_height) * 4
	pixels = make([]u8, size, allocator)
	copy(pixels, loaded[:size])
	stb_image.image_free(loaded)
	return pixels, u32(pixels_width), u32(pixels_height), true
}
