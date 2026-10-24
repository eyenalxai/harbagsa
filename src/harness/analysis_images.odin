#+vet explicit-allocators
package harness

import "core:c"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:strings"

import stb_image "vendor:stb/image"

@(private)
analysis_write_maps :: proc(
	staging_dir, final_frames_dir: string,
	first, last: []u8,
	variances: []f32,
	max_variance: f32,
	width, height: u32,
	allocator: mem.Allocator,
) -> (
	Analysis_Maps,
	string,
) {
	pixel_count := len(first) / 4
	diff := make([]u8, pixel_count * 4, allocator)
	defer delete(diff, allocator)
	variance := make([]u8, pixel_count * 4, allocator)
	defer delete(variance, allocator)
	for pixel in 0 ..< pixel_count {
		base := pixel * 4
		diff[base + 0] = u8(abs(i32(last[base + 0]) - i32(first[base + 0])))
		diff[base + 1] = u8(abs(i32(last[base + 1]) - i32(first[base + 1])))
		diff[base + 2] = u8(abs(i32(last[base + 2]) - i32(first[base + 2])))
		diff[base + 3] = 255
		value: u8
		if max_variance > 0 {
			value = u8(clamp(math.sqrt(variances[pixel] / max_variance) * 255.0, 0, 255))
		}
		variance[base + 0] = value
		variance[base + 1] = value
		variance[base + 2] = value
		variance[base + 3] = 255
	}

	diff_name := "analysis-diff"
	variance_name := "analysis-variance"
	if error := analysis_write_png(staging_dir, diff_name, diff, width, height, allocator); error != "" {
		return {}, error
	}
	if error := analysis_write_png(staging_dir, variance_name, variance, width, height, allocator); error != "" {
		return {}, error
	}
	return {
		diff = join_path({final_frames_dir, "analysis-diff.png"}, allocator),
		variance = join_path({final_frames_dir, "analysis-variance.png"}, allocator),
	}, ""
}

@(private)
analysis_write_png :: proc(
	frames_dir, name: string,
	pixels: []u8,
	width, height: u32,
	allocator: mem.Allocator,
) -> string {
	path, path_error := capture_path(frames_dir, name, ".png", allocator)
	if path_error != "" {
		return path_error
	}
	defer delete(path, allocator)
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
		return fmt.aprintf("cannot write %s", path, allocator = allocator)
	}
	return ""
}

@(private)
analysis_load_png :: proc(
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
