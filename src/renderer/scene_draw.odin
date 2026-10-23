#+vet explicit-allocators
package renderer

import "core:log"

import "src:geometry"
import vk "vendor:vulkan"

record_frame :: proc(
	r: ^Renderer,
	command_buffer: vk.CommandBuffer,
	image_index: u32,
	camera: Camera,
	light_direction: [3]f32,
	boxes: []geometry.Box,
	debug_lines: []geometry.Line,
	hud: HUD_Frame,
) -> bool {
	if int(image_index) >= len(r.swapchain_views) {
		log.errorf("renderer: swapchain image index %d is out of range", image_index)
		return false
	}
	box_count := len(boxes)
	if box_count > MAX_SCENE_BOXES {
		log.errorf("renderer: scene has %d boxes, the limit is %d", box_count, MAX_SCENE_BOXES)
		return false
	}

	if !prepare_overlay(r, debug_lines, hud) {
		log.error("renderer: overlay vertex upload failed")
		return false
	}
	r.shadow.light_view_projection = shadow_light_matrix(light_direction)
	if !update_camera(r, camera, light_direction) {
		return false
	}
	if !write_object_data(r, boxes) {
		return false
	}

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	if !check(vk.BeginCommandBuffer(command_buffer, &begin_info), "vkBeginCommandBuffer") {
		return false
	}

	record_shadow_pass(r, command_buffer, boxes)
	record_scene_pass(r, command_buffer, box_count)
	record_taa_resolve(r, command_buffer, image_index)
	record_overlay_pass(r, command_buffer, image_index)
	record_present_barrier(r, command_buffer, image_index)

	if !check(vk.EndCommandBuffer(command_buffer), "vkEndCommandBuffer") {
		return false
	}
	r.taa.history_read = (r.taa.history_read + 1) % TAA_HISTORY_IMAGES
	r.taa.history_valid = true
	return true
}

write_object_data :: proc(r: ^Renderer, boxes: []geometry.Box) -> bool {
	taa := &r.taa
	data := cast([^]Object_Data)r.scene.object_mapped[r.frame_index]
	if data == nil {
		log.error("renderer: object storage buffer is not mapped")
		return false
	}

	models: [MAX_SCENE_BOXES]Mat4
	for box, index in boxes {
		models[index] = box_model_matrix(box)
		previous := models[index]
		if index < taa.prev_model_count {
			previous = taa.prev_models[index]
		}
		data[index] = Object_Data {
			model = models[index],
			prev_model = previous,
			color = box.color,
		}
	}
	for index in 0 ..< len(boxes) {
		taa.prev_models[index] = models[index]
	}
	taa.prev_model_count = len(boxes)
	return true
}

record_scene_pass :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, box_count: int) {
	taa := &r.taa
	frame := r.frame_index
	color := taa.scene_color[frame]
	velocity := taa.velocity[frame]
	depth := taa.depth[frame]
	extent := taa.targets_extent

	image_barrier(
		command_buffer,
		color.image,
		COLOR_SUBRESOURCE,
		.UNDEFINED,
		.COLOR_ATTACHMENT_OPTIMAL,
		{.TOP_OF_PIPE},
		{.COLOR_ATTACHMENT_OUTPUT},
		{},
		{.COLOR_ATTACHMENT_WRITE},
	)
	image_barrier(
		command_buffer,
		velocity.image,
		COLOR_SUBRESOURCE,
		.UNDEFINED,
		.COLOR_ATTACHMENT_OPTIMAL,
		{.TOP_OF_PIPE},
		{.COLOR_ATTACHMENT_OUTPUT},
		{},
		{.COLOR_ATTACHMENT_WRITE},
	)
	record_depth_write_barrier(command_buffer, depth.image)

	color_clear := vk.ClearValue{}
	color_clear.color.float32 = r.clear_color
	velocity_clear := vk.ClearValue{}
	velocity_clear.color.float32 = {0, 0, CAMERA_FAR, 0}
	attachments := [2]vk.RenderingAttachmentInfo {
		{
			sType = .RENDERING_ATTACHMENT_INFO,
			imageView = color.view,
			imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
			loadOp = .CLEAR,
			storeOp = .STORE,
			clearValue = color_clear,
		},
		{
			sType = .RENDERING_ATTACHMENT_INFO,
			imageView = velocity.view,
			imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
			loadOp = .CLEAR,
			storeOp = .STORE,
			clearValue = velocity_clear,
		},
	}
	depth_attachment := make_depth_attachment(depth.view, .DEPTH_ATTACHMENT_OPTIMAL)
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

	vk.CmdBindPipeline(command_buffer, .GRAPHICS, r.scene.pipeline)
	bind_camera(command_buffer, r.scene.pipeline_layout, r.scene.descriptor_sets[frame])
	draw_boxes_indexed(r, command_buffer, r.scene.pipeline_layout, box_count)

	vk.CmdEndRendering(command_buffer)

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
