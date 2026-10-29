#+vet explicit-allocators
package renderer

import "core:log"

import "src:geometry"
import vk "vendor:vulkan"

// A term view is one extra lit pass at the frame's camera and jitter, resolved
// into its own image. The resolve binds no history output, so it cannot advance
// the temporal state the beauty frame is building.
record_scene_view :: proc(
	r: ^Renderer,
	command_buffer: vk.CommandBuffer,
	capture: Frame_Capture,
	view: Capture_View,
	image_index: u32,
	boxes: []geometry.Box,
) -> bool {
	scene := Pass {
		name        = .Scene,
		image_index = image_index,
		view        = view,
		boxes       = boxes,
	}
	build_scene_pass(r, &scene, view)
	scene.pipeline = r.scene.view_pipeline
	scene.layout = r.scene.view_layout
	record_pass(r, command_buffer, &scene)

	resolve := Pass {
		name  = .Taa,
		view  = view,
	}
	build_view_resolve_pass(r, &resolve)
	record_pass(r, command_buffer, &resolve)

	slot := capture_slot(capture, .Color, view)
	return record_view_copy(r, command_buffer, view, slot)
}

@(private)
build_view_resolve_pass :: proc(r: ^Renderer, pass: ^Pass) {
	extent := target_extent_vk(r)
	image := r.view_targets.images[pass.view]
	clear := vk.ClearValue{}
	clear.color.float32 = r.clear_color
	pass.attachments[0] = {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = image.view,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .STORE,
		clearValue = clear,
	}
	pass.rendering = {
		sType = .RENDERING_INFO,
		renderArea = {extent = extent},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &pass.attachments[0],
	}
	pass.barriers = view_resolve_barriers
	pass.pipeline = r.taa.view_pipeline
	pass.layout = r.taa.view_pipeline_layout
	pass.has_rendering = true
	pass.draw = view_resolve_draw
}

@(private)
view_resolve_barriers :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, pass: ^Pass) {
	frame := r.frame_index
	color := r.frame_targets.scene_color[frame]
	velocity := r.frame_targets.velocity[frame]
	image_barrier(
		command_buffer,
		color.image,
		COLOR_SUBRESOURCE,
		.COLOR_ATTACHMENT_OPTIMAL,
		.SHADER_READ_ONLY_OPTIMAL,
		{.COLOR_ATTACHMENT_OUTPUT},
		{.FRAGMENT_SHADER},
		{.COLOR_ATTACHMENT_WRITE},
		{.SHADER_READ},
	)
	image_barrier(
		command_buffer,
		velocity.image,
		COLOR_SUBRESOURCE,
		.COLOR_ATTACHMENT_OPTIMAL,
		.SHADER_READ_ONLY_OPTIMAL,
		{.COLOR_ATTACHMENT_OUTPUT},
		{.FRAGMENT_SHADER},
		{.COLOR_ATTACHMENT_WRITE},
		{.SHADER_READ},
	)
	image_barrier(
		command_buffer,
		r.view_targets.images[pass.view].image,
		COLOR_SUBRESOURCE,
		.UNDEFINED,
		.COLOR_ATTACHMENT_OPTIMAL,
		{.TOP_OF_PIPE},
		{.COLOR_ATTACHMENT_OUTPUT},
		{},
		{.COLOR_ATTACHMENT_WRITE},
	)
}

@(private)
view_resolve_draw :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, pass: ^Pass) {
	descriptor_set := r.taa.descriptor_sets[r.frame_index * TAA_HISTORY_IMAGES + r.taa.history_read]
	vk.CmdBindDescriptorSets(
		command_buffer,
		.GRAPHICS,
		pass.layout,
		0,
		1,
		&descriptor_set,
		0,
		nil,
	)
	params := TAA_Params {
		gamma          = srgb_gamma(r),
		history_valid  = 0,
		max_samples    = TAA_MAX_SAMPLES,
		history_weight = -1,
		clamp_enabled  = 1,
		force_trust    = 0,
	}
	vk.CmdPushConstants(
		command_buffer,
		pass.layout,
		{.FRAGMENT},
		0,
		u32(size_of(TAA_Params)),
		&params,
	)
	vk.CmdDraw(command_buffer, 3, 1, 0, 0)
}

@(private)
record_view_copy :: proc(
	r: ^Renderer,
	command_buffer: vk.CommandBuffer,
	view: Capture_View,
	slot: int,
) -> bool {
	name := capture_view_name(view)
	if slot < 0 {
		log.errorf("renderer: view %s has no readback slot", name)
		return false
	}
	if r.target.readback.buffer == 0 || r.target.readback.size == 0 {
		log.errorf("renderer: capture readback is not allocated for view %s", name)
		return false
	}
	stride := capture_slot_stride(r)
	if vk.DeviceSize(slot) * stride >= r.target.readback.size {
		log.errorf(
			"renderer: capture slot %d for view %s is past the %d byte readback",
			slot,
			name,
			r.target.readback.size,
		)
		return false
	}
	image := r.view_targets.images[view]
	image_barrier(
		command_buffer,
		image.image,
		COLOR_SUBRESOURCE,
		.COLOR_ATTACHMENT_OPTIMAL,
		.TRANSFER_SRC_OPTIMAL,
		{.COLOR_ATTACHMENT_OUTPUT},
		{.TRANSFER},
		{.COLOR_ATTACHMENT_WRITE},
		{.TRANSFER_READ},
	)
	region := vk.BufferImageCopy {
		bufferOffset = vk.DeviceSize(slot) * stride,
		bufferRowLength = 0,
		bufferImageHeight = 0,
		imageSubresource = {
			aspectMask = COLOR_SUBRESOURCE.aspectMask,
			mipLevel = 0,
			baseArrayLayer = 0,
			layerCount = 1,
		},
		imageOffset = {0, 0, 0},
		imageExtent = {r.target.config.width, r.target.config.height, 1},
	}
	vk.CmdCopyImageToBuffer(
		command_buffer,
		image.image,
		.TRANSFER_SRC_OPTIMAL,
		r.target.readback.buffer,
		1,
		&region,
	)
	return true
}
