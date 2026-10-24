#+vet explicit-allocators
package renderer

import vk "vendor:vulkan"

// The sky draws after the lit pass and writes the same two colour images, so
// the second colour scope needs an explicit dependency. Depth stays in the
// attachment layout the prepass left it in.
record_sky_pass :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer) {
	if !renderer_debug(r).sky {
		return
	}
	extent := vk.Extent2D{r.target.config.width, r.target.config.height}
	frame := r.frame_index
	color := r.taa.scene_color[frame]
	velocity := r.taa.velocity[frame]
	depth := r.taa.depth[frame]

	image_barrier(
		command_buffer,
		color.image,
		COLOR_SUBRESOURCE,
		.COLOR_ATTACHMENT_OPTIMAL,
		.COLOR_ATTACHMENT_OPTIMAL,
		{.COLOR_ATTACHMENT_OUTPUT},
		{.COLOR_ATTACHMENT_OUTPUT},
		{.COLOR_ATTACHMENT_WRITE},
		{.COLOR_ATTACHMENT_READ, .COLOR_ATTACHMENT_WRITE},
	)
	image_barrier(
		command_buffer,
		velocity.image,
		COLOR_SUBRESOURCE,
		.COLOR_ATTACHMENT_OPTIMAL,
		.COLOR_ATTACHMENT_OPTIMAL,
		{.COLOR_ATTACHMENT_OUTPUT},
		{.COLOR_ATTACHMENT_OUTPUT},
		{.COLOR_ATTACHMENT_WRITE},
		{.COLOR_ATTACHMENT_READ, .COLOR_ATTACHMENT_WRITE},
	)

	attachments := [2]vk.RenderingAttachmentInfo {
		{
			sType = .RENDERING_ATTACHMENT_INFO,
			imageView = color.view,
			imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
			loadOp = .LOAD,
			storeOp = .STORE,
		},
		{
			sType = .RENDERING_ATTACHMENT_INFO,
			imageView = velocity.view,
			imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
			loadOp = .LOAD,
			storeOp = .STORE,
		},
	}
	depth_attachment := make_depth_attachment(depth.view, .DEPTH_ATTACHMENT_OPTIMAL, .LOAD)
	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {extent = extent},
		layerCount = 1,
		colorAttachmentCount = u32(len(attachments)),
		pColorAttachments = &attachments[0],
		pDepthAttachment = &depth_attachment,
	}
	vk.CmdBeginRendering(command_buffer, &rendering_info)
	set_viewport(command_buffer, extent.width, extent.height)
	vk.CmdBindPipeline(command_buffer, .GRAPHICS, r.scene.sky_pipeline)
	bind_camera(command_buffer, r.scene.sky_layout, r.scene.descriptor_sets[r.frame_index])
	vk.CmdDraw(command_buffer, 3, 1, 0, 0)
	vk.CmdEndRendering(command_buffer)
}
