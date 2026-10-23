#+vet explicit-allocators
package renderer

import vk "vendor:vulkan"

record_overlay_pass :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, image_index: u32) {
	attachment := vk.RenderingAttachmentInfo {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = r.swapchain_views[image_index],
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp = .LOAD,
		storeOp = .STORE,
	}
	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {extent = r.swapchain_extent},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &attachment,
	}
	vk.CmdBeginRendering(command_buffer, &rendering_info)

	viewport := vk.Viewport {
		width = f32(r.swapchain_extent.width),
		height = f32(r.swapchain_extent.height),
		minDepth = 0,
		maxDepth = 1,
	}
	scissor := vk.Rect2D{extent = r.swapchain_extent}
	vk.CmdSetViewport(command_buffer, 0, 1, &viewport)
	vk.CmdSetScissor(command_buffer, 0, 1, &scissor)

	record_overlay(r, command_buffer)

	vk.CmdEndRendering(command_buffer)
}

record_present_barrier :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, image_index: u32) {
	image_barrier(
		command_buffer,
		r.swapchain_images[image_index],
		COLOR_SUBRESOURCE,
		.COLOR_ATTACHMENT_OPTIMAL,
		.PRESENT_SRC_KHR,
		{.COLOR_ATTACHMENT_OUTPUT},
		{.BOTTOM_OF_PIPE},
		{.COLOR_ATTACHMENT_WRITE},
		{},
	)
}
