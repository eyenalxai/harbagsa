#+vet explicit-allocators
package renderer

import "core:log"

import "src:geometry"
import vk "vendor:vulkan"

// A term view is one extra lit pass at the frame's camera and jitter, resolved
// into its own image. The resolve binds no history output, so it cannot advance
// the temporal state the beauty frame is building.
record_scene_view :: proc(
	r: ^Renderer,
	command_buffer: vk.CommandBuffer,
	capture: Frame_Capture,
	view: Capture_View,
	image_index: u32,
	boxes: []geometry.Box,
) -> bool {
	scene := Pass {
		name        = .Scene,
		image_index = image_index,
		view        = view,
		boxes       = boxes,
	}
	build_scene_pass(r, &scene, view)
	scene.barriers = view_scene_barriers
	scene.pipeline = r.scene.view_pipeline
	scene.layout = r.scene.view_layout
	record_pass(r, command_buffer, &scene)

	resolve := Pass {
		name = .Taa,
		view = view,
	}
	build_view_resolve_pass(r, &resolve)
	record_pass(r, command_buffer, &resolve)

	return record_view_copy(r, command_buffer, view, capture_view_slot(capture, view))
}

// The beauty resolve left the scene and velocity targets readable. The extra
// lit pass writes them again, so it has to wait for those fragment reads.
@(private)
view_scene_barriers :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, pass: ^Pass) {
	frame := r.frame_index
	color := r.frame_targets.scene_color[frame]
	velocity := r.frame_targets.velocity[frame]
	image_barrier(
		command_buffer,
		color.image,
		COLOR_SUBRESOURCE,
		.SHADER_READ_ONLY_OPTIMAL,
		.COLOR_ATTACHMENT_OPTIMAL,
		{.FRAGMENT_SHADER},
		{.COLOR_ATTACHMENT_OUTPUT},
		{.SHADER_READ},
		{.COLOR_ATTACHMENT_WRITE},
	)
	image_barrier(
		command_buffer,
		velocity.image,
		COLOR_SUBRESOURCE,
		.SHADER_READ_ONLY_OPTIMAL,
		.COLOR_ATTACHMENT_OPTIMAL,
		{.FRAGMENT_SHADER},
		{.COLOR_ATTACHMENT_OUTPUT},
		{.SHADER_READ},
		{.COLOR_ATTACHMENT_WRITE},
	)
	record_depth_read_barrier(command_buffer, r.frame_targets.depth[frame].image)
}

@(private)
build_view_resolve_pass :: proc(r: ^Renderer, pass: ^Pass) {
	extent := target_extent_vk(r)
	image := r.view_images.images[pass.view]
	clear := vk.ClearValue{}
	clear.color.float32 = r.clear_color
	pass.attachments[0] = {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = image.view,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .STORE,
		clearValue = clear,
	}
	pass.rendering = {
		sType = .RENDERING_INFO,
		renderArea = {extent = extent},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &pass.attachments[0],
	}
	pass.barriers = view_resolve_barriers
	pass.pipeline = r.taa.view_pipeline
	pass.layout = r.taa.view_pipeline_layout
	pass.has_rendering = true
	pass.draw = view_resolve_draw
}

@(private)
view_resolve_barriers :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, pass: ^Pass) {
	record_scene_read_barriers(r, command_buffer)
	image_barrier(
		command_buffer,
		r.view_images.images[pass.view].image,
		COLOR_SUBRESOURCE,
		.UNDEFINED,
		.COLOR_ATTACHMENT_OPTIMAL,
		{.TOP_OF_PIPE},
		{.COLOR_ATTACHMENT_OUTPUT},
		{},
		{.COLOR_ATTACHMENT_WRITE},
	)
}

@(private)
view_resolve_draw :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, pass: ^Pass) {
	taa_bind_resolve(r, command_buffer, pass.layout)
	params := TAA_Params {
		gamma          = srgb_gamma(r),
		history_valid  = 0,
		max_samples    = TAA_MAX_SAMPLES,
		history_weight = -1,
		clamp_enabled  = 1,
		force_trust    = 0,
	}
	taa_push_params(command_buffer, pass.layout, params)
	vk.CmdDraw(command_buffer, 3, 1, 0, 0)
}

@(private)
record_view_copy :: proc(
	r: ^Renderer,
	command_buffer: vk.CommandBuffer,
	view: Capture_View,
	slot: int,
) -> bool {
	if slot < 0 {
		log.errorf("renderer: view %s has no readback slot", capture_view_name(view))
		return false
	}
	return record_capture_image_copy(
		r,
		command_buffer,
		r.view_images.images[view].image,
		capture_view_name(view),
		.COLOR_ATTACHMENT_OPTIMAL,
		{.COLOR_ATTACHMENT_OUTPUT},
		{.COLOR_ATTACHMENT_WRITE},
		COLOR_SUBRESOURCE,
		slot,
	)
}
