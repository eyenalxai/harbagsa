#+vet explicit-allocators
package harness

@(private)
backend_capture_png :: proc(
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
	return backend_capture_write_png(data, session, request, initial, pixels, width, height)
}

// One readback feeds a stats or profile payload and its optional PNG sidecar.
// The sidecar keeps the payload and joins the color delta series like a plain
// PNG capture.
@(private)
backend_capture_write_png :: proc(
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
	if crop, has_crop := request.crop.?; has_crop {
		if !capture_crop_valid(crop, width, height) {
			capture_result_destroy(&result, data.allocator)
			return {}, format_error("capture crop must be inside the target")
		}
		cropped, out_width, out_height, crop_error := capture_crop_pixels(
			pixels,
			width,
			height,
			crop,
			data.allocator,
		)
		if crop_error != "" {
			capture_result_destroy(&result, data.allocator)
			return {}, crop_error
		}
		defer delete(cropped, data.allocator)
		written, write_error := capture_write_png(
			data.frames_dir,
			request.name,
			session.frame,
			out_width,
			out_height,
			cropped,
			data.allocator,
		)
		if write_error != "" {
			capture_result_destroy(&result, data.allocator)
			return {}, write_error
		}
		delete(result.name, data.allocator)
		written.width = width
		written.height = height
		written.written_width = out_width
		written.written_height = out_height
		written.crop = Capture_Crop_Result {
			x = crop.x, y = crop.y, w = crop.w, h = crop.h, scale = crop.scale,
			width = out_width, height = out_height,
		}
		written.view = result.view
		written.target = result.target
		written.format = result.format
		written.target_format = result.target_format
		written.png = result.png
		written.region = result.region
		written.stats = result.stats
		written.profile = result.profile
		written.histogram = result.histogram
		// A cropped image cannot compare with the full baseline, so it neither
		// reads nor writes the previous pixels.
		return written, ""
	}
	written, write_error := capture_write_png(
		data.frames_dir,
		request.name,
		session.frame,
		width,
		height,
		pixels,
		data.allocator,
	)
	if write_error != "" {
		capture_result_destroy(&result, data.allocator)
		return {}, write_error
	}
	delete(result.name, data.allocator)
	written.view = result.view
	written.target = result.target
	written.format = result.format
	written.target_format = result.target_format
	written.png = result.png
	written.region = result.region
	written.stats = result.stats
	written.profile = result.profile
	written.histogram = result.histogram
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
	return written, ""
}
