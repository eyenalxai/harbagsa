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

make_depth_attachment :: proc(view: vk.ImageView, layout: vk.ImageLayout) -> vk.RenderingAttachmentInfo {
	clear := vk.ClearValue{}
	clear.depthStencil = {depth = 1.0, stencil = 0}
	return {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = view,
		imageLayout = layout,
		loadOp = .CLEAR,
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
	box_count: int,
) {
	vertex_buffer := r.scene.vertex_buffer
	vertex_offset: vk.DeviceSize = 0
	vk.CmdBindVertexBuffers(command_buffer, 0, 1, &vertex_buffer, &vertex_offset)
	vk.CmdBindIndexBuffer(command_buffer, r.scene.index_buffer, 0, .UINT16)

	for index in 0 ..< box_count {
		push := Object_Index{index = u32(index)}
		vk.CmdPushConstants(
			command_buffer,
			layout,
			{.VERTEX, .FRAGMENT},
			0,
			u32(size_of(Object_Index)),
			&push,
		)
		vk.CmdDrawIndexed(command_buffer, r.scene.index_count, 1, 0, 0, 0)
	}
}
