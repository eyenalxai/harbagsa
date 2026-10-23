#+vet explicit-allocators
package renderer

import "core:log"

import "src:geometry"
import vk "vendor:vulkan"

record_scene :: proc(
	r: ^Renderer,
	command_buffer: vk.CommandBuffer,
	image_index: u32,
	camera: Camera,
	light_direction: [3]f32,
	boxes: []geometry.Box,
	debug_lines: []geometry.Line,
	hud: HUD_State,
) -> bool {
	if int(image_index) >= len(r.swapchain_views) || int(image_index) >= len(r.scene.depth_views) {
		log.errorf("renderer: swapchain image index %d is out of range", image_index)
		return false
	}

	if !prepare_overlay(r, debug_lines, hud) {
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

	if !update_camera(r, camera, light_direction) {
		return false
	}

	to_color := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
		oldLayout = .UNDEFINED,
		newLayout = .COLOR_ATTACHMENT_OPTIMAL,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = r.swapchain_images[image_index],
		subresourceRange = COLOR_SUBRESOURCE,
	}
	to_depth := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		dstAccessMask = {.DEPTH_STENCIL_ATTACHMENT_WRITE},
		oldLayout = .UNDEFINED,
		newLayout = .DEPTH_ATTACHMENT_OPTIMAL,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = r.scene.depth_images[image_index],
		subresourceRange = DEPTH_SUBRESOURCE,
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
	vk.CmdPipelineBarrier(
		command_buffer,
		{.TOP_OF_PIPE},
		{.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS},
		{},
		0,
		nil,
		0,
		nil,
		1,
		&to_depth,
	)

	clear := r.clear_color
	if !r.swapchain_is_srgb {
		clear = {srgb_encode(clear.r), srgb_encode(clear.g), srgb_encode(clear.b), clear.a}
	}
	clear_color := vk.ClearValue{}
	clear_color.color.float32 = clear
	color_attachment := vk.RenderingAttachmentInfo {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = r.swapchain_views[image_index],
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .STORE,
		clearValue = clear_color,
	}

	clear_depth := vk.ClearValue{}
	clear_depth.depthStencil = {depth = 1.0, stencil = 0}
	depth_attachment := vk.RenderingAttachmentInfo {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = r.scene.depth_views[image_index],
		imageLayout = .DEPTH_ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .STORE,
		clearValue = clear_depth,
	}

	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {extent = r.swapchain_extent},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &color_attachment,
		pDepthAttachment = &depth_attachment,
	}
	vk.CmdBeginRendering(command_buffer, &rendering_info)

	viewport := vk.Viewport {
		x = 0,
		y = 0,
		width = f32(r.swapchain_extent.width),
		height = f32(r.swapchain_extent.height),
		minDepth = 0,
		maxDepth = 1,
	}
	scissor := vk.Rect2D{extent = r.swapchain_extent}
	vk.CmdSetViewport(command_buffer, 0, 1, &viewport)
	vk.CmdSetScissor(command_buffer, 0, 1, &scissor)

	vk.CmdBindPipeline(command_buffer, .GRAPHICS, r.scene.pipeline)

	descriptor_set := r.scene.descriptor_sets[r.frame_index]
	vk.CmdBindDescriptorSets(command_buffer, .GRAPHICS, r.scene.pipeline_layout, 0, 1, &descriptor_set, 0, nil)

	vertex_buffer := r.scene.vertex_buffer
	vertex_offset: vk.DeviceSize = 0
	vk.CmdBindVertexBuffers(command_buffer, 0, 1, &vertex_buffer, &vertex_offset)
	vk.CmdBindIndexBuffer(command_buffer, r.scene.index_buffer, 0, .UINT16)

	for box in boxes {
		scale := [3]f32 {
			box.half_extents.x * 2,
			box.half_extents.y * 2,
			box.half_extents.z * 2,
		}
		push := Push_Constants {
			model = mat4_multiply(
				mat4_translation(box.center),
				mat4_multiply(mat4_rotation(box.rotation), mat4_scale(scale)),
			),
			color = box.color,
		}
		vk.CmdPushConstants(
			command_buffer,
			r.scene.pipeline_layout,
			{.VERTEX},
			0,
			u32(size_of(Push_Constants)),
			&push,
		)
		vk.CmdDrawIndexed(command_buffer, r.scene.index_count, 1, 0, 0, 0)
	}

	record_overlay(r, command_buffer)

	vk.CmdEndRendering(command_buffer)

	to_present := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		srcAccessMask = {.COLOR_ATTACHMENT_WRITE},
		oldLayout = .COLOR_ATTACHMENT_OPTIMAL,
		newLayout = .PRESENT_SRC_KHR,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = r.swapchain_images[image_index],
		subresourceRange = COLOR_SUBRESOURCE,
	}
	vk.CmdPipelineBarrier(
		command_buffer,
		{.COLOR_ATTACHMENT_OUTPUT},
		{.BOTTOM_OF_PIPE},
		{},
		0,
		nil,
		0,
		nil,
		1,
		&to_present,
	)

	return check(vk.EndCommandBuffer(command_buffer), "vkEndCommandBuffer")
}
