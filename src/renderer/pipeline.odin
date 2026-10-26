#+vet explicit-allocators
package renderer

import vk "vendor:vulkan"

BOX_VERTEX_SPIRV :: #load("../../build/shaders/box.vert.spv")
BOX_FRAGMENT_SPIRV :: #load("../../build/shaders/box.frag.spv")
CLUSTER_COMPUTE_SPIRV :: #load("../../build/shaders/cluster.comp.spv")

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
	color_formats := [2]vk.Format{SCENE_COLOR_FORMAT, VELOCITY_FORMAT}
	binding := vk.VertexInputBindingDescription {
		binding = 0,
		stride = u32(size_of(Vertex)),
		inputRate = .VERTEX,
	}

	if !create_graphics_pipeline(
		r,
		{
			vertex_spirv = BOX_VERTEX_SPIRV,
			fragment_spirv = BOX_FRAGMENT_SPIRV,
			name = "box",
			set_layouts = set_layouts[:],
			push_constant = vk.PushConstantRange {
				stageFlags = {.VERTEX, .FRAGMENT},
				offset = 0,
				size = u32(size_of(Object_Index)),
			},
			vertex_binding = binding,
			vertex_attributes = attributes[:],
			topology = .TRIANGLE_LIST,
			color_formats = color_formats[:],
			depth_format = DEPTH_FORMAT,
			depth_test = true,
			depth_write = false,
			depth_compare = .LESS_OR_EQUAL,
			cull_back = true,
			dynamic_viewport = true,
			dynamic_scissor = true,
		},
		&r.scene.pipeline,
		&r.scene.pipeline_layout,
	) {
		return false
	}

	// A depth-only prepass pays the vertex and raster cost once per pixel, so a
	// dense overlap of boxes traces the shadow rays only for the surface in front.
	return create_graphics_pipeline(
		r,
		{
			vertex_spirv = BOX_VERTEX_SPIRV,
			name = "box depth",
			set_layouts = set_layouts[:],
			push_constant = vk.PushConstantRange {
				stageFlags = {.VERTEX},
				offset = 0,
				size = u32(size_of(Object_Index)),
			},
			vertex_binding = binding,
			vertex_attributes = attributes[:],
			topology = .TRIANGLE_LIST,
			depth_format = DEPTH_FORMAT,
			depth_test = true,
			depth_write = true,
			cull_back = true,
			dynamic_viewport = true,
			dynamic_scissor = true,
		},
		&r.scene.depth_pipeline,
		&r.scene.depth_layout,
	)
}

@(private)
create_cluster_pipeline :: proc(r: ^Renderer) -> bool {
	set_layouts := [1]vk.DescriptorSetLayout{r.scene.descriptor_set_layout}
	return create_compute_pipeline(
		r,
		{
			spirv = CLUSTER_COMPUTE_SPIRV,
			name = "cluster",
			set_layouts = set_layouts[:],
		},
		&r.scene.cluster_pipeline,
		&r.scene.cluster_layout,
	)
}
