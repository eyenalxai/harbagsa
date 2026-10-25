#+vet explicit-allocators
package renderer

import vk "vendor:vulkan"

Compute_Pipeline_Desc :: struct {
	spirv:        []byte,
	name:         string,
	set_layouts:  []vk.DescriptorSetLayout,
	push_constant: Maybe(vk.PushConstantRange),
}

create_compute_pipeline :: proc(
	r: ^Renderer,
	desc: Compute_Pipeline_Desc,
	pipeline: ^vk.Pipeline,
	layout: ^vk.PipelineLayout,
) -> bool {
	module, module_ok := create_shader_module(r, desc.spirv, desc.name)
	if !module_ok {
		return false
	}
	defer vk.DestroyShaderModule(r.device, module, nil)

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

	stage := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.COMPUTE},
		module = module,
		pName  = "main",
	}
	info := vk.ComputePipelineCreateInfo {
		sType  = .COMPUTE_PIPELINE_CREATE_INFO,
		stage  = stage,
		layout = layout^,
	}
	if !check(
		vk.CreateComputePipelines(r.device, 0, 1, &info, nil, pipeline),
		"vkCreateComputePipelines",
	) {
		return false
	}
	created = true
	return true
}
