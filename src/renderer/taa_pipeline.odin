#+vet explicit-allocators
package renderer

import vk "vendor:vulkan"

TAA_VERTEX_SPIRV :: #load("../../build/shaders/taa.vert.spv")
TAA_FRAGMENT_SPIRV :: #load("../../build/shaders/taa.frag.spv")

create_taa_pipeline :: proc(r: ^Renderer) -> bool {
	set_layouts := [1]vk.DescriptorSetLayout{r.taa.descriptor_set_layout}
	color_formats := [2]vk.Format{r.target.config.format, HISTORY_FORMAT}
	ok := create_graphics_pipeline(
		r,
		{
			vertex_spirv = TAA_VERTEX_SPIRV,
			fragment_spirv = TAA_FRAGMENT_SPIRV,
			name = "taa resolve",
			set_layouts = set_layouts[:],
			push_constant = vk.PushConstantRange {
				stageFlags = {.FRAGMENT},
				offset = 0,
				size = u32(size_of(TAA_Params)),
			},
			topology = .TRIANGLE_LIST,
			color_formats = color_formats[:],
			depth_format = .UNDEFINED,
			dynamic_viewport = true,
			dynamic_scissor = true,
		},
		&r.taa.pipeline,
		&r.taa.pipeline_layout,
	)
	if ok {
		r.taa.pipeline_format = r.target.config.format
	}
	return ok
}
