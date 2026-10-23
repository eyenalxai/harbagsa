#+vet explicit-allocators
package renderer

import vk "vendor:vulkan"

record_overlay_pass :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, image_index: u32) {
	extent := vk.Extent2D{r.target.config.width, r.target.config.height}
	attachment := vk.RenderingAttachmentInfo {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = r.target.views[image_index],
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp = .LOAD,
		storeOp = .STORE,
	}
	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {extent = extent},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &attachment,
	}
	vk.CmdBeginRendering(command_buffer, &rendering_info)

	viewport := vk.Viewport {
		width = f32(extent.width),
		height = f32(extent.height),
		minDepth = 0,
		maxDepth = 1,
	}
	scissor := vk.Rect2D{extent = extent}
	vk.CmdSetViewport(command_buffer, 0, 1, &viewport)
	vk.CmdSetScissor(command_buffer, 0, 1, &scissor)

	record_overlay(r, command_buffer)

	vk.CmdEndRendering(command_buffer)
}
