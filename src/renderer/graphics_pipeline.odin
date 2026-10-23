#+vet explicit-allocators
package renderer

import "core:log"

import vk "vendor:vulkan"

GRAPHICS_PIPELINE_MAX_COLOR_ATTACHMENTS :: 2
GRAPHICS_PIPELINE_MAX_DYNAMIC_STATES :: 2

Graphics_Pipeline_Desc :: struct {
	vertex_spirv:      []byte,
	fragment_spirv:    []byte,
	name:              string,
	set_layouts:       []vk.DescriptorSetLayout,
	push_constant:     Maybe(vk.PushConstantRange),
	vertex_binding:    Maybe(vk.VertexInputBindingDescription),
	vertex_attributes: []vk.VertexInputAttributeDescription,
	topology:          vk.PrimitiveTopology,
	color_formats:     []vk.Format,
	depth_format:      vk.Format,
	depth_test:        bool,
	depth_write:       bool,
	blend:             bool,
	dynamic_viewport:  bool,
	dynamic_scissor:   bool,
	viewport:          vk.Viewport,
	scissor:           vk.Rect2D,
}

create_graphics_pipeline :: proc(
	r: ^Renderer,
	desc: Graphics_Pipeline_Desc,
	pipeline: ^vk.Pipeline,
	layout: ^vk.PipelineLayout,
) -> bool {
	if len(desc.color_formats) == 0 || len(desc.color_formats) > GRAPHICS_PIPELINE_MAX_COLOR_ATTACHMENTS {
		log.errorf("renderer: %s pipeline needs one or two color formats", desc.name)
		return false
	}
	if !desc.dynamic_viewport && (desc.viewport.width <= 0 || desc.viewport.height <= 0) {
		log.errorf("renderer: %s pipeline needs a viewport or dynamic viewport", desc.name)
		return false
	}
	if !desc.dynamic_scissor &&
	   (desc.scissor.extent.width == 0 || desc.scissor.extent.height == 0) {
		log.errorf("renderer: %s pipeline needs a scissor or dynamic scissor", desc.name)
		return false
	}

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

	created := false
	defer {
		if !created {
			destroy_pipeline_pair(r, pipeline, layout)
		}
	}

	layout_info := vk.PipelineLayoutCreateInfo {
		sType          = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount = u32(len(desc.set_layouts)),
		pSetLayouts    = raw_data(desc.set_layouts),
	}
	push_range: vk.PushConstantRange
	if range, has_push := desc.push_constant.?; has_push {
		push_range = range
		layout_info.pushConstantRangeCount = 1
		layout_info.pPushConstantRanges = &push_range
	}
	if !check(vk.CreatePipelineLayout(r.device, &layout_info, nil, layout), "vkCreatePipelineLayout") {
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

	binding: vk.VertexInputBindingDescription
	vertex_input := vk.PipelineVertexInputStateCreateInfo {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
	}
	if vertex_binding, has_binding := desc.vertex_binding.?; has_binding {
		binding = vertex_binding
		vertex_input.vertexBindingDescriptionCount = 1
		vertex_input.pVertexBindingDescriptions = &binding
		vertex_input.vertexAttributeDescriptionCount = u32(len(desc.vertex_attributes))
		vertex_input.pVertexAttributeDescriptions = raw_data(desc.vertex_attributes)
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
	dynamic_states: [GRAPHICS_PIPELINE_MAX_DYNAMIC_STATES]vk.DynamicState
	dynamic_count: u32
	viewport := desc.viewport
	scissor := desc.scissor
	if desc.dynamic_viewport {
		dynamic_states[dynamic_count] = .VIEWPORT
		dynamic_count += 1
	} else {
		viewport_state.pViewports = &viewport
	}
	if desc.dynamic_scissor {
		dynamic_states[dynamic_count] = .SCISSOR
		dynamic_count += 1
	} else {
		viewport_state.pScissors = &scissor
	}
	dynamic_state := vk.PipelineDynamicStateCreateInfo {
		sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
	}
	if dynamic_count > 0 {
		dynamic_state.dynamicStateCount = dynamic_count
		dynamic_state.pDynamicStates = &dynamic_states[0]
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

	has_depth := desc.depth_format != .UNDEFINED
	depth_compare := vk.CompareOp.ALWAYS
	if has_depth && desc.depth_test {
		depth_compare = .LESS
	}
	depth_stencil := vk.PipelineDepthStencilStateCreateInfo {
		sType            = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable  = b32(has_depth && desc.depth_test),
		depthWriteEnable = b32(has_depth && desc.depth_write),
		depthCompareOp   = depth_compare,
	}

	color_attachments: [GRAPHICS_PIPELINE_MAX_COLOR_ATTACHMENTS]vk.PipelineColorBlendAttachmentState
	for i in 0 ..< len(desc.color_formats) {
		color_attachments[i] = color_blend_attachment(desc.blend)
	}
	color_blend := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		attachmentCount = u32(len(desc.color_formats)),
		pAttachments    = &color_attachments[0],
	}

	rendering_info := vk.PipelineRenderingCreateInfo {
		sType                   = .PIPELINE_RENDERING_CREATE_INFO,
		colorAttachmentCount    = u32(len(desc.color_formats)),
		pColorAttachmentFormats = raw_data(desc.color_formats),
		depthAttachmentFormat   = desc.depth_format,
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
		layout              = layout^,
		basePipelineIndex   = -1,
	}
	if !check(vk.CreateGraphicsPipelines(r.device, 0, 1, &pipeline_info, nil, pipeline), "vkCreateGraphicsPipelines") {
		return false
	}
	created = true
	return true
}

@(private)
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

@(private)
color_blend_attachment :: proc(blend: bool) -> vk.PipelineColorBlendAttachmentState {
	if !blend {
		return {
			blendEnable = false,
			colorWriteMask = {.R, .G, .B, .A},
		}
	}
	return {
		blendEnable = true,
		srcColorBlendFactor = .SRC_ALPHA,
		dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
		colorBlendOp = .ADD,
		srcAlphaBlendFactor = .ONE,
		dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA,
		alphaBlendOp = .ADD,
		colorWriteMask = {.R, .G, .B, .A},
	}
}
