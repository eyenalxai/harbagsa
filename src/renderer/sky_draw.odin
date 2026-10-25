#+vet explicit-allocators
package renderer

import vk "vendor:vulkan"

// The sky draws after the lit pass and writes the same two colour images, so
// the second colour scope needs an explicit dependency. Depth stays in the
// attachment layout the prepass left it in.
sky_barriers :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, pass: ^Pass) {
	frame := r.frame_index
	color := r.taa.scene_color[frame]
	velocity := r.taa.velocity[frame]

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
}
