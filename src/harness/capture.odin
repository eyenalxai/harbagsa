#+vet explicit-allocators
package harness

import "core:c"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"

import stb_image "vendor:stb/image"

import "src:renderer"

Capture_Target :: renderer.Capture_Target

Capture_Format :: enum {
	Png,
	Float,
	Raw,
	Stats,
}

capture_format_name :: proc(format: Capture_Format) -> string {
	switch format {
	case .Png:
		return "png"
	case .Float:
		return "float"
	case .Raw:
		return "raw"
	case .Stats:
		return "stats"
	}
	return "png"
}

capture_format_parse :: proc(name: string) -> (format: Capture_Format, ok: bool) {
	switch name {
	case "png":
		return .Png, true
	case "float":
		return .Float, true
	case "raw":
		return .Raw, true
	case "stats":
		return .Stats, true
	}
	return .Png, false
}

capture_format_extension :: proc(format: Capture_Format) -> string {
	switch format {
	case .Png:
		return ".png"
	case .Float:
		return ".f32"
	case .Raw:
		return ".bin"
	case .Stats:
		return ""
	}
	return ""
}

Capture_Request :: struct {
	name:    string,
	alpha:   f32,
	target:  Capture_Target,
	format:  Capture_Format,
	enabled: bool,
}

Capture_Result :: struct {
	name:          string         `json:"name"`,
	path:          string         `json:"path,omitempty"`,
	frame:         int            `json:"frame"`,
	width:         u32            `json:"width"`,
	height:        u32            `json:"height"`,
	target:        string         `json:"target"`,
	format:        string         `json:"format"`,
	target_format: string         `json:"target_format"`,
	hash:          string         `json:"hash,omitempty"`,
	stats:         Maybe(Capture_Stats) `json:"stats,omitempty"`,
	delta_mean:    f32            `json:"delta_mean"`,
	delta_max:     u8             `json:"delta_max"`,
	delta_over_16: int            `json:"delta_over_16"`,
}

Capture_Delta :: struct {
	mean:    f32,
	max:     u8,
	over_16: int,
}

Capture_Summary :: struct {
	count:                  int,
	worst_mean_delta:       f32,
	worst_max_delta:        u8,
	worst_over_16:          int,
	worst_over_16_fraction: f32,
	last_target:            string,
	last_format:            string,
	last_stats:             Maybe(Capture_Stats),
}

capture_summary :: proc(captures: []Capture_Result) -> Capture_Summary {
	summary := Capture_Summary{count = len(captures)}
	for capture in captures {
		summary.worst_mean_delta = max(summary.worst_mean_delta, capture.delta_mean)
		summary.worst_max_delta = max(summary.worst_max_delta, capture.delta_max)
		summary.worst_over_16 = max(summary.worst_over_16, capture.delta_over_16)
		pixels := f32(capture.width) * f32(capture.height)
		if pixels > 0 {
			summary.worst_over_16_fraction = max(
				summary.worst_over_16_fraction,
				f32(capture.delta_over_16) / pixels,
			)
		}
	}
	if len(captures) > 0 {
		last := captures[len(captures) - 1]
		summary.last_target = last.target
		summary.last_format = last.format
		summary.last_stats = last.stats
	}
	return summary
}

capture_delta :: proc(previous, current: []u8) -> Capture_Delta {
	count := min(len(previous), len(current)) / 4
	if count == 0 {
		return {}
	}
	total: u64
	highest: u8
	over_16: int
	for index in 0 ..< count {
		base := index * 4
		delta := abs(i32(current[base]) - i32(previous[base]))
		delta = max(delta, abs(i32(current[base + 1]) - i32(previous[base + 1])))
		delta = max(delta, abs(i32(current[base + 2]) - i32(previous[base + 2])))
		total += u64(delta)
		if delta > 16 {
			over_16 += 1
		}
		if delta > i32(highest) {
			highest = u8(delta)
		}
	}
	return {mean = f32(total) / f32(count), max = highest, over_16 = over_16}
}

capture_write_png :: proc(
	frames_dir, name: string,
	frame: int,
	width, height: u32,
	pixels: []u8,
	allocator: mem.Allocator,
) -> (Capture_Result, string) {
	path, path_error := capture_path(frames_dir, name, ".png", allocator)
	if path_error != "" {
		return {}, path_error
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
