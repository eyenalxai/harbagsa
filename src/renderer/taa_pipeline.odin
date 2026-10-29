#+vet explicit-allocators
package renderer

import vk "vendor:vulkan"

TAA_VERTEX_SPIRV :: #load("../../build/shaders/taa.vert.spv")
TAA_FRAGMENT_SPIRV :: #load("../../build/shaders/taa.frag.spv")
TAA_VIEW_FRAGMENT_SPIRV :: #load("../../build/shaders/taa_view.frag.spv")

@(private)
create_taa_like_pipeline :: proc(
	r: ^Renderer,
	name: string,
	fragment_spirv: []byte,
	formats: []vk.Format,
	pipeline: ^vk.Pipeline,
	layout: ^vk.PipelineLayout,
) -> bool {
	set_layouts := [1]vk.DescriptorSetLayout{r.taa.descriptor_set_layout}
	return create_graphics_pipeline(
		r,
		{
			vertex_spirv = TAA_VERTEX_SPIRV,
			fragment_spirv = fragment_spirv,
			name = name,
			set_layouts = set_layouts[:],
			push_constant = vk.PushConstantRange {
				stageFlags = {.FRAGMENT},
				offset = 0,
				size = u32(size_of(TAA_Params)),
			},
			topology = .TRIANGLE_LIST,
			color_formats = formats,
			depth_format = .UNDEFINED,
			dynamic_viewport = true,
			dynamic_scissor = true,
		},
		pipeline,
		layout,
	)
}

create_taa_pipeline :: proc(r: ^Renderer) -> bool {
	formats := [3]vk.Format{r.target.config.format, HISTORY_FORMAT, COUNT_FORMAT}
	if !create_taa_like_pipeline(
		r,
		"taa resolve",
		TAA_FRAGMENT_SPIRV,
		formats[:],
		&r.taa.pipeline,
		&r.taa.pipeline_layout,
	) {
		return false
	}
	// A term view resolves the same shader into one image. The history and count
	// outputs are absent, so the shader cannot advance the history there.
	view_formats := [1]vk.Format{r.target.config.format}
	if !create_taa_like_pipeline(
		r,
		"term view resolve",
		TAA_VIEW_FRAGMENT_SPIRV,
		view_formats[:],
		&r.taa.view_pipeline,
		&r.taa.view_pipeline_layout,
	) {
		destroy_pipeline_pair(r, &r.taa.pipeline, &r.taa.pipeline_layout)
		return false
	}
	r.taa.pipeline_format = r.target.config.format
	return true
}
