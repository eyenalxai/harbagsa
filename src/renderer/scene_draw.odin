#+vet explicit-allocators
package renderer

import "core:log"

import "src:geometry"
import vk "vendor:vulkan"

record_scene :: proc(
	r: ^Renderer,
	command_buffer: vk.CommandBuffer,
	image_index: u32,
	view: Frame_View,
	capture: Frame_Capture,
) -> bool {
	r.frame_count += 1
	if int(image_index) >= len(r.target.views) {
		log.errorf("renderer: target image index %d is out of range", image_index)
		return false
	}
	box_count := len(view.boxes)
	if box_count > MAX_SCENE_BOXES {
		log.errorf("renderer: scene has %d boxes, the limit is %d", box_count, MAX_SCENE_BOXES)
		return false
	}

	if !prepare_overlay(r, view.debug_lines, view.hud) {
		log.error("renderer: overlay vertex upload failed")
		return false
	}
	if r.taa.has_prev_models && box_count != r.taa.prev_model_count {
		reset_history(r, .Scene_Change)
	}
	if !update_camera(r, view.camera, view.light_direction) {
		return false
	}
	r.render_digest = render_digest(
		Render_Digest_Input {
			camera = view.camera,
			light_direction = view.light_direction,
			boxes = view.boxes,
			jitter = r.taa.current_jitter,
			shadow_phase = r.taa.shadow_phase,
			view_flags = view.view_flags,
		},
	)
	r.has_render_digest = true
	if !write_object_data(r, view.boxes) {
		return false
	}

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	if !check(vk.BeginCommandBuffer(command_buffer, &begin_info), "vkBeginCommandBuffer") {
		return false
	}

	reset_timing(r, command_buffer)
	write_timing(r, command_buffer, .Start)
	record_acceleration(r, command_buffer, view.boxes)
	write_timing(r, command_buffer, .After_Tlas)
	record_scene_pass(r, command_buffer, box_count)
	write_timing(r, command_buffer, .After_Scene)
	record_taa_resolve(r, command_buffer, image_index)
	write_timing(r, command_buffer, .After_Taa)
	record_overlay_pass(r, command_buffer, image_index)
	write_timing(r, command_buffer, .After_Overlay)
	if capture.enabled && !record_capture_copy(r, command_buffer, image_index, capture.target) {
		return false
	}
	if r.target.kind == .Swapchain {
		record_present_barrier(r, command_buffer, image_index, capture.enabled)
	}

	if !check(vk.EndCommandBuffer(command_buffer), "vkEndCommandBuffer") {
		return false
	}

	r.taa.applied_history_read = r.taa.history_read
	r.taa.history_read = (r.taa.history_read + 1) % TAA_HISTORY_IMAGES
	r.taa.history_valid = true
	r.taa.convergence_frames = min(r.taa.convergence_frames + 1, TAA_MAX_SAMPLES)
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
	taa.has_prev_models = true
	return true
}

record_scene_pass :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, box_count: int) {
	taa := &r.taa
	frame := r.frame_index
	color := taa.scene_color[frame]
	velocity := taa.velocity[frame]
	depth := taa.depth[frame]

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

	record_depth_prepass(r, command_buffer, box_count)
	record_depth_read_barrier(command_buffer, depth.image)
	record_color_pass(r, command_buffer, box_count)

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

// Writing depth first means the lighting pass traces the sun rays for the
// nearest surface at each pixel, even when several boxes overlap on screen.
@(private)
record_depth_prepass :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, box_count: int) {
	extent := vk.Extent2D{r.target.config.width, r.target.config.height}
	depth := r.taa.depth[r.frame_index]
	depth_attachment := make_depth_attachment(depth.view, .DEPTH_ATTACHMENT_OPTIMAL)
	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {extent = extent},
		layerCount = 1,
		pDepthAttachment = &depth_attachment,
	}
	record_box_scope(
		r,
		command_buffer,
		&rendering_info,
		r.scene.depth_pipeline,
		r.scene.depth_layout,
		{.VERTEX},
		box_count,
	)
}

@(private)
record_color_pass :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, box_count: int) {
	extent := vk.Extent2D{r.target.config.width, r.target.config.height}
	frame := r.frame_index
	color := r.taa.scene_color[frame]
	velocity := r.taa.velocity[frame]
	depth := r.taa.depth[frame]

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
	depth_attachment := make_depth_attachment(depth.view, .DEPTH_ATTACHMENT_OPTIMAL, .LOAD)
	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {extent = extent},
		layerCount = 1,
		colorAttachmentCount = u32(len(attachments)),
		pColorAttachments = &attachments[0],
		pDepthAttachment = &depth_attachment,
	}
	record_box_scope(
		r,
		command_buffer,
		&rendering_info,
		r.scene.pipeline,
		r.scene.pipeline_layout,
		{.VERTEX, .FRAGMENT},
		box_count,
	)
}

@(private)
record_box_scope :: proc(
	r: ^Renderer,
	command_buffer: vk.CommandBuffer,
	rendering_info: ^vk.RenderingInfo,
	pipeline: vk.Pipeline,
	layout: vk.PipelineLayout,
	stages: vk.ShaderStageFlags,
	box_count: int,
) {
	extent := rendering_info.renderArea.extent
	vk.CmdBeginRendering(command_buffer, rendering_info)
	set_viewport(command_buffer, extent.width, extent.height)
	vk.CmdBindPipeline(command_buffer, .GRAPHICS, pipeline)
	bind_camera(command_buffer, layout, r.scene.descriptor_sets[r.frame_index])
	draw_boxes_indexed(r, command_buffer, layout, stages, box_count)
	vk.CmdEndRendering(command_buffer)
}
