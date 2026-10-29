#+vet explicit-allocators
package renderer

import "src:geometry"
import vk "vendor:vulkan"

bind_camera :: proc(
	command_buffer: vk.CommandBuffer,
	layout: vk.PipelineLayout,
	set: vk.DescriptorSet,
) {
	descriptor_set := set
	vk.CmdBindDescriptorSets(command_buffer, .GRAPHICS, layout, 0, 1, &descriptor_set, 0, nil)
}

target_extent_vk :: proc(r: ^Renderer) -> vk.Extent2D {
	return {r.target.config.width, r.target.config.height}
}

set_viewport :: proc(command_buffer: vk.CommandBuffer, width, height: u32) {
	viewport := vk.Viewport {
		width = f32(width),
		height = f32(height),
		minDepth = 0,
		maxDepth = 1,
	}
	scissor := vk.Rect2D{extent = {width, height}}
	vk.CmdSetViewport(command_buffer, 0, 1, &viewport)
	vk.CmdSetScissor(command_buffer, 0, 1, &scissor)
}

make_depth_attachment :: proc(
	view: vk.ImageView,
	layout: vk.ImageLayout,
	load_op: vk.AttachmentLoadOp = .CLEAR,
) -> vk.RenderingAttachmentInfo {
	clear := vk.ClearValue{}
	clear.depthStencil = {depth = 1.0, stencil = 0}
	return {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = view,
		imageLayout = layout,
		loadOp = load_op,
		storeOp = .STORE,
		clearValue = clear,
	}
}

record_depth_write_barrier :: proc(command_buffer: vk.CommandBuffer, image: vk.Image) {
	barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		dstAccessMask = {.DEPTH_STENCIL_ATTACHMENT_WRITE},
		oldLayout = .UNDEFINED,
		newLayout = .DEPTH_ATTACHMENT_OPTIMAL,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = image,
		subresourceRange = DEPTH_SUBRESOURCE,
	}
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
		&barrier,
	)
}

// The prepass writes depth and the color pass reads it in a later render pass.
// The prepass has no fragment shader, so name both depth-test stages: the
// implementation may place its writes in either one.
record_depth_read_barrier :: proc(command_buffer: vk.CommandBuffer, image: vk.Image) {
	image_barrier(
		command_buffer,
		image,
		DEPTH_SUBRESOURCE,
		.DEPTH_ATTACHMENT_OPTIMAL,
		.DEPTH_ATTACHMENT_OPTIMAL,
		{.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS},
		{.EARLY_FRAGMENT_TESTS},
		{.DEPTH_STENCIL_ATTACHMENT_WRITE},
		{.DEPTH_STENCIL_ATTACHMENT_READ},
	)
}

box_model_matrix :: proc(box: geometry.Box) -> Mat4 {
	scale := [3]f32 {
		box.half_extents.x * 2,
		box.half_extents.y * 2,
		box.half_extents.z * 2,
	}
	return mat4_multiply(
		mat4_translation(box.center),
		mat4_multiply(mat4_rotation(box.rotation), mat4_scale(scale)),
	)
}

draw_boxes_indexed :: proc(
	r: ^Renderer,
	command_buffer: vk.CommandBuffer,
	layout: vk.PipelineLayout,
	stages: vk.ShaderStageFlags,
	box_count: int,
	view: Capture_View,
) {
	vertex_buffer := r.scene.vertex_buffer
	vertex_offset: vk.DeviceSize = 0
	vk.CmdBindVertexBuffers(command_buffer, 0, 1, &vertex_buffer, &vertex_offset)
	vk.CmdBindIndexBuffer(command_buffer, r.scene.index_buffer, 0, .UINT16)

	for index in 0 ..< box_count {
		push := Scene_Draw{index = u32(index), view = u32(view)}
		vk.CmdPushConstants(
			command_buffer,
			layout,
			stages,
			0,
			u32(size_of(Scene_Draw)),
			&push,
		)
		vk.CmdDrawIndexed(command_buffer, r.scene.index_count, 1, 0, 0, 0)
	}
}
