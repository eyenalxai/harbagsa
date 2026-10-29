#+vet explicit-allocators
#+vet !unused-procedures // the harness reads captures; the game binary does not
package renderer

import "core:fmt"
import "core:log"
import "core:mem"

import vk "vendor:vulkan"

MAX_CAPTURE_TEXEL_BYTES :: 16

Capture_Target :: enum {
	Color,
	Velocity,
	History,
	Depth,
	Scene_Color,
}

Capture_Targets :: bit_set[Capture_Target]

@(private)
capture_slot_stride :: proc(r: ^Renderer) -> vk.DeviceSize {
	return vk.DeviceSize(r.target.config.width) *
	       vk.DeviceSize(r.target.config.height) *
	       vk.DeviceSize(MAX_CAPTURE_TEXEL_BYTES)
}

@(private)
target_image :: proc(r: ^Renderer, image_index: u32, target: Capture_Target) -> (image: vk.Image, format: vk.Format, ok: bool) {
	switch target {
	case .Color:
		if int(image_index) >= len(r.target.images) {
			return 0, .UNDEFINED, false
		}
		return r.target.images[image_index], r.target.config.format, true
	case .Velocity:
		return r.frame_targets.velocity[r.frame_index].image, VELOCITY_FORMAT, true
	case .History:
		return r.taa.history[r.taa.history_read].image, HISTORY_FORMAT, true
	case .Depth:
		return r.frame_targets.depth[r.frame_index].image, DEPTH_FORMAT, true
	case .Scene_Color:
		return r.frame_targets.scene_color[r.frame_index].image, SCENE_COLOR_FORMAT, true
	}
	return 0, .UNDEFINED, false
}

// The color image rests in the attachment layout until the next frame discards
// it. The TAA images are sampled by the resolve. The history image returns to
// the sampler layout because the next resolve reads it.
record_capture_copy :: proc(
	r: ^Renderer,
	command_buffer: vk.CommandBuffer,
	image_index: u32,
	target: Capture_Target,
	slot: int,
) -> bool {
	name := capture_target_name(target)
	if r.target.readback.buffer == 0 || r.target.readback.size == 0 {
		log.errorf("renderer: capture readback is not allocated for %s slot %d", name, slot)
		return false
	}
	stride := capture_slot_stride(r)
	if vk.DeviceSize(slot) * stride >= r.target.readback.size {
		log.errorf(
			"renderer: capture slot %d for %s is past the %d byte readback",
			slot,
			name,
			r.target.readback.size,
		)
		return false
	}
	image, format, ok := target_image(r, image_index, target)
	if !ok || texel_bytes(format) == 0 {
		log.errorf("renderer: capture target %s slot %d has no readable image", name, slot)
		return false
	}

	subresource := COLOR_SUBRESOURCE
	old_layout := vk.ImageLayout.SHADER_READ_ONLY_OPTIMAL
	src_stage := vk.PipelineStageFlags{.FRAGMENT_SHADER}
	src_access := vk.AccessFlags{.SHADER_READ}
	switch target {
	case .Color:
		old_layout = .COLOR_ATTACHMENT_OPTIMAL
		src_stage = {.COLOR_ATTACHMENT_OUTPUT}
		src_access = {.COLOR_ATTACHMENT_WRITE}
	case .Depth:
		subresource = DEPTH_SUBRESOURCE
		old_layout = .DEPTH_ATTACHMENT_OPTIMAL
		src_stage = {.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS}
		src_access = {.DEPTH_STENCIL_ATTACHMENT_WRITE}
	case .Velocity, .History, .Scene_Color:
	}

	image_barrier(
		command_buffer,
		image,
		subresource,
		old_layout,
		.TRANSFER_SRC_OPTIMAL,
		src_stage,
		{.TRANSFER},
		src_access,
		{.TRANSFER_READ},
	)

	region := vk.BufferImageCopy {
		bufferOffset = vk.DeviceSize(slot) * stride,
		bufferRowLength = 0,
		bufferImageHeight = 0,
		imageSubresource = {
			aspectMask = subresource.aspectMask,
			mipLevel = 0,
			baseArrayLayer = 0,
			layerCount = 1,
		},
		imageOffset = {0, 0, 0},
		imageExtent = {r.target.config.width, r.target.config.height, 1},
	}
	vk.CmdCopyImageToBuffer(
		command_buffer,
		image,
		.TRANSFER_SRC_OPTIMAL,
		r.target.readback.buffer,
		1,
		&region,
	)

	if target == .History {
		image_barrier(
			command_buffer,
			image,
			subresource,
			.TRANSFER_SRC_OPTIMAL,
			.SHADER_READ_ONLY_OPTIMAL,
			{.TRANSFER},
			{.FRAGMENT_SHADER},
			{.TRANSFER_READ},
			{.SHADER_READ},
		)
	}
	if target == .Color {
		// The present pass always sees the target in the colour layout, so the
		// capture copy is the only place that owns this transition back.
		image_barrier(
			command_buffer,
			image,
			subresource,
			.TRANSFER_SRC_OPTIMAL,
			.COLOR_ATTACHMENT_OPTIMAL,
			{.TRANSFER},
			{.COLOR_ATTACHMENT_OUTPUT},
			{.TRANSFER_READ},
			{.COLOR_ATTACHMENT_WRITE},
		)
	}
	return true
}

read_capture_target :: proc(
	r: ^Renderer,
	target: Capture_Target,
	slot := 0,
) -> (
	pixels: []u8,
	width, height: u32,
	format: vk.Format,
	error: string,
) {
	name := capture_target_name(target)
	_, image_format, image_ok := target_image(r, 0, target)
	if !image_ok {
		return nil, 0, 0, .UNDEFINED, fmt.aprintf(
			"capture target %s has no image",
			name,
			allocator = context.allocator,
		)
	}
	return read_capture_bytes(r, image_format, name, slot)
}

// A term view owns an image in the target color format, so the readback and the
// channel swap are the ones the color target already uses.
read_capture_view :: proc(
	r: ^Renderer,
	view: Capture_View,
	slot := 0,
) -> (
	pixels: []u8,
	width, height: u32,
	format: vk.Format,
	error: string,
) {
	return read_capture_bytes(r, r.target.config.format, capture_view_name(view), slot)
}

@(private)
read_capture_bytes :: proc(
	r: ^Renderer,
	image_format: vk.Format,
	name: string,
	slot: int,
) -> (
	pixels: []u8,
	width, height: u32,
	format: vk.Format,
	error: string,
) {
	if r.target.readback.mapped == nil || r.target.readback.size == 0 {
		return nil, 0, 0, .UNDEFINED, "capture readback is not allocated; request a capture first"
	}
	format = image_format
	bytes_per_texel := texel_bytes(format)
	if bytes_per_texel == 0 {
		return nil, 0, 0, .UNDEFINED, fmt.aprintf(
			"capture target %s has an unknown format",
			name,
			allocator = context.allocator,
		)
	}
	width = r.target.config.width
	height = r.target.config.height
	required := vk.DeviceSize(width) * vk.DeviceSize(height) * vk.DeviceSize(bytes_per_texel)
	offset := vk.DeviceSize(slot) * capture_slot_stride(r)
	if offset + required > r.target.readback.size {
		return nil, 0, 0, .UNDEFINED, fmt.aprintf(
			"capture %s (%s) at %dx%d needs %d bytes, the readback holds %d",
			name,
			format_name(format),
			width,
			height,
			required,
			r.target.readback.size,
			allocator = context.allocator,
		)
	}
	size := int(required)
	source := rawptr(uintptr(r.target.readback.mapped) + uintptr(offset))
	mem.copy(raw_data(r.target.readback.pixels), source, size)
	if format == .B8G8R8A8_SRGB || format == .B8G8R8A8_UNORM {
		for i := 0; i + 3 < size; i += 4 {
			r.target.readback.pixels[i], r.target.readback.pixels[i + 2] =
				r.target.readback.pixels[i + 2], r.target.readback.pixels[i]
		}
	}
	return r.target.readback.pixels[:size], width, height, format, ""
}

// Four f32 values per pixel in RGBA order. Depth fills only .x. Color keeps its
// 0..255 channel values. The other formats are linear floats.
capture_values :: proc(bytes: []u8, format: vk.Format, allocator: mem.Allocator) -> []f32 {
	info := format_info(format)
	if info.texel_bytes == 0 || len(bytes) % info.texel_bytes != 0 {
		return nil
	}
	pixels := len(bytes) / info.texel_bytes
	values := make([]f32, pixels * 4, allocator)
	switch info.decode {
	case .Rgba16f:
		halves := cast([^]u16)raw_data(bytes)
		for index in 0 ..< pixels * 4 {
			values[index] = f32(transmute(f16)halves[index])
		}
	case .Rgba32f:
		floats := cast([^]f32)raw_data(bytes)
		for index in 0 ..< pixels * 4 {
			values[index] = floats[index]
		}
	case .Depth32f:
		depths := cast([^]f32)raw_data(bytes)
		for index in 0 ..< pixels {
			values[index * 4] = depths[index]
		}
	case .Rgba8:
		for index in 0 ..< pixels {
			base := index * 4
			values[index * 4 + 0] = f32(bytes[base + 0])
			values[index * 4 + 1] = f32(bytes[base + 1])
			values[index * 4 + 2] = f32(bytes[base + 2])
			values[index * 4 + 3] = f32(bytes[base + 3])
		}
	case .Unknown:
		return nil
	}
	return values
}
