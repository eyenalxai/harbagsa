#+vet explicit-allocators
package renderer

import vk "vendor:vulkan"

record_taa_resolve :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, image_index: u32) {
	taa := &r.taa
	read_index := taa.history_read
	write_index := (read_index + 1) % TAA_HISTORY_IMAGES
	read := taa.history[read_index]
	write := taa.history[write_index]
	read_count := taa.counts[read_index]
	write_count := taa.counts[write_index]
	extent := vk.Extent2D{r.target.config.width, r.target.config.height}
	target_image := r.target.images[image_index]

	taa_read_barrier(command_buffer, read.image, &taa.history_layouts[read_index])
	taa_write_barrier(command_buffer, write.image, &taa.history_layouts[write_index])
	taa_read_barrier(command_buffer, read_count.image, &taa.count_layouts[read_index])
	taa_write_barrier(command_buffer, write_count.image, &taa.count_layouts[write_index])

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
	attachments := [3]vk.RenderingAttachmentInfo {
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
		{
			sType = .RENDERING_ATTACHMENT_INFO,
			imageView = write_count.view,
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

	params := TAA_Params {
		gamma          = srgb_gamma(r),
		history_valid  = taa.enabled && taa.history_valid ? 1 : 0,
		max_samples    = TAA_MAX_SAMPLES,
		history_weight = -1,
		clamp_enabled  = 1,
		force_trust    = 0,
	}
	if taa.debug.active {
		params.history_weight = taa.debug.history_weight
		params.clamp_enabled = taa.debug.clamp ? 1 : 0
		params.force_trust = taa.debug.force_depth_trust ? 1 : 0
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

	taa_finish_write(command_buffer, write.image, &taa.history_layouts[write_index])
	taa_finish_write(command_buffer, write_count.image, &taa.count_layouts[write_index])
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
}

// The read target was written by the previous resolve and already rests in
// SHADER_READ_ONLY_OPTIMAL.
@(private)
taa_read_barrier :: proc(command_buffer: vk.CommandBuffer, image: vk.Image, layout: ^vk.ImageLayout) {
	if layout^ == .UNDEFINED {
		image_barrier(
			command_buffer,
			image,
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
			image,
			COLOR_SUBRESOURCE,
			.SHADER_READ_ONLY_OPTIMAL,
			.SHADER_READ_ONLY_OPTIMAL,
			{.COLOR_ATTACHMENT_OUTPUT},
			{.FRAGMENT_SHADER},
			{.COLOR_ATTACHMENT_WRITE},
			{.SHADER_READ},
		)
	}
	layout^ = .SHADER_READ_ONLY_OPTIMAL
}

@(private)
taa_write_barrier :: proc(command_buffer: vk.CommandBuffer, image: vk.Image, layout: ^vk.ImageLayout) {
	if layout^ == .UNDEFINED {
		image_barrier(
			command_buffer,
			image,
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
			image,
			COLOR_SUBRESOURCE,
			.SHADER_READ_ONLY_OPTIMAL,
			.COLOR_ATTACHMENT_OPTIMAL,
			{.FRAGMENT_SHADER},
			{.COLOR_ATTACHMENT_OUTPUT},
			{.SHADER_READ},
			{.COLOR_ATTACHMENT_WRITE},
		)
	}
	layout^ = .COLOR_ATTACHMENT_OPTIMAL
}

@(private)
taa_finish_write :: proc(command_buffer: vk.CommandBuffer, image: vk.Image, layout: ^vk.ImageLayout) {
	image_barrier(
		command_buffer,
		image,
		COLOR_SUBRESOURCE,
		.COLOR_ATTACHMENT_OPTIMAL,
		.SHADER_READ_ONLY_OPTIMAL,
		{.COLOR_ATTACHMENT_OUTPUT},
		{.FRAGMENT_SHADER},
		{.COLOR_ATTACHMENT_WRITE},
		{.SHADER_READ},
	)
	layout^ = .SHADER_READ_ONLY_OPTIMAL
}
