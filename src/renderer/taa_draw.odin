#+vet explicit-allocators
package renderer

import vk "vendor:vulkan"

taa_barriers :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, pass: ^Pass) {
	taa := &r.taa
	read_index := taa.history_read
	write_index := (read_index + 1) % TAA_HISTORY_IMAGES

	record_scene_read_barriers(r, command_buffer)
	taa_read_barrier(command_buffer, taa.history[read_index].image, &taa.history_layouts[read_index])
	taa_write_barrier(command_buffer, taa.history[write_index].image, &taa.history_layouts[write_index])
	taa_read_barrier(command_buffer, taa.counts[read_index].image, &taa.count_layouts[read_index])
	taa_write_barrier(command_buffer, taa.counts[write_index].image, &taa.count_layouts[write_index])

	image_barrier(
		command_buffer,
		r.target.images[pass.image_index],
		COLOR_SUBRESOURCE,
		.UNDEFINED,
		.COLOR_ATTACHMENT_OPTIMAL,
		{.TOP_OF_PIPE},
		{.COLOR_ATTACHMENT_OUTPUT},
		{},
		{.COLOR_ATTACHMENT_WRITE},
	)
}

taa_draw :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, pass: ^Pass) {
	taa := &r.taa
	read_index := taa.history_read
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
	if r.debug.active {
		params.history_weight = r.debug.history_weight
		params.clamp_enabled = r.debug.clamp ? 1 : 0
		params.force_trust = r.debug.force_depth_trust ? 1 : 0
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
}

taa_after :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, pass: ^Pass) {
	taa := &r.taa
	read_index := taa.history_read
	write_index := (read_index + 1) % TAA_HISTORY_IMAGES
	taa_finish_write(command_buffer, taa.history[write_index].image, &taa.history_layouts[write_index])
	taa_finish_write(command_buffer, taa.counts[write_index].image, &taa.count_layouts[write_index])
	image_barrier(
		command_buffer,
		r.target.images[pass.image_index],
		COLOR_SUBRESOURCE,
		.COLOR_ATTACHMENT_OPTIMAL,
		.COLOR_ATTACHMENT_OPTIMAL,
		{.COLOR_ATTACHMENT_OUTPUT},
		{.COLOR_ATTACHMENT_OUTPUT},
		{.COLOR_ATTACHMENT_WRITE},
		{.COLOR_ATTACHMENT_READ, .COLOR_ATTACHMENT_WRITE},
	)
}

@(private)
record_scene_read_barriers :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer) {
	color := r.frame_targets.scene_color[r.frame_index]
	velocity := r.frame_targets.velocity[r.frame_index]

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
