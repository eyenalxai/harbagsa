#+vet explicit-allocators
package renderer

import "core:log"
import "core:math"
import "core:mem"

import "src:geometry"
import vk "vendor:vulkan"

CAMERA_UP :: [3]f32{0, 1, 0}
CAMERA_NEAR :: 0.05
CAMERA_FAR :: 200.0

// Camera is the per-frame view the main loop builds from the interpolated
// player state. Yaw is measured around +Y and pitch is the look angle in
// radians. fov_x is the horizontal field of view in radians.
Camera :: struct {
	position: [3]f32,
	yaw:      f32,
	pitch:    f32,
	fov_x:    f32,
}

LIGHT_DIRECTION :: [3]f32{-0.45, -1.0, -0.35}
AMBIENT_COLOR :: [3]f32{0.24, 0.25, 0.28}

DEPTH_FORMAT :: vk.Format.D32_SFLOAT

DEPTH_SUBRESOURCE :: vk.ImageSubresourceRange {
	aspectMask = {.DEPTH},
	levelCount = 1,
	layerCount = 1,
}

VERTEX_SPIRV :: #load("../../build/shaders/box.vert.spv")
FRAGMENT_SPIRV :: #load("../../build/shaders/box.frag.spv")

// The uniform block mirrors the GLSL Camera block in both shader stages.
// Mat4 is column-major, so the view and projection matrices upload directly.
Camera_Uniform :: struct {
	view:            Mat4,
	projection:      Mat4,
	light_direction: [4]f32,
	ambient:         [4]f32,
	gamma:           [4]f32,
}

// The push constant block mirrors the GLSL PushConstants block in the vertex
// shader. The color travels to the fragment stage as a varying.
Push_Constants :: struct {
	model: Mat4,
	color: [4]f32,
}

Vertex :: struct {
	position: [3]f32,
	normal:   [3]f32,
}

#assert(size_of(Camera_Uniform) == 176)
#assert(size_of(Push_Constants) == 80)
#assert(size_of(Vertex) == 24)

// The unit cube has four vertices per face so every face has its own normal.
CUBE_VERTICES := [24]Vertex {
	// +Z
	{{-0.5, -0.5, 0.5}, {0, 0, 1}},
	{{0.5, -0.5, 0.5}, {0, 0, 1}},
	{{0.5, 0.5, 0.5}, {0, 0, 1}},
	{{-0.5, 0.5, 0.5}, {0, 0, 1}},
	// -Z
	{{0.5, -0.5, -0.5}, {0, 0, -1}},
	{{-0.5, -0.5, -0.5}, {0, 0, -1}},
	{{-0.5, 0.5, -0.5}, {0, 0, -1}},
	{{0.5, 0.5, -0.5}, {0, 0, -1}},
	// +X
	{{0.5, -0.5, 0.5}, {1, 0, 0}},
	{{0.5, -0.5, -0.5}, {1, 0, 0}},
	{{0.5, 0.5, -0.5}, {1, 0, 0}},
	{{0.5, 0.5, 0.5}, {1, 0, 0}},
	// -X
	{{-0.5, -0.5, -0.5}, {-1, 0, 0}},
	{{-0.5, -0.5, 0.5}, {-1, 0, 0}},
	{{-0.5, 0.5, 0.5}, {-1, 0, 0}},
	{{-0.5, 0.5, -0.5}, {-1, 0, 0}},
	// +Y
	{{-0.5, 0.5, 0.5}, {0, 1, 0}},
	{{0.5, 0.5, 0.5}, {0, 1, 0}},
	{{0.5, 0.5, -0.5}, {0, 1, 0}},
	{{-0.5, 0.5, -0.5}, {0, 1, 0}},
	// -Y
	{{-0.5, -0.5, -0.5}, {0, -1, 0}},
	{{0.5, -0.5, -0.5}, {0, -1, 0}},
	{{0.5, -0.5, 0.5}, {0, -1, 0}},
	{{-0.5, -0.5, 0.5}, {0, -1, 0}},
}

CUBE_INDICES := [36]u16 {
	0, 1, 2, 0, 2, 3,
	4, 5, 6, 4, 6, 7,
	8, 9, 10, 8, 10, 11,
	12, 13, 14, 12, 14, 15,
	16, 17, 18, 16, 18, 19,
	20, 21, 22, 20, 22, 23,
}

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

destroy_pipeline :: proc(r: ^Renderer) {
	if r.scene.pipeline != 0 {
		vk.DestroyPipeline(r.device, r.scene.pipeline, nil)
		r.scene.pipeline = 0
	}
	if r.scene.pipeline_layout != 0 {
		vk.DestroyPipelineLayout(r.device, r.scene.pipeline_layout, nil)
		r.scene.pipeline_layout = 0
	}
}

destroy_scene :: proc(r: ^Renderer) {
	if r.device == nil {
		return
	}

	destroy_pipeline(r)
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

create_camera_resources :: proc(r: ^Renderer) -> bool {
	binding := vk.DescriptorSetLayoutBinding {
		binding = 0,
		descriptorType = .UNIFORM_BUFFER,
		descriptorCount = 1,
		stageFlags = {.VERTEX, .FRAGMENT},
	}
	layout_info := vk.DescriptorSetLayoutCreateInfo {
		sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 1,
		pBindings = &binding,
	}
	if !check(
		vk.CreateDescriptorSetLayout(r.device, &layout_info, nil, &r.scene.descriptor_set_layout),
		"vkCreateDescriptorSetLayout",
	) {
		return false
	}

	pool_size := vk.DescriptorPoolSize {
		type = .UNIFORM_BUFFER,
		descriptorCount = MAX_FRAMES_IN_FLIGHT,
	}
	pool_info := vk.DescriptorPoolCreateInfo {
		sType = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets = MAX_FRAMES_IN_FLIGHT,
		poolSizeCount = 1,
		pPoolSizes = &pool_size,
	}
	if !check(vk.CreateDescriptorPool(r.device, &pool_info, nil, &r.scene.descriptor_pool), "vkCreateDescriptorPool") {
		return false
	}

	// Allocate one set per call. The per-frame set then matches the per-frame
	// camera buffer without relying on an array allocation.
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		allocate_info := vk.DescriptorSetAllocateInfo {
			sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
			descriptorPool = r.scene.descriptor_pool,
			descriptorSetCount = 1,
			pSetLayouts = &r.scene.descriptor_set_layout,
		}
		if !check(
			vk.AllocateDescriptorSets(r.device, &allocate_info, &r.scene.descriptor_sets[i]),
			"vkAllocateDescriptorSets",
		) {
			return false
		}
	}

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		if !create_buffer(
			r,
			vk.DeviceSize(size_of(Camera_Uniform)),
			{.UNIFORM_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
			&r.scene.camera_buffers[i],
			&r.scene.camera_memory[i],
		) {
			return false
		}
		if !check(
			vk.MapMemory(
				r.device,
				r.scene.camera_memory[i],
				0,
				vk.DeviceSize(size_of(Camera_Uniform)),
				{},
				&r.scene.camera_mapped[i],
			),
			"vkMapMemory",
		) {
			return false
		}

		buffer_info := vk.DescriptorBufferInfo {
			buffer = r.scene.camera_buffers[i],
			offset = 0,
			range = vk.DeviceSize(size_of(Camera_Uniform)),
		}
		write := vk.WriteDescriptorSet {
			sType = .WRITE_DESCRIPTOR_SET,
			dstSet = r.scene.descriptor_sets[i],
			dstBinding = 0,
			descriptorCount = 1,
			descriptorType = .UNIFORM_BUFFER,
			pBufferInfo = &buffer_info,
		}
		vk.UpdateDescriptorSets(r.device, 1, &write, 0, nil)
	}

	return true
}

create_mesh :: proc(r: ^Renderer) -> bool {
	if !create_device_buffer(
		r,
		raw_data(CUBE_VERTICES[:]),
		vk.DeviceSize(size_of(CUBE_VERTICES)),
		{.VERTEX_BUFFER},
		&r.scene.vertex_buffer,
		&r.scene.vertex_memory,
	) {
		return false
	}
	if !create_device_buffer(
		r,
		raw_data(CUBE_INDICES[:]),
		vk.DeviceSize(size_of(CUBE_INDICES)),
		{.INDEX_BUFFER},
		&r.scene.index_buffer,
		&r.scene.index_memory,
	) {
		return false
	}
	r.scene.index_count = u32(len(CUBE_INDICES))
	return true
}

create_pipeline :: proc(r: ^Renderer) -> bool {
	vertex_module, vertex_ok := create_shader_module(r, VERTEX_SPIRV, "box vertex")
	if !vertex_ok {
		return false
	}
	fragment_module, fragment_ok := create_shader_module(r, FRAGMENT_SPIRV, "box fragment")
	if !fragment_ok {
		vk.DestroyShaderModule(r.device, vertex_module, nil)
		return false
	}
	defer {
		vk.DestroyShaderModule(r.device, vertex_module, nil)
		vk.DestroyShaderModule(r.device, fragment_module, nil)
	}

	push_range := vk.PushConstantRange {
		stageFlags = {.VERTEX},
		offset = 0,
		size = u32(size_of(Push_Constants)),
	}
	layout_info := vk.PipelineLayoutCreateInfo {
		sType = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount = 1,
		pSetLayouts = &r.scene.descriptor_set_layout,
		pushConstantRangeCount = 1,
		pPushConstantRanges = &push_range,
	}
	if !check(vk.CreatePipelineLayout(r.device, &layout_info, nil, &r.scene.pipeline_layout), "vkCreatePipelineLayout") {
		return false
	}

	stages := [2]vk.PipelineShaderStageCreateInfo {
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.VERTEX},
			module = vertex_module,
			pName = "main",
		},
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.FRAGMENT},
			module = fragment_module,
			pName = "main",
		},
	}

	binding := vk.VertexInputBindingDescription {
		binding = 0,
		stride = u32(size_of(Vertex)),
		inputRate = .VERTEX,
	}
	attributes := [2]vk.VertexInputAttributeDescription {
		{location = 0, binding = 0, format = .R32G32B32_SFLOAT, offset = 0},
		{
			location = 1,
			binding = 0,
			format = .R32G32B32_SFLOAT,
			offset = u32(offset_of(Vertex, normal)),
		},
	}
	vertex_input := vk.PipelineVertexInputStateCreateInfo {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount = 1,
		pVertexBindingDescriptions = &binding,
		vertexAttributeDescriptionCount = u32(len(attributes)),
		pVertexAttributeDescriptions = &attributes[0],
	}

	input_assembly := vk.PipelineInputAssemblyStateCreateInfo {
		sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = .TRIANGLE_LIST,
	}

	viewport_state := vk.PipelineViewportStateCreateInfo {
		sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount = 1,
	}

	rasterization := vk.PipelineRasterizationStateCreateInfo {
		sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode = .FILL,
		cullMode = {},
		frontFace = .CLOCKWISE,
		lineWidth = 1.0,
	}

	multisample := vk.PipelineMultisampleStateCreateInfo {
		sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = {._1},
	}

	depth_stencil := vk.PipelineDepthStencilStateCreateInfo {
		sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable = true,
		depthWriteEnable = true,
		depthCompareOp = .LESS,
	}

	color_attachment := vk.PipelineColorBlendAttachmentState {
		blendEnable = false,
		colorWriteMask = {.R, .G, .B, .A},
	}
	color_blend := vk.PipelineColorBlendStateCreateInfo {
		sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		attachmentCount = 1,
		pAttachments = &color_attachment,
	}

	dynamic_states := [2]vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state := vk.PipelineDynamicStateCreateInfo {
		sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = u32(len(dynamic_states)),
		pDynamicStates = &dynamic_states[0],
	}

	rendering_info := vk.PipelineRenderingCreateInfo {
		sType = .PIPELINE_RENDERING_CREATE_INFO,
		colorAttachmentCount = 1,
		pColorAttachmentFormats = &r.swapchain_format,
		depthAttachmentFormat = DEPTH_FORMAT,
		stencilAttachmentFormat = .UNDEFINED,
	}

	pipeline_info := vk.GraphicsPipelineCreateInfo {
		sType = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext = &rendering_info,
		stageCount = u32(len(stages)),
		pStages = &stages[0],
		pVertexInputState = &vertex_input,
		pInputAssemblyState = &input_assembly,
		pViewportState = &viewport_state,
		pRasterizationState = &rasterization,
		pMultisampleState = &multisample,
		pDepthStencilState = &depth_stencil,
		pColorBlendState = &color_blend,
		pDynamicState = &dynamic_state,
		layout = r.scene.pipeline_layout,
		basePipelineIndex = -1,
	}
	if !check(
		vk.CreateGraphicsPipelines(r.device, 0, 1, &pipeline_info, nil, &r.scene.pipeline),
		"vkCreateGraphicsPipelines",
	) {
		return false
	}
	r.scene.pipeline_format = r.swapchain_format
	return true
}

create_shader_module :: proc(r: ^Renderer, spirv: []byte, name: string) -> (module: vk.ShaderModule, ok: bool) {
	if len(spirv) == 0 || len(spirv) % 4 != 0 {
		log.errorf("renderer: %s SPIR-V is empty or not word aligned (%d bytes)", name, len(spirv))
		return 0, false
	}
	info := vk.ShaderModuleCreateInfo {
		sType = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(spirv),
		pCode = cast(^u32)raw_data(spirv),
	}
	if !check(vk.CreateShaderModule(r.device, &info, nil, &module), "vkCreateShaderModule") {
		return 0, false
	}
	return module, true
}

create_depth_resources :: proc(r: ^Renderer) -> bool {
	destroy_depth_resources(r)

	image_count := len(r.swapchain_images)
	if image_count == 0 {
		log.error("renderer: cannot create depth resources without swapchain images")
		return false
	}

	r.scene.depth_images = make([]vk.Image, image_count, r.allocator)
	r.scene.depth_memory = make([]vk.DeviceMemory, image_count, r.allocator)
	r.scene.depth_views = make([]vk.ImageView, image_count, r.allocator)

	for i in 0 ..< image_count {
		image_info := vk.ImageCreateInfo {
			sType = .IMAGE_CREATE_INFO,
			imageType = .D2,
			format = DEPTH_FORMAT,
			extent = {r.swapchain_extent.width, r.swapchain_extent.height, 1},
			mipLevels = 1,
			arrayLayers = 1,
			samples = {._1},
			tiling = .OPTIMAL,
			usage = {.DEPTH_STENCIL_ATTACHMENT},
			sharingMode = .EXCLUSIVE,
			initialLayout = .UNDEFINED,
		}
		if !check(vk.CreateImage(r.device, &image_info, nil, &r.scene.depth_images[i]), "vkCreateImage") {
			return false
		}

		requirements: vk.MemoryRequirements
		vk.GetImageMemoryRequirements(r.device, r.scene.depth_images[i], &requirements)
		memory_type, found := find_memory_type(r, requirements.memoryTypeBits, {.DEVICE_LOCAL})
		if !found {
			log.error("renderer: no device-local memory type for the depth image")
			return false
		}
		allocate_info := vk.MemoryAllocateInfo {
			sType = .MEMORY_ALLOCATE_INFO,
			allocationSize = requirements.size,
			memoryTypeIndex = memory_type,
		}
		if !check(
			vk.AllocateMemory(r.device, &allocate_info, nil, &r.scene.depth_memory[i]),
			"vkAllocateMemory",
		) {
			return false
		}
		if !check(
			vk.BindImageMemory(r.device, r.scene.depth_images[i], r.scene.depth_memory[i], 0),
			"vkBindImageMemory",
		) {
			return false
		}

		view_info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = r.scene.depth_images[i],
			viewType = .D2,
			format = DEPTH_FORMAT,
			subresourceRange = DEPTH_SUBRESOURCE,
		}
		if !check(vk.CreateImageView(r.device, &view_info, nil, &r.scene.depth_views[i]), "vkCreateImageView") {
			return false
		}
	}

	return true
}

destroy_depth_resources :: proc(r: ^Renderer) {
	if r.device != nil {
		for &view in r.scene.depth_views {
			if view != 0 {
				vk.DestroyImageView(r.device, view, nil)
				view = 0
			}
		}
		for &image in r.scene.depth_images {
			if image != 0 {
				vk.DestroyImage(r.device, image, nil)
				image = 0
			}
		}
		for &memory in r.scene.depth_memory {
			if memory != 0 {
				vk.FreeMemory(r.device, memory, nil)
				memory = 0
			}
		}
	}

	if r.scene.depth_views != nil {
		delete(r.scene.depth_views, r.allocator)
		r.scene.depth_views = nil
	}
	if r.scene.depth_images != nil {
		delete(r.scene.depth_images, r.allocator)
		r.scene.depth_images = nil
	}
	if r.scene.depth_memory != nil {
		delete(r.scene.depth_memory, r.allocator)
		r.scene.depth_memory = nil
	}
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

create_buffer :: proc(
	r: ^Renderer,
	size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	properties: vk.MemoryPropertyFlags,
	buffer: ^vk.Buffer,
	memory: ^vk.DeviceMemory,
) -> bool {
	if size == 0 {
		log.error("renderer: refusing to create an empty buffer")
		return false
	}

	create_info := vk.BufferCreateInfo {
		sType = .BUFFER_CREATE_INFO,
		size = size,
		usage = usage,
		sharingMode = .EXCLUSIVE,
	}
	if !check(vk.CreateBuffer(r.device, &create_info, nil, buffer), "vkCreateBuffer") {
		return false
	}

	requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(r.device, buffer^, &requirements)
	memory_type, found := find_memory_type(r, requirements.memoryTypeBits, properties)
	if !found {
		log.error("renderer: no memory type matches the requested buffer properties")
		destroy_buffer(r, buffer, memory)
		return false
	}

	allocate_info := vk.MemoryAllocateInfo {
		sType = .MEMORY_ALLOCATE_INFO,
		allocationSize = requirements.size,
		memoryTypeIndex = memory_type,
	}
	if !check(vk.AllocateMemory(r.device, &allocate_info, nil, memory), "vkAllocateMemory") {
		destroy_buffer(r, buffer, memory)
		return false
	}
	if !check(vk.BindBufferMemory(r.device, buffer^, memory^, 0), "vkBindBufferMemory") {
		destroy_buffer(r, buffer, memory)
		return false
	}
	return true
}

destroy_buffer :: proc(r: ^Renderer, buffer: ^vk.Buffer, memory: ^vk.DeviceMemory) {
	if r.device != nil {
		if buffer^ != 0 {
			vk.DestroyBuffer(r.device, buffer^, nil)
			buffer^ = 0
		}
		if memory^ != 0 {
			vk.FreeMemory(r.device, memory^, nil)
			memory^ = 0
		}
	}
}

// create_device_buffer uploads data through a host-visible staging buffer and
// leaves the result in device-local memory.
create_device_buffer :: proc(
	r: ^Renderer,
	data: rawptr,
	size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	buffer: ^vk.Buffer,
	memory: ^vk.DeviceMemory,
) -> bool {
	staging_buffer: vk.Buffer
	staging_memory: vk.DeviceMemory
	defer destroy_buffer(r, &staging_buffer, &staging_memory)

	if !create_buffer(
		r,
		size,
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
		&staging_buffer,
		&staging_memory,
	) {
		return false
	}

	mapped: rawptr
	if !check(vk.MapMemory(r.device, staging_memory, 0, size, {}, &mapped), "vkMapMemory") {
		return false
	}
	mem.copy(mapped, data, int(size))
	vk.UnmapMemory(r.device, staging_memory)

	if !create_buffer(r, size, usage | {.TRANSFER_DST}, {.DEVICE_LOCAL}, buffer, memory) {
		return false
	}

	allocate_info := vk.CommandBufferAllocateInfo {
		sType = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool = r.command_pool,
		level = .PRIMARY,
		commandBufferCount = 1,
	}
	command_buffer: vk.CommandBuffer
	if !check(vk.AllocateCommandBuffers(r.device, &allocate_info, &command_buffer), "vkAllocateCommandBuffers") {
		return false
	}
	defer vk.FreeCommandBuffers(r.device, r.command_pool, 1, &command_buffer)

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	if !check(vk.BeginCommandBuffer(command_buffer, &begin_info), "vkBeginCommandBuffer") {
		return false
	}
	copy_region := vk.BufferCopy{size = size}
	vk.CmdCopyBuffer(command_buffer, staging_buffer, buffer^, 1, &copy_region)
	if !check(vk.EndCommandBuffer(command_buffer), "vkEndCommandBuffer") {
		return false
	}

	submit := vk.SubmitInfo {
		sType = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers = &command_buffer,
	}
	if !check(vk.QueueSubmit(r.graphics_queue, 1, &submit, 0), "vkQueueSubmit") {
		return false
	}
	return check(vk.QueueWaitIdle(r.graphics_queue), "vkQueueWaitIdle")
}

find_memory_type :: proc(
	r: ^Renderer,
	type_bits: u32,
	properties: vk.MemoryPropertyFlags,
) -> (
	memory_type: u32,
	ok: bool,
) {
	for i in 0 ..< r.memory_properties.memoryTypeCount {
		if type_bits & (u32(1) << i) == 0 {
			continue
		}
		available := r.memory_properties.memoryTypes[i].propertyFlags
		if available & properties == properties {
			return u32(i), true
		}
	}
	return 0, false
}
