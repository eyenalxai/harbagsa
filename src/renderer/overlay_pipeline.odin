#+vet explicit-allocators
package renderer

import vk "vendor:vulkan"

DEBUG_VERTEX_SPIRV :: #load("../../build/shaders/debug.vert.spv")
DEBUG_FRAGMENT_SPIRV :: #load("../../build/shaders/debug.frag.spv")
HUD_VERTEX_SPIRV :: #load("../../build/shaders/hud.vert.spv")
HUD_FRAGMENT_SPIRV :: #load("../../build/shaders/hud.frag.spv")

destroy_overlay_pipelines :: proc(r: ^Renderer) {
	destroy_pipeline_pair(r, &r.overlay.debug_pipeline, &r.overlay.debug_layout)
	destroy_pipeline_pair(r, &r.overlay.hud_pipeline, &r.overlay.hud_layout)
}

create_overlay_pipelines :: proc(r: ^Renderer) -> bool {
	debug_layout_info := vk.PipelineLayoutCreateInfo {
		sType          = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount = 1,
		pSetLayouts    = &r.scene.descriptor_set_layout,
	}
	if !check(
		vk.CreatePipelineLayout(r.device, &debug_layout_info, nil, &r.overlay.debug_layout),
		"vkCreatePipelineLayout",
	) {
		return false
	}

	hud_push_range := vk.PushConstantRange {
		stageFlags = {.VERTEX, .FRAGMENT},
		offset     = 0,
		size       = u32(size_of([4]f32)),
	}
	hud_layout_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &hud_push_range,
	}
	if !check(
		vk.CreatePipelineLayout(r.device, &hud_layout_info, nil, &r.overlay.hud_layout),
		"vkCreatePipelineLayout",
	) {
		return false
	}

	debug_binding := vk.VertexInputBindingDescription {
		binding   = 0,
		stride    = u32(size_of(Debug_Vertex)),
		inputRate = .VERTEX,
	}
	debug_attributes := [2]vk.VertexInputAttributeDescription {
		{location = 0, binding = 0, format = .R32G32B32_SFLOAT, offset = 0},
		{
			location = 1,
			binding = 0,
			format = .R32G32B32A32_SFLOAT,
			offset = u32(offset_of(Debug_Vertex, color)),
		},
	}
	debug_attributes_slice := debug_attributes[:]
	if !create_overlay_pipeline(
		r,
		{
			vertex_spirv = DEBUG_VERTEX_SPIRV,
			fragment_spirv = DEBUG_FRAGMENT_SPIRV,
			name = "debug",
			binding = debug_binding,
			attributes = debug_attributes_slice,
			topology = .LINE_LIST,
			layout = r.overlay.debug_layout,
		},
		&r.overlay.debug_pipeline,
	) {
		return false
	}

	hud_binding := vk.VertexInputBindingDescription {
		binding   = 0,
		stride    = u32(size_of(HUD_Vertex)),
		inputRate = .VERTEX,
	}
	hud_attributes := [2]vk.VertexInputAttributeDescription {
		{location = 0, binding = 0, format = .R32G32_SFLOAT, offset = 0},
		{
			location = 1,
			binding = 0,
			format = .R32G32B32A32_SFLOAT,
			offset = u32(offset_of(HUD_Vertex, color)),
		},
	}
	hud_attributes_slice := hud_attributes[:]
	if !create_overlay_pipeline(
		r,
		{
			vertex_spirv = HUD_VERTEX_SPIRV,
			fragment_spirv = HUD_FRAGMENT_SPIRV,
			name = "hud",
			binding = hud_binding,
			attributes = hud_attributes_slice,
			topology = .TRIANGLE_LIST,
			layout = r.overlay.hud_layout,
		},
		&r.overlay.hud_pipeline,
	) {
		return false
	}

	r.overlay.pipeline_format = r.swapchain_format
	return true
}

Overlay_Pipeline_Desc :: struct {
	vertex_spirv:   []byte,
	fragment_spirv: []byte,
	name:           string,
	binding:        vk.VertexInputBindingDescription,
	attributes:     []vk.VertexInputAttributeDescription,
	topology:       vk.PrimitiveTopology,
	layout:         vk.PipelineLayout,
}

create_overlay_pipeline :: proc(r: ^Renderer, desc: Overlay_Pipeline_Desc, pipeline: ^vk.Pipeline) -> bool {
	binding := desc.binding
	vertex_module, vertex_ok := create_shader_module(r, desc.vertex_spirv, desc.name)
	if !vertex_ok {
		return false
	}
	fragment_module, fragment_ok := create_shader_module(r, desc.fragment_spirv, desc.name)
	if !fragment_ok {
		vk.DestroyShaderModule(r.device, vertex_module, nil)
		return false
	}
	defer {
		vk.DestroyShaderModule(r.device, vertex_module, nil)
		vk.DestroyShaderModule(r.device, fragment_module, nil)
	}

	stages := [2]vk.PipelineShaderStageCreateInfo {
		{
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage  = {.VERTEX},
			module = vertex_module,
			pName  = "main",
		},
		{
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage  = {.FRAGMENT},
			module = fragment_module,
			pName  = "main",
		},
	}

	vertex_input := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 1,
		pVertexBindingDescriptions      = &binding,
		vertexAttributeDescriptionCount = u32(len(desc.attributes)),
		pVertexAttributeDescriptions    = raw_data(desc.attributes),
	}
	input_assembly := vk.PipelineInputAssemblyStateCreateInfo {
		sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = desc.topology,
	}
	viewport_state := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}
	rasterization := vk.PipelineRasterizationStateCreateInfo {
		sType       = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode = .FILL,
		cullMode    = {},
		frontFace   = .CLOCKWISE,
		lineWidth   = 1.0,
	}
	multisample := vk.PipelineMultisampleStateCreateInfo {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = {._1},
	}
	depth_stencil := vk.PipelineDepthStencilStateCreateInfo {
		sType            = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable  = false,
		depthWriteEnable = false,
		depthCompareOp   = .ALWAYS,
	}
	color_attachment := vk.PipelineColorBlendAttachmentState {
		blendEnable         = true,
		srcColorBlendFactor = .SRC_ALPHA,
		dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
		colorBlendOp        = .ADD,
		srcAlphaBlendFactor = .ONE,
		dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA,
		alphaBlendOp        = .ADD,
		colorWriteMask      = {.R, .G, .B, .A},
	}
	color_blend := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &color_attachment,
	}
	dynamic_states := [2]vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = u32(len(dynamic_states)),
		pDynamicStates    = &dynamic_states[0],
	}
	rendering_info := vk.PipelineRenderingCreateInfo {
		sType                   = .PIPELINE_RENDERING_CREATE_INFO,
		colorAttachmentCount    = 1,
		pColorAttachmentFormats = &r.swapchain_format,
		depthAttachmentFormat   = DEPTH_FORMAT,
		stencilAttachmentFormat = .UNDEFINED,
	}
	pipeline_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &rendering_info,
		stageCount          = u32(len(stages)),
		pStages             = &stages[0],
		pVertexInputState   = &vertex_input,
		pInputAssemblyState = &input_assembly,
		pViewportState      = &viewport_state,
		pRasterizationState = &rasterization,
		pMultisampleState   = &multisample,
		pDepthStencilState  = &depth_stencil,
		pColorBlendState    = &color_blend,
		pDynamicState       = &dynamic_state,
		layout              = desc.layout,
		basePipelineIndex   = -1,
	}
	if !check(
		vk.CreateGraphicsPipelines(r.device, 0, 1, &pipeline_info, nil, pipeline),
		"vkCreateGraphicsPipelines",
	) {
		return false
	}
	return true
}
