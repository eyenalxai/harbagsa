#+vet explicit-allocators
#+vet !unused-procedures // the harness reads captures; the game binary does not
package renderer

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

MAX_CAPTURE_TARGETS :: 5
Capture_Targets :: bit_set[Capture_Target]

Frame_Capture :: struct {
	targets: Capture_Targets,
}

capture_target_count :: proc(capture: Frame_Capture) -> int {
	count := 0
	for _ in capture.targets {
		count += 1
	}
	return count
}

@(private)
capture_slot_stride :: proc(r: ^Renderer) -> vk.DeviceSize {
	return vk.DeviceSize(r.target.config.width) *
	       vk.DeviceSize(r.target.config.height) *
	       vk.DeviceSize(MAX_CAPTURE_TEXEL_BYTES)
}

capture_target_name :: proc(target: Capture_Target) -> string {
	switch target {
	case .Color:
		return "color"
	case .Velocity:
		return "velocity"
	case .History:
		return "history"
	case .Depth:
		return "depth"
	case .Scene_Color:
		return "scene_color"
	}
	return "color"
}

capture_target_parse :: proc(name: string) -> (target: Capture_Target, ok: bool) {
	switch name {
	case "color":
		return .Color, true
	case "velocity":
		return .Velocity, true
	case "history":
		return .History, true
	case "depth":
		return .Depth, true
	case "scene_color":
		return .Scene_Color, true
	}
	return .Color, false
}

Format_Info :: struct {
	name:        string,
	texel_bytes: int,
}

format_info :: proc(format: vk.Format) -> Format_Info {
	#partial switch format {
	case .R8G8B8A8_SRGB:
		return {"R8G8B8A8_SRGB", 4}
	case .B8G8R8A8_SRGB:
		return {"B8G8R8A8_SRGB", 4}
	case .R8G8B8A8_UNORM:
		return {"R8G8B8A8_UNORM", 4}
	case .B8G8R8A8_UNORM:
		return {"B8G8R8A8_UNORM", 4}
	case .R16G16B16A16_SFLOAT:
		return {"R16G16B16A16_SFLOAT", 8}
	case .R32G32B32A32_SFLOAT:
		return {"R32G32B32A32_SFLOAT", 16}
	case .D32_SFLOAT:
		return {"D32_SFLOAT", 4}
	}
	return {"unknown", 0}
}

format_name :: proc(format: vk.Format) -> string {
	return format_info(format).name
}

texel_bytes :: proc(format: vk.Format) -> int {
	return format_info(format).texel_bytes
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
		return r.taa.velocity[r.frame_index].image, VELOCITY_FORMAT, true
	case .History:
		return r.taa.history[r.taa.history_read].image, HISTORY_FORMAT, true
	case .Depth:
		return r.taa.depth[r.frame_index].image, DEPTH_FORMAT, true
	case .Scene_Color:
		return r.taa.scene_color[r.frame_index].image, SCENE_COLOR_FORMAT, true
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
	if r.target.readback.buffer == 0 || r.target.readback.size == 0 {
		return false
	}
	stride := capture_slot_stride(r)
	if vk.DeviceSize(slot) * stride >= r.target.readback.size {
		return false
	}
	image, format, ok := target_image(r, image_index, target)
	if !ok || texel_bytes(format) == 0 {
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
	ok: bool,
) {
	if r.target.readback.mapped == nil || r.target.readback.size == 0 {
		return nil, 0, 0, .UNDEFINED, false
	}
	_, image_format, image_ok := target_image(r, 0, target)
	if !image_ok {
		return nil, 0, 0, .UNDEFINED, false
	}
	format = image_format
	bytes_per_texel := texel_bytes(format)
	if bytes_per_texel == 0 {
		return nil, 0, 0, .UNDEFINED, false
	}
	width = r.target.config.width
	height = r.target.config.height
	required := vk.DeviceSize(width) * vk.DeviceSize(height) * vk.DeviceSize(bytes_per_texel)
	offset := vk.DeviceSize(slot) * capture_slot_stride(r)
	if offset + required > r.target.readback.size {
		return nil, 0, 0, .UNDEFINED, false
	}
	size := int(required)
	source := rawptr(uintptr(r.target.readback.mapped) + uintptr(offset))
	mem.copy(raw_data(r.target.readback.pixels), source, size)
	if target == .Color &&
	   (format == .B8G8R8A8_SRGB || format == .B8G8R8A8_UNORM) {
		for i := 0; i + 3 < size; i += 4 {
			r.target.readback.pixels[i], r.target.readback.pixels[i + 2] =
				r.target.readback.pixels[i + 2], r.target.readback.pixels[i]
		}
	}
	return r.target.readback.pixels[:size], width, height, format, true
}

// Four f32 values per pixel in RGBA order. Depth fills only .x. Color keeps its
// 0..255 channel values. The other formats are linear floats.
capture_values :: proc(bytes: []u8, format: vk.Format, allocator: mem.Allocator) -> []f32 {
	bytes_per_texel := texel_bytes(format)
	if bytes_per_texel == 0 || len(bytes) % bytes_per_texel != 0 {
		return nil
	}
	pixels := len(bytes) / bytes_per_texel
	values := make([]f32, pixels * 4, allocator)
	if format == .R16G16B16A16_SFLOAT {
		halves := cast([^]u16)raw_data(bytes)
		for index in 0 ..< pixels * 4 {
			values[index] = f32(transmute(f16)halves[index])
		}
	} else if format == .R32G32B32A32_SFLOAT {
		floats := cast([^]f32)raw_data(bytes)
		for index in 0 ..< pixels * 4 {
			values[index] = floats[index]
		}
	} else if format == .D32_SFLOAT {
		depths := cast([^]f32)raw_data(bytes)
		for index in 0 ..< pixels {
			values[index * 4] = depths[index]
		}
	} else {
		for index in 0 ..< pixels {
			base := index * 4
			values[index * 4 + 0] = f32(bytes[base + 0])
			values[index * 4 + 1] = f32(bytes[base + 1])
			values[index * 4 + 2] = f32(bytes[base + 2])
			values[index * 4 + 3] = f32(bytes[base + 3])
		}
	}
	return values
}
