#+vet explicit-allocators
package renderer

import "core:log"
import "core:math"

import "src:geometry"
import vk "vendor:vulkan"

CAMERA_UP :: [3]f32{0, 1, 0}
CAMERA_NEAR :: 0.05
CAMERA_FAR :: 200.0

Camera :: struct {
	position: [3]f32,
	yaw:      f32,
	pitch:    f32,
	fov_x:    f32,
}

LIGHT_DIRECTION :: [3]f32{-0.45, -1.0, -0.35}
AMBIENT_COLOR :: [3]f32{0.24, 0.25, 0.28}

Scene :: struct {
	vertex_buffer: vk.Buffer,
	vertex_memory: vk.DeviceMemory,
	index_buffer:  vk.Buffer,
	index_memory:  vk.DeviceMemory,
	index_count:   u32,

	pipeline_layout:       vk.PipelineLayout,
	pipeline:              vk.Pipeline,
	pipeline_format:       vk.Format,
	descriptor_set_layout: vk.DescriptorSetLayout,
	descriptor_pool:       vk.DescriptorPool,
	descriptor_sets:       [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,

	camera_buffers: [MAX_FRAMES_IN_FLIGHT]vk.Buffer,
	camera_memory:  [MAX_FRAMES_IN_FLIGHT]vk.DeviceMemory,
	camera_mapped:  [MAX_FRAMES_IN_FLIGHT]rawptr,

	depth_images: []vk.Image,
	depth_memory: []vk.DeviceMemory,
	depth_views:  []vk.ImageView,
}

init_scene :: proc(r: ^Renderer) -> Error {
	if !create_camera_resources(r) {
		return .Create_Scene
	}
	if !create_mesh(r) {
		return .Create_Scene
	}
	if !create_pipeline(r) {
		return .Create_Pipeline
	}
	return .None
}

destroy_scene :: proc(r: ^Renderer) {
	if r.device == nil {
		return
	}

	destroy_pipeline_pair(r, &r.scene.pipeline, &r.scene.pipeline_layout)
	if r.scene.descriptor_pool != 0 {
		vk.DestroyDescriptorPool(r.device, r.scene.descriptor_pool, nil)
		r.scene.descriptor_pool = 0
	}
	if r.scene.descriptor_set_layout != 0 {
		vk.DestroyDescriptorSetLayout(r.device, r.scene.descriptor_set_layout, nil)
		r.scene.descriptor_set_layout = 0
	}

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		if r.scene.camera_mapped[i] != nil {
			vk.UnmapMemory(r.device, r.scene.camera_memory[i])
			r.scene.camera_mapped[i] = nil
		}
		destroy_buffer(r, &r.scene.camera_buffers[i], &r.scene.camera_memory[i])
	}

	destroy_buffer(r, &r.scene.vertex_buffer, &r.scene.vertex_memory)
	destroy_buffer(r, &r.scene.index_buffer, &r.scene.index_memory)
	r.scene.index_count = 0
}

record_scene :: proc(
	r: ^Renderer,
	command_buffer: vk.CommandBuffer,
	image_index: u32,
	camera: Camera,
	boxes: []geometry.Box,
	debug_lines: []geometry.Line,
	hud: HUD_State,
) -> bool {
	if int(image_index) >= len(r.swapchain_views) || int(image_index) >= len(r.scene.depth_views) {
		log.errorf("renderer: swapchain image index %d is out of range", image_index)
		return false
	}

	if !prepare_overlay(r, debug_lines, hud) {
		log.error("renderer: overlay vertex upload failed")
		return false
	}

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	if !check(vk.BeginCommandBuffer(command_buffer, &begin_info), "vkBeginCommandBuffer") {
		return false
	}

	if !update_camera(r, camera) {
		return false
	}

	to_color := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
		oldLayout = .UNDEFINED,
		newLayout = .COLOR_ATTACHMENT_OPTIMAL,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = r.swapchain_images[image_index],
		subresourceRange = COLOR_SUBRESOURCE,
	}
	to_depth := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		dstAccessMask = {.DEPTH_STENCIL_ATTACHMENT_WRITE},
		oldLayout = .UNDEFINED,
		newLayout = .DEPTH_ATTACHMENT_OPTIMAL,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = r.scene.depth_images[image_index],
		subresourceRange = DEPTH_SUBRESOURCE,
	}
	vk.CmdPipelineBarrier(
		command_buffer,
		{.TOP_OF_PIPE},
		{.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS},
		{},
		0,
		nil,
		0,
		nil,
		1,
		&to_color,
	)
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
		&to_depth,
	)

	clear := r.clear_color
	if !r.swapchain_is_srgb {
		clear = {srgb_encode(clear.r), srgb_encode(clear.g), srgb_encode(clear.b), clear.a}
	}
	clear_color := vk.ClearValue{}
	clear_color.color.float32 = clear
	color_attachment := vk.RenderingAttachmentInfo {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = r.swapchain_views[image_index],
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .STORE,
		clearValue = clear_color,
	}

	clear_depth := vk.ClearValue{}
	clear_depth.depthStencil = {depth = 1.0, stencil = 0}
	depth_attachment := vk.RenderingAttachmentInfo {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = r.scene.depth_views[image_index],
		imageLayout = .DEPTH_ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .STORE,
		clearValue = clear_depth,
	}

	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {extent = r.swapchain_extent},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &color_attachment,
		pDepthAttachment = &depth_attachment,
	}
	vk.CmdBeginRendering(command_buffer, &rendering_info)

	viewport := vk.Viewport {
		x = 0,
		y = 0,
		width = f32(r.swapchain_extent.width),
		height = f32(r.swapchain_extent.height),
		minDepth = 0,
		maxDepth = 1,
	}
	scissor := vk.Rect2D{extent = r.swapchain_extent}
	vk.CmdSetViewport(command_buffer, 0, 1, &viewport)
	vk.CmdSetScissor(command_buffer, 0, 1, &scissor)

	vk.CmdBindPipeline(command_buffer, .GRAPHICS, r.scene.pipeline)

	descriptor_set := r.scene.descriptor_sets[r.frame_index]
	vk.CmdBindDescriptorSets(command_buffer, .GRAPHICS, r.scene.pipeline_layout, 0, 1, &descriptor_set, 0, nil)

	vertex_buffer := r.scene.vertex_buffer
	vertex_offset: vk.DeviceSize = 0
	vk.CmdBindVertexBuffers(command_buffer, 0, 1, &vertex_buffer, &vertex_offset)
	vk.CmdBindIndexBuffer(command_buffer, r.scene.index_buffer, 0, .UINT16)

	for box in boxes {
		scale := [3]f32 {
			box.half_extents.x * 2,
			box.half_extents.y * 2,
			box.half_extents.z * 2,
		}
		push := Push_Constants {
			model = mat4_multiply(
				mat4_translation(box.center),
				mat4_multiply(mat4_rotation(box.rotation), mat4_scale(scale)),
			),
			color = box.color,
		}
		vk.CmdPushConstants(
			command_buffer,
			r.scene.pipeline_layout,
			{.VERTEX},
			0,
			u32(size_of(Push_Constants)),
			&push,
		)
		vk.CmdDrawIndexed(command_buffer, r.scene.index_count, 1, 0, 0, 0)
	}

	record_overlay(r, command_buffer)

	vk.CmdEndRendering(command_buffer)

	to_present := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		srcAccessMask = {.COLOR_ATTACHMENT_WRITE},
		oldLayout = .COLOR_ATTACHMENT_OPTIMAL,
		newLayout = .PRESENT_SRC_KHR,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = r.swapchain_images[image_index],
		subresourceRange = COLOR_SUBRESOURCE,
	}
	vk.CmdPipelineBarrier(
		command_buffer,
		{.COLOR_ATTACHMENT_OUTPUT},
		{.BOTTOM_OF_PIPE},
		{},
		0,
		nil,
		0,
		nil,
		1,
		&to_present,
	)

	return check(vk.EndCommandBuffer(command_buffer), "vkEndCommandBuffer")
}

update_camera :: proc(r: ^Renderer, camera: Camera) -> bool {
	height := f32(r.swapchain_extent.height)
	if height <= 0 {
		log.error("renderer: cannot build a projection for a zero-height swapchain")
		return false
	}
	aspect := f32(r.swapchain_extent.width) / height

	buffer := cast(^Camera_Uniform)r.scene.camera_mapped[r.frame_index]
	if buffer == nil {
		log.error("renderer: camera uniform buffer is not mapped")
		return false
	}

	cos_pitch := math.cos(camera.pitch)
	forward := [3]f32{
		-math.sin(camera.yaw) * cos_pitch,
		math.sin(camera.pitch),
		-math.cos(camera.yaw) * cos_pitch,
	}
	target := [3]f32 {
		camera.position.x + forward.x,
		camera.position.y + forward.y,
		camera.position.z + forward.z,
	}
	view := mat4_look_at(camera.position, target, CAMERA_UP)

	gamma: f32
	if !r.swapchain_is_srgb {
		gamma = 1
	}
	fov_y := 2 * math.atan(math.tan(camera.fov_x * 0.5) / aspect)
	buffer^ = Camera_Uniform {
		view = view,
		projection = mat4_perspective(fov_y, aspect, CAMERA_NEAR, CAMERA_FAR),
		light_direction = {LIGHT_DIRECTION.x, LIGHT_DIRECTION.y, LIGHT_DIRECTION.z, 0},
		ambient = {AMBIENT_COLOR.x, AMBIENT_COLOR.y, AMBIENT_COLOR.z, 0},
		gamma = {gamma, 0, 0, 0},
	}
	return true
}
