#+vet explicit-allocators
package renderer

import "core:log"

import vk "vendor:vulkan"

record_scene :: proc(
	r: ^Renderer,
	command_buffer: vk.CommandBuffer,
	image_index: u32,
	view: Frame_View,
	capture: bool,
) -> bool {
	if int(image_index) >= len(r.target.views) || int(image_index) >= len(r.target.depth) {
		log.errorf("renderer: target image index %d is out of range", image_index)
		return false
	}

	if !prepare_overlay(r, view.debug_lines, view.hud) {
		log.error("renderer: overlay vertex upload failed")
		return false
	}

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	if !check(vk.BeginCommandBuffer(command_buffer, &begin_info), "vkBeginCommandBuffer") {
		return false
	}

	// The shadow matrix feeds the camera uniform, so rebuild it first.
	r.shadow.light_view_projection = shadow_light_matrix(view.light_direction)
	if !update_camera(r, view.camera, view.light_direction) {
		return false
	}

	record_shadow_pass(r, command_buffer, view.boxes)

	to_color := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
		oldLayout = .UNDEFINED,
		newLayout = .COLOR_ATTACHMENT_OPTIMAL,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = r.target.images[image_index],
		subresourceRange = COLOR_SUBRESOURCE,
	}
	vk.CmdPipelineBarrier(
		command_buffer,
		{.TOP_OF_PIPE},
		{.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS},
		{},
		0,
		nil,
		0,
		nil,
		1,
		&to_color,
	)
	record_depth_write_barrier(command_buffer, r.target.depth[image_index].image)

	clear := r.clear_color
	if !r.target.config.is_srgb {
		clear = {srgb_encode(clear.r), srgb_encode(clear.g), srgb_encode(clear.b), clear.a}
	}
	clear_color := vk.ClearValue{}
	clear_color.color.float32 = clear
	color_attachment := vk.RenderingAttachmentInfo {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = r.target.views[image_index],
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .STORE,
		clearValue = clear_color,
	}

	depth_attachment := make_depth_attachment(
		r.target.depth[image_index].view,
		.DEPTH_ATTACHMENT_OPTIMAL,
	)

	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {extent = {r.target.config.width, r.target.config.height}},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &color_attachment,
		pDepthAttachment = &depth_attachment,
	}
	vk.CmdBeginRendering(command_buffer, &rendering_info)

	set_viewport(command_buffer, r.target.config.width, r.target.config.height)

	vk.CmdBindPipeline(command_buffer, .GRAPHICS, r.scene.pipeline)

	bind_camera(command_buffer, r.scene.pipeline_layout, r.scene.descriptor_sets[r.frame_index])

	draw_boxes(r, command_buffer, r.scene.pipeline_layout, view.boxes)

	record_overlay(r, command_buffer)

	vk.CmdEndRendering(command_buffer)

	if capture && !record_capture_copy(r, command_buffer, image_index) {
		return false
	}

	if r.target.kind == .Swapchain {
		src_access: vk.AccessFlags = {.COLOR_ATTACHMENT_WRITE}
		old_layout: vk.ImageLayout = .COLOR_ATTACHMENT_OPTIMAL
		if capture {
			src_access = {.TRANSFER_READ}
			old_layout = .TRANSFER_SRC_OPTIMAL
		}
		to_present := vk.ImageMemoryBarrier {
			sType = .IMAGE_MEMORY_BARRIER,
			srcAccessMask = src_access,
			oldLayout = old_layout,
			newLayout = .PRESENT_SRC_KHR,
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			image = r.target.images[image_index],
			subresourceRange = COLOR_SUBRESOURCE,
		}
		vk.CmdPipelineBarrier(
			command_buffer,
			{.COLOR_ATTACHMENT_OUTPUT, .TRANSFER},
			{.BOTTOM_OF_PIPE},
			{},
			0,
			nil,
			0,
			nil,
			1,
			&to_present,
		)
	}

	return check(vk.EndCommandBuffer(command_buffer), "vkEndCommandBuffer")
}
