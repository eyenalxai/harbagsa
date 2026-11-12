#+vet explicit-allocators
package renderer

import vk "vendor:vulkan"

DEBUG_VERTEX_SPIRV :: #load("../../build/shaders/debug.vert.spv")
DEBUG_FRAGMENT_SPIRV :: #load("../../build/shaders/debug.frag.spv")

destroy_overlay_pipelines :: proc(r: ^Renderer) {
	destroy_pipeline_pair(r, &r.overlay.debug_pipeline, &r.overlay.debug_layout)
}

create_overlay_pipelines :: proc(r: ^Renderer) -> bool {
	color_formats := [1]vk.Format{r.target.config.format}

	debug_set_layouts := [1]vk.DescriptorSetLayout{r.scene.descriptor_set_layout}
	debug_attributes := [2]vk.VertexInputAttributeDescription {
		{location = 0, binding = 0, format = .R32G32B32_SFLOAT, offset = 0},
		{
			location = 1,
			binding = 0,
			format = .R32G32B32A32_SFLOAT,
			offset = u32(offset_of(Debug_Vertex, color)),
		},
	}
	if !create_graphics_pipeline(
		r,
		{
			vertex_spirv = DEBUG_VERTEX_SPIRV,
			fragment_spirv = DEBUG_FRAGMENT_SPIRV,
			name = "debug",
			set_layouts = debug_set_layouts[:],
			vertex_binding = vk.VertexInputBindingDescription {
				binding = 0,
				stride = u32(size_of(Debug_Vertex)),
				inputRate = .VERTEX,
			},
			vertex_attributes = debug_attributes[:],
			topology = .LINE_LIST,
			color_formats = color_formats[:],
			depth_format = .UNDEFINED,
			blend = true,
			dynamic_viewport = true,
			dynamic_scissor = true,
		},
		&r.overlay.debug_pipeline,
		&r.overlay.debug_layout,
	) {
		return false
	}

	r.overlay.pipeline_format = r.target.config.format
	return true
}
