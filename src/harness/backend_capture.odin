#+vet explicit-allocators
package harness

import "core:slice"
import "core:strings"

import "src:renderer"
import vk "vendor:vulkan"

@(private)
backend_capture :: proc(
	data: ^Backend_Data,
	session: ^Session,
	request: Capture_Request,
) -> (
	Capture_Result,
	string,
) {
	pixels, width, height, format, ok := renderer.read_capture_target(&data.renderer, request.target)
	if !ok {
		return {}, format_error("capture readback failed")
	}
	result := Capture_Result {
		name          = strings.clone(request.name, data.allocator),
		frame         = session.frame,
		width         = width,
		height        = height,
		target        = renderer.capture_target_name(request.target),
		format        = capture_format_name(request.format),
		target_format = renderer.format_name(format),
	}
	write_error: string
	switch request.format {
	case .Png:
		write_error = backend_capture_png(data, session, request, &result, pixels, width, height)
	case .Float:
		write_error = backend_capture_float(data, request, &result, pixels, format)
	case .Raw:
		path, error := capture_write_file(
			data.frames_dir,
			request.name,
			capture_format_extension(request.format),
			pixels,
			data.allocator,
		)
		write_error = error
		if error == "" {
			result.path = path
			result.hash = pixel_hash(pixels, data.allocator)
		}
	case .Stats:
		write_error = backend_capture_stats(data, request, &result, pixels, width, height, format)
	}
	if write_error != "" {
		capture_result_destroy(&result, data.allocator)
		return {}, write_error
	}
	return result, ""
}

@(private)
backend_capture_png :: proc(
	data: ^Backend_Data,
	session: ^Session,
	request: Capture_Request,
	result: ^Capture_Result,
	pixels: []u8,
	width, height: u32,
) -> string {
	written, error := capture_write_png(
		data.frames_dir,
		request.name,
		session.frame,
		width,
		height,
		pixels,
		data.allocator,
	)
	if error != "" {
		return error
	}
	delete(result.name, data.allocator)
	written.target = result.target
	written.format = result.format
	written.target_format = result.target_format
	delta := Capture_Delta{}
	if data.previous_pixels != nil &&
	   data.previous_width == width &&
	   data.previous_height == height &&
	   len(data.previous_pixels) == len(pixels) {
		delta = capture_delta(data.previous_pixels, pixels)
	}
	written.delta_mean = delta.mean
	written.delta_max = delta.max
	written.delta_over_16 = delta.over_16
	if len(data.previous_pixels) != len(pixels) {
		delete(data.previous_pixels, data.allocator)
		data.previous_pixels = make([]u8, len(pixels), data.allocator)
	}
	copy(data.previous_pixels, pixels)
	data.previous_width = width
	data.previous_height = height
	result^ = written
	return ""
}

@(private)
backend_capture_float :: proc(
	data: ^Backend_Data,
	request: Capture_Request,
	result: ^Capture_Result,
	pixels: []u8,
	format: vk.Format,
) -> string {
	values := renderer.capture_values(pixels, format, data.allocator)
	if values == nil {
		return format_error("cannot convert the %s capture to floats", renderer.format_name(format))
	}
	defer delete(values, data.allocator)
	bytes := slice.to_bytes(values)
	path, error := capture_write_file(
		data.frames_dir,
		request.name,
		capture_format_extension(request.format),
		bytes,
		data.allocator,
	)
	if error != "" {
		return error
	}
	result.path = path
	result.hash = pixel_hash(bytes, data.allocator)
	return ""
}

@(private)
backend_capture_stats :: proc(
	data: ^Backend_Data,
	request: Capture_Request,
	result: ^Capture_Result,
	pixels: []u8,
	width, height: u32,
	format: vk.Format,
) -> string {
	values := renderer.capture_values(pixels, format, data.allocator)
	if values == nil {
		return format_error("cannot convert the %s capture to floats", renderer.format_name(format))
	}
	defer delete(values, data.allocator)
	result.stats = capture_stats(values, width, height, request.target, data.allocator)
	return ""
}
