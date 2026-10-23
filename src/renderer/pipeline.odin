#+vet explicit-allocators
package renderer

import "core:log"

import vk "vendor:vulkan"

VERTEX_SPIRV :: #load("../../build/shaders/box.vert.spv")
FRAGMENT_SPIRV :: #load("../../build/shaders/box.frag.spv")

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
