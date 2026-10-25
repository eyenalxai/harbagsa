#+vet explicit-allocators
package renderer

import "src:geometry"
import "src:perf"
import vk "vendor:vulkan"

build_pass :: proc(
	r: ^Renderer,
	pass: ^Pass,
	kind: perf.Pass,
	image_index: u32,
	boxes: []geometry.Box,
) {
	pass^ = {
		name        = kind,
		image_index = image_index,
		boxes       = boxes,
	}
	switch kind {
	case .Tlas:
		pass.draw = draw_tlas
	case .Depth:
		build_depth_pass(r, pass)
	case .Scene:
		build_scene_pass(r, pass)
	case .Sky:
		build_sky_pass(r, pass)
	case .Taa:
		build_taa_pass(r, pass)
	case .Overlay:
		build_overlay_pass(r, pass)
	}
}

@(private)
build_depth_pass :: proc(r: ^Renderer, pass: ^Pass) {
	extent := target_extent_vk(r)
	depth := r.taa.depth[r.frame_index]
	pass.depth = make_depth_attachment(depth.view, .DEPTH_ATTACHMENT_OPTIMAL)
	pass.rendering = {
		sType           = .RENDERING_INFO,
		renderArea      = {extent = extent},
		layerCount      = 1,
		pDepthAttachment = &pass.depth,
	}
	pass.barriers = depth_barriers
	pass.pipeline = r.scene.depth_pipeline
	pass.layout = r.scene.depth_layout
	pass.stages = {.VERTEX}
	pass.bind_camera = true
	pass.has_rendering = true
	pass.draw = draw_box_pass
}

@(private)
depth_barriers :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, pass: ^Pass) {
	record_depth_write_barrier(command_buffer, r.taa.depth[r.frame_index].image)
}

@(private)
build_scene_pass :: proc(r: ^Renderer, pass: ^Pass) {
	extent := target_extent_vk(r)
	frame := r.frame_index
	color := r.taa.scene_color[frame]
	velocity := r.taa.velocity[frame]
	depth := r.taa.depth[frame]

	color_clear := vk.ClearValue{}
	color_clear.color.float32 = r.clear_color
	velocity_clear := vk.ClearValue{}
	velocity_clear.color.float32 = {0, 0, CAMERA_FAR, 0}
	pass.attachments[0] = {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = color.view,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .STORE,
		clearValue = color_clear,
	}
	pass.attachments[1] = {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = velocity.view,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .STORE,
		clearValue = velocity_clear,
	}
	pass.depth = make_depth_attachment(depth.view, .DEPTH_ATTACHMENT_OPTIMAL, .LOAD)
	pass.rendering = {
		sType = .RENDERING_INFO,
		renderArea = {extent = extent},
		layerCount = 1,
		colorAttachmentCount = 2,
		pColorAttachments = &pass.attachments[0],
		pDepthAttachment = &pass.depth,
	}
	pass.barriers = scene_barriers
	pass.pipeline = r.scene.pipeline
	pass.layout = r.scene.pipeline_layout
	pass.stages = {.VERTEX, .FRAGMENT}
	pass.bind_camera = true
	pass.has_rendering = true
	pass.draw = draw_box_pass
}

@(private)
scene_barriers :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, pass: ^Pass) {
	frame := r.frame_index
	color := r.taa.scene_color[frame]
	velocity := r.taa.velocity[frame]
	depth := r.taa.depth[frame]

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
	record_depth_read_barrier(command_buffer, depth.image)
}

@(private)
build_sky_pass :: proc(r: ^Renderer, pass: ^Pass) {
	extent := target_extent_vk(r)
	frame := r.frame_index
	color := r.taa.scene_color[frame]
	velocity := r.taa.velocity[frame]
	depth := r.taa.depth[frame]

	pass.attachments[0] = {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = color.view,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp = .LOAD,
		storeOp = .STORE,
	}
	pass.attachments[1] = {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = velocity.view,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp = .LOAD,
		storeOp = .STORE,
	}
	pass.depth = make_depth_attachment(depth.view, .DEPTH_ATTACHMENT_OPTIMAL, .LOAD)
	pass.rendering = {
		sType = .RENDERING_INFO,
		renderArea = {extent = extent},
		layerCount = 1,
		colorAttachmentCount = 2,
		pColorAttachments = &pass.attachments[0],
		pDepthAttachment = &pass.depth,
	}
	pass.barriers = sky_barriers
	pass.pipeline = r.scene.sky_pipeline
	pass.layout = r.scene.sky_layout
	pass.bind_camera = true
	pass.has_rendering = true
	pass.draw = draw_sky
}

@(private)
build_taa_pass :: proc(r: ^Renderer, pass: ^Pass) {
	extent := target_extent_vk(r)
	read_index := r.taa.history_read
	write_index := (read_index + 1) % TAA_HISTORY_IMAGES
	write := r.taa.history[write_index]
	write_count := r.taa.counts[write_index]

	target_clear := vk.ClearValue{}
	target_clear.color.float32 = r.clear_color
	pass.attachments[0] = {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = r.target.views[pass.image_index],
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .STORE,
		clearValue = target_clear,
	}
	pass.attachments[1] = {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = write.view,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp = .DONT_CARE,
		storeOp = .STORE,
	}
	pass.attachments[2] = {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = write_count.view,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp = .DONT_CARE,
		storeOp = .STORE,
	}
	pass.rendering = {
		sType = .RENDERING_INFO,
		renderArea = {extent = extent},
		layerCount = 1,
		colorAttachmentCount = 3,
		pColorAttachments = &pass.attachments[0],
	}
	pass.barriers = taa_barriers
	pass.after = taa_after
	pass.pipeline = r.taa.pipeline
	pass.layout = r.taa.pipeline_layout
	pass.has_rendering = true
	pass.draw = taa_draw
}

@(private)
build_overlay_pass :: proc(r: ^Renderer, pass: ^Pass) {
	extent := target_extent_vk(r)
	pass.attachments[0] = {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = r.target.views[pass.image_index],
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp = .LOAD,
		storeOp = .STORE,
	}
	pass.rendering = {
		sType = .RENDERING_INFO,
		renderArea = {extent = extent},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &pass.attachments[0],
	}
	pass.has_rendering = true
	pass.draw = overlay_draw
}

@(private)
draw_tlas :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, pass: ^Pass) {
	record_acceleration(r, command_buffer, pass.boxes)
}

@(private)
draw_box_pass :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, pass: ^Pass) {
	draw_boxes_indexed(
		r,
		command_buffer,
		pass.layout,
		pass.stages,
		len(pass.boxes),
	)
}

@(private)
draw_sky :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, pass: ^Pass) {
	vk.CmdDraw(command_buffer, 3, 1, 0, 0)
}
