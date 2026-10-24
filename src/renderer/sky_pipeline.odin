#+vet explicit-allocators
package renderer

import vk "vendor:vulkan"

SKY_VERTEX_SPIRV :: #load("../../build/shaders/sky.vert.spv")
SKY_FRAGMENT_SPIRV :: #load("../../build/shaders/sky.frag.spv")

create_sky_pipeline :: proc(r: ^Renderer) -> bool {
	set_layouts := [1]vk.DescriptorSetLayout{r.scene.descriptor_set_layout}
	color_formats := [2]vk.Format{SCENE_COLOR_FORMAT, VELOCITY_FORMAT}
	return create_graphics_pipeline(
		r,
		{
			vertex_spirv = SKY_VERTEX_SPIRV,
			fragment_spirv = SKY_FRAGMENT_SPIRV,
			name = "sky",
			set_layouts = set_layouts[:],
			topology = .TRIANGLE_LIST,
			color_formats = color_formats[:],
			depth_format = DEPTH_FORMAT,
			depth_test = true,
			depth_write = false,
			depth_compare = .EQUAL,
			cull_back = false,
			dynamic_viewport = true,
			dynamic_scissor = true,
		},
		&r.scene.sky_pipeline,
		&r.scene.sky_layout,
	)
}
