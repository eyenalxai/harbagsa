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
		build_tlas_pass(r, pass)
	case .Cluster:
		build_cluster_pass(r, pass)
	case .Depth:
		build_depth_pass(r, pass)
	case .Scene:
		build_scene_pass(r, pass)
	case .Taa:
		build_taa_pass(r, pass)
	case .Overlay:
		build_overlay_pass(r, pass)
	}
}

@(private)
build_tlas_pass :: proc(r: ^Renderer, pass: ^Pass) {
	pass.has_rendering = false
	pass.draw = draw_tlas
}

@(private)
draw_tlas :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, pass: ^Pass) {
	if !renderer_debug(r).light_shadows {
		return
	}
	record_acceleration(r, command_buffer, pass.boxes)
}

@(private)
build_cluster_pass :: proc(r: ^Renderer, pass: ^Pass) {
	pass.has_rendering = false
	pass.draw = draw_clusters
	pass.after = cluster_after
}

@(private)
draw_clusters :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, pass: ^Pass) {
	// The overflow slot is the only value that is not written by a cluster.
	counts_buffer := r.scene.cluster_counts_buffers[r.frame_index]
	vk.CmdFillBuffer(
		command_buffer,
		counts_buffer,
		vk.DeviceSize(CLUSTER_COUNT * size_of(u32)),
		vk.DeviceSize(size_of(u32)),
		0,
	)
	barrier := vk.BufferMemoryBarrier {
		sType = .BUFFER_MEMORY_BARRIER,
		srcAccessMask = {.TRANSFER_WRITE},
		dstAccessMask = {.SHADER_WRITE},
		buffer = counts_buffer,
		offset = vk.DeviceSize(CLUSTER_COUNT * size_of(u32)),
		size = vk.DeviceSize(size_of(u32)),
	}
	vk.CmdPipelineBarrier(
		command_buffer,
		{.TRANSFER},
		{.COMPUTE_SHADER},
		{},
		0,
		nil,
		1,
		&barrier,
		0,
		nil,
	)

	vk.CmdBindPipeline(command_buffer, .COMPUTE, r.scene.cluster_pipeline)
	vk.CmdBindDescriptorSets(
		command_buffer,
		.COMPUTE,
		r.scene.cluster_layout,
		0,
		1,
		&r.scene.descriptor_sets[r.frame_index],
		0,
		nil,
	)
	groups := u32((CLUSTER_COUNT + CLUSTER_LOCAL_SIZE - 1) / CLUSTER_LOCAL_SIZE)
	vk.CmdDispatch(command_buffer, groups, 1, 1)
}

@(private)
cluster_after :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, pass: ^Pass) {
	barriers := [2]vk.BufferMemoryBarrier {
		{
			sType = .BUFFER_MEMORY_BARRIER,
			srcAccessMask = {.SHADER_WRITE},
			dstAccessMask = {.SHADER_READ},
			buffer = r.scene.cluster_counts_buffers[r.frame_index],
			offset = 0,
			size = vk.DeviceSize(CLUSTER_COUNTS_SIZE),
		},
		{
			sType = .BUFFER_MEMORY_BARRIER,
			srcAccessMask = {.SHADER_WRITE},
			dstAccessMask = {.SHADER_READ},
			buffer = r.scene.cluster_indices_buffers[r.frame_index],
			offset = 0,
			size = vk.DeviceSize(CLUSTER_COUNT * CLUSTER_LIGHT_STRIDE * size_of(u32)),
		},
	}
	vk.CmdPipelineBarrier(
		command_buffer,
		{.COMPUTE_SHADER},
		{.FRAGMENT_SHADER},
		{},
		0,
		nil,
		u32(len(barriers)),
		&barriers[0],
		0,
		nil,
	)
}

@(private)
build_depth_pass :: proc(r: ^Renderer, pass: ^Pass) {
	extent := target_extent_vk(r)
	depth := r.frame_targets.depth[r.frame_index]
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
	record_depth_write_barrier(command_buffer, r.frame_targets.depth[r.frame_index].image)
}

@(private)
build_scene_pass :: proc(r: ^Renderer, pass: ^Pass, view := Capture_View.Beauty) {
	extent := target_extent_vk(r)
	frame := r.frame_index
	color := r.frame_targets.scene_color[frame]
	velocity := r.frame_targets.velocity[frame]
	depth := r.frame_targets.depth[frame]

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
	pass.view = view
	pass.draw = draw_box_pass
}

@(private)
scene_barriers :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, pass: ^Pass) {
	frame := r.frame_index
	color := r.frame_targets.scene_color[frame]
	velocity := r.frame_targets.velocity[frame]
	depth := r.frame_targets.depth[frame]

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
draw_box_pass :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, pass: ^Pass) {
	draw_boxes_indexed(
		r,
		command_buffer,
		pass.layout,
		pass.stages,
		len(pass.boxes),
		pass.view,
	)
}
