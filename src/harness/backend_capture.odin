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
	slot: int,
) -> (
	Capture_Result,
	string,
) {
	pixels: []u8
	width, height: u32
	format: vk.Format
	readback_error: string
	if request.has_view && request.view != .Beauty {
		pixels, width, height, format, readback_error = renderer.read_capture_view(
			&data.renderer,
			request.view,
			slot,
		)
	} else {
		pixels, width, height, format, readback_error = renderer.read_capture_target(
			&data.renderer,
			request.target,
			slot,
		)
	}
	if readback_error != "" {
		return {}, readback_error
	}
	region: Maybe(Capture_Region)
	if spec, has_region := request.region.?; has_region {
		resolved, region_error := capture_region_resolve(spec, width, height)
		if region_error != "" {
			return {}, region_error
		}
		region = resolved
	}
	result := Capture_Result {
		name          = strings.clone(request.name, data.allocator),
		note          = strings.clone(request.note, data.allocator),
		frame         = session.frame,
		width         = width,
		height        = height,
		target        = renderer.capture_target_name(request.target),
		format        = capture_format_name(request.format),
		target_format = renderer.format_name(format),
		region        = region,
	}
	if request.has_view {
		result.view = strings.clone(renderer.capture_view_name(request.view), data.allocator)
	}
	switch request.format {
	case .Png:
		return backend_capture_png(data, session, request, result, pixels, width, height)
	case .Float:
		return backend_capture_float(data, request, result, pixels, format)
	case .Raw:
		return backend_capture_raw(data, request, result, pixels)
	case .Stats:
		return backend_capture_stats(data, session, request, result, pixels, width, height, format, region)
	case .Profile:
		return backend_capture_profile(data, session, request, result, pixels, width, height, format)
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
	region: Maybe(Capture_Region),
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
		region,
		request.steps,
		request.color_key,
		request.coverage,
		data.allocator,
	)
	if histogram, has_histogram := request.histogram.?; has_histogram {
		bounds := Capture_Region{x = 0, y = 0, w = int(width), h = int(height)}
		if configured, has_region := region.?; has_region {
			bounds = configured
		}
		result.histogram = capture_histogram_build(
			pixels,
			width,
			bounds,
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
	format: vk.Format,
) -> (
	Capture_Result,
	string,
) {
	result := initial
	spec, has_profile := request.profile.?
	if !has_profile {
		return {}, format_error("a profile capture needs a profile")
	}
	source := Capture_Profile_Source{pixels = pixels, width = width, height = height}
	values: []f32
	if request.target != .Color {
		values = renderer.capture_values(pixels, format, data.allocator)
		if values == nil {
			return {}, format_error("cannot convert the %s capture to floats", renderer.format_name(format))
		}
		defer delete(values, data.allocator)
		source = {values = values, width = width, height = height}
	}
	profile, profile_error := capture_profile_build(source, spec, data.allocator)
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
			return {}, write_error
		}
		return written, ""
	}
	return result, ""
}
