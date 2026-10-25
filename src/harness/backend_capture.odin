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
		region        = request.region,
	}
	if region, has_region := request.region.?; has_region {
		if !capture_region_valid(region, width, height) {
			capture_result_destroy(&result, data.allocator)
			return {}, format_error("capture region must be inside the target")
		}
	}
	switch request.format {
	case .Png:
		return backend_capture_png(data, session, request, result, pixels, width, height)
	case .Float:
		return backend_capture_float(data, request, result, pixels, format)
	case .Raw:
		return backend_capture_raw(data, request, result, pixels)
	case .Stats:
		return backend_capture_stats(data, session, request, result, pixels, width, height, format)
	case .Profile:
		return backend_capture_profile(data, session, request, result, pixels, width, height)
	}
	return result, ""
}

@(private)
backend_capture_float :: proc(
	data: ^Backend_Data,
	request: Capture_Request,
	initial: Capture_Result,
	pixels: []u8,
	format: vk.Format,
) -> (
	Capture_Result,
	string,
) {
	result := initial
	values := renderer.capture_values(pixels, format, data.allocator)
	if values == nil {
		return {}, format_error("cannot convert the %s capture to floats", renderer.format_name(format))
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
		return {}, error
	}
	result.path = path
	result.hash = pixel_hash(bytes, data.allocator)
	return result, ""
}

@(private)
backend_capture_raw :: proc(
	data: ^Backend_Data,
	request: Capture_Request,
	initial: Capture_Result,
	pixels: []u8,
) -> (
	Capture_Result,
	string,
) {
	result := initial
	path, error := capture_write_file(
		data.frames_dir,
		request.name,
		capture_format_extension(request.format),
		pixels,
		data.allocator,
	)
	if error != "" {
		return {}, error
	}
	result.path = path
	result.hash = pixel_hash(pixels, data.allocator)
	return result, ""
}

@(private)
backend_capture_stats :: proc(
	data: ^Backend_Data,
	session: ^Session,
	request: Capture_Request,
	initial: Capture_Result,
	pixels: []u8,
	width, height: u32,
	format: vk.Format,
) -> (
	Capture_Result,
	string,
) {
	result := initial
	values := renderer.capture_values(pixels, format, data.allocator)
	if values == nil {
		return {}, format_error("cannot convert the %s capture to floats", renderer.format_name(format))
	}
	defer delete(values, data.allocator)
	result.stats = capture_stats(
		values,
		width,
		height,
		request.target,
		request.region,
		data.allocator,
	)
	if histogram, has_histogram := request.histogram.?; has_histogram {
		region := Capture_Region{x = 0, y = 0, w = int(width), h = int(height)}
		if bounds, has_region := request.region.?; has_region {
			region = bounds
		}
		result.histogram = capture_histogram_build(
			pixels,
			width,
			region,
			histogram,
			data.allocator,
		)
	}
	if request.png {
		result.png = true
		written, write_error := backend_capture_write_png(
			data,
			session,
			request,
			result,
			pixels,
			width,
			height,
		)
		if write_error != "" {
			capture_result_destroy(&result, data.allocator)
			return {}, write_error
		}
		return written, ""
	}
	return result, ""
}

@(private)
backend_capture_profile :: proc(
	data: ^Backend_Data,
	session: ^Session,
	request: Capture_Request,
	initial: Capture_Result,
	pixels: []u8,
	width, height: u32,
) -> (
	Capture_Result,
	string,
) {
	result := initial
	spec, has_profile := request.profile.?
	if !has_profile {
		return {}, format_error("a profile capture needs a profile")
	}
	profile, profile_error := capture_profile_build(pixels, width, height, spec, data.allocator)
	if profile_error != "" {
		return {}, profile_error
	}
	result.profile = profile
	if request.png {
		result.png = true
		written, write_error := backend_capture_write_png(
			data,
			session,
			request,
			result,
			pixels,
			width,
			height,
		)
		if write_error != "" {
			capture_result_destroy(&result, data.allocator)
			return {}, write_error
		}
		return written, ""
	}
	return result, ""
}
