#+vet explicit-allocators
package renderer

import vk "vendor:vulkan"

record_taa_resolve :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, image_index: u32) {
	taa := &r.taa
	read_index := taa.history_read
	write_index := (read_index + 1) % TAA_HISTORY_IMAGES
	read := taa.history[read_index]
	write := taa.history[write_index]
	extent := vk.Extent2D{r.target.config.width, r.target.config.height}
	target_image := r.target.images[image_index]

	// After the first use the read target rests in SHADER_READ_ONLY_OPTIMAL.
	if taa.history_layouts[read_index] == .UNDEFINED {
		image_barrier(
			command_buffer,
			read.image,
			COLOR_SUBRESOURCE,
			.UNDEFINED,
			.SHADER_READ_ONLY_OPTIMAL,
			{.TOP_OF_PIPE},
			{.FRAGMENT_SHADER},
			{},
			{.SHADER_READ},
		)
	} else {
		image_barrier(
			command_buffer,
			read.image,
			COLOR_SUBRESOURCE,
			.SHADER_READ_ONLY_OPTIMAL,
			.SHADER_READ_ONLY_OPTIMAL,
			{.COLOR_ATTACHMENT_OUTPUT},
			{.FRAGMENT_SHADER},
			{.COLOR_ATTACHMENT_WRITE},
			{.SHADER_READ},
		)
	}

	old_write_layout := taa.history_layouts[write_index]
	if old_write_layout == .UNDEFINED {
		image_barrier(
			command_buffer,
			write.image,
			COLOR_SUBRESOURCE,
			.UNDEFINED,
			.COLOR_ATTACHMENT_OPTIMAL,
			{.TOP_OF_PIPE},
			{.COLOR_ATTACHMENT_OUTPUT},
			{},
			{.COLOR_ATTACHMENT_WRITE},
		)
	} else {
		image_barrier(
			command_buffer,
			write.image,
			COLOR_SUBRESOURCE,
			old_write_layout,
			.COLOR_ATTACHMENT_OPTIMAL,
			{.FRAGMENT_SHADER},
			{.COLOR_ATTACHMENT_OUTPUT},
			{.SHADER_READ},
			{.COLOR_ATTACHMENT_WRITE},
		)
	}

	image_barrier(
		command_buffer,
		target_image,
		COLOR_SUBRESOURCE,
		.UNDEFINED,
		.COLOR_ATTACHMENT_OPTIMAL,
		{.TOP_OF_PIPE},
		{.COLOR_ATTACHMENT_OUTPUT},
		{},
		{.COLOR_ATTACHMENT_WRITE},
	)

	target_clear := vk.ClearValue{}
	target_clear.color.float32 = r.clear_color
	attachments := [2]vk.RenderingAttachmentInfo {
		{
			sType = .RENDERING_ATTACHMENT_INFO,
			imageView = r.target.views[image_index],
			imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
			loadOp = .CLEAR,
			storeOp = .STORE,
			clearValue = target_clear,
		},
		{
			sType = .RENDERING_ATTACHMENT_INFO,
			imageView = write.view,
			imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
			loadOp = .DONT_CARE,
			storeOp = .STORE,
		},
	}
	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {extent = extent},
		layerCount = 1,
		colorAttachmentCount = u32(len(attachments)),
		pColorAttachments = &attachments[0],
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

	vk.CmdBindPipeline(command_buffer, .GRAPHICS, taa.pipeline)
	descriptor_set := taa.descriptor_sets[r.frame_index * TAA_HISTORY_IMAGES + read_index]
	vk.CmdBindDescriptorSets(
		command_buffer,
		.GRAPHICS,
		taa.pipeline_layout,
		0,
		1,
		&descriptor_set,
		0,
		nil,
	)

	weight: f32
	if taa.enabled && taa.history_valid {
		weight = taa_history_weight(taa.converge_frames)
	}
	params := TAA_Params {
		gamma = srgb_gamma(r),
		weight = weight,
	}
	vk.CmdPushConstants(
		command_buffer,
		taa.pipeline_layout,
		{.FRAGMENT},
		0,
		u32(size_of(TAA_Params)),
		&params,
	)
	vk.CmdDraw(command_buffer, 3, 1, 0, 0)
	vk.CmdEndRendering(command_buffer)

	image_barrier(
		command_buffer,
		write.image,
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
		target_image,
		COLOR_SUBRESOURCE,
		.COLOR_ATTACHMENT_OPTIMAL,
		.COLOR_ATTACHMENT_OPTIMAL,
		{.COLOR_ATTACHMENT_OUTPUT},
		{.COLOR_ATTACHMENT_OUTPUT},
		{.COLOR_ATTACHMENT_WRITE},
		{.COLOR_ATTACHMENT_READ, .COLOR_ATTACHMENT_WRITE},
	)

	taa.history_layouts[read_index] = .SHADER_READ_ONLY_OPTIMAL
	taa.history_layouts[write_index] = .SHADER_READ_ONLY_OPTIMAL
}
