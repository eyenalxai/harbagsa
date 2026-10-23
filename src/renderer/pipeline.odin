#+vet explicit-allocators
package renderer

import vk "vendor:vulkan"

BOX_VERTEX_SPIRV :: #load("../../build/shaders/box.vert.spv")
BOX_FRAGMENT_SPIRV :: #load("../../build/shaders/box.frag.spv")

create_pipeline :: proc(r: ^Renderer) -> bool {
	set_layouts := [1]vk.DescriptorSetLayout{r.scene.descriptor_set_layout}
	attributes := [2]vk.VertexInputAttributeDescription {
		{location = 0, binding = 0, format = .R32G32B32_SFLOAT, offset = 0},
		{
			location = 1,
			binding = 0,
			format = .R32G32B32_SFLOAT,
			offset = u32(offset_of(Vertex, normal)),
		},
	}
	color_formats := [1]vk.Format{r.target.config.format}

	ok := create_graphics_pipeline(
		r,
		{
			vertex_spirv = BOX_VERTEX_SPIRV,
			fragment_spirv = BOX_FRAGMENT_SPIRV,
			name = "box",
			set_layouts = set_layouts[:],
			push_constant = vk.PushConstantRange {
				stageFlags = {.VERTEX},
				offset = 0,
				size = u32(size_of(Push_Constants)),
			},
			vertex_binding = vk.VertexInputBindingDescription {
				binding = 0,
				stride = u32(size_of(Vertex)),
				inputRate = .VERTEX,
			},
			vertex_attributes = attributes[:],
			topology = .TRIANGLE_LIST,
			color_formats = color_formats[:],
			depth_format = DEPTH_FORMAT,
			depth_test = true,
			depth_write = true,
			dynamic_viewport = true,
			dynamic_scissor = true,
		},
		&r.scene.pipeline,
		&r.scene.pipeline_layout,
	)
	if ok {
		r.scene.pipeline_format = r.target.config.format
	}
	return ok
}
