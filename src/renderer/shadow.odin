#+vet explicit-allocators
package renderer

import "core:math"
import "core:math/linalg"

import "src:geometry"
import vk "vendor:vulkan"

SHADOW_MAP_SIZE :: 4096
LIGHT_VOLUME_RADIUS :: 30.0
LIGHT_VOLUME_DEPTH :: 60.0
LIGHT_VOLUME_CENTER :: [3]f32{0, 1.5, 0}
// The real sun is about 0.53 degrees. The demo uses a wider disk so the
// contact-hardening cue is visible over the arena's short shadows.
SUN_ANGULAR_DIAMETER :: 3.0 * math.PI / 180.0

SHADOW_VERTEX_SPIRV :: #load("../../build/shaders/shadow.vert.spv")

Shadow :: struct {
	images:                [MAX_FRAMES_IN_FLIGHT]Image,
	compare_sampler:       vk.Sampler,
	depth_sampler:         vk.Sampler,
	pipeline:              vk.Pipeline,
	pipeline_layout:       vk.PipelineLayout,
	light_view_projection: Mat4,
}

// The light volume is fixed; only the direction follows the runtime sun.
shadow_light_matrix :: proc(light_direction: [3]f32) -> Mat4 {
	to_light := -linalg.vector_normalize0(light_direction)
	eye := LIGHT_VOLUME_CENTER + to_light * (LIGHT_VOLUME_DEPTH * 0.5)
	view := mat4_look_at(eye, LIGHT_VOLUME_CENTER, CAMERA_UP)
	projection := mat4_orthographic(
		-LIGHT_VOLUME_RADIUS,
		LIGHT_VOLUME_RADIUS,
		-LIGHT_VOLUME_RADIUS,
		LIGHT_VOLUME_RADIUS,
		0,
		LIGHT_VOLUME_DEPTH,
	)
	return mat4_multiply(projection, view)
}

// UV radius per unit of normalized depth difference. The sun is at infinity,
// so the penumbra grows with the receiver-to-blocker distance and does not
// divide by the blocker depth.
shadow_penumbra_scale :: proc() -> f32 {
	return LIGHT_VOLUME_DEPTH * math.tan(f32(SUN_ANGULAR_DIAMETER * 0.5)) / (2 * LIGHT_VOLUME_RADIUS)
}

create_shadow_resources :: proc(r: ^Renderer) -> bool {
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		image, ok := create_image(
			r,
			SHADOW_MAP_SIZE,
			SHADOW_MAP_SIZE,
			DEPTH_FORMAT,
			{.DEPTH_STENCIL_ATTACHMENT, .SAMPLED},
			{.DEPTH},
		)
		if !ok {
			return false
		}
		r.shadow.images[i] = image
	}

	properties: vk.FormatProperties
	vk.GetPhysicalDeviceFormatProperties(r.physical_device, DEPTH_FORMAT, &properties)
	compare_filter := vk.Filter.LINEAR
	if (properties.optimalTilingFeatures & {.SAMPLED_IMAGE_FILTER_LINEAR}) == {} {
		compare_filter = .NEAREST
	}

	compare_info := vk.SamplerCreateInfo {
		sType = .SAMPLER_CREATE_INFO,
		magFilter = compare_filter,
		minFilter = compare_filter,
		mipmapMode = .NEAREST,
		addressModeU = .CLAMP_TO_BORDER,
		addressModeV = .CLAMP_TO_BORDER,
		addressModeW = .CLAMP_TO_BORDER,
		compareEnable = true,
		compareOp = .LESS_OR_EQUAL,
		maxLod = 0,
		borderColor = .FLOAT_OPAQUE_WHITE,
	}
	if !check(vk.CreateSampler(r.device, &compare_info, nil, &r.shadow.compare_sampler), "vkCreateSampler") {
		return false
	}

	depth_info := vk.SamplerCreateInfo {
		sType = .SAMPLER_CREATE_INFO,
		magFilter = .NEAREST,
		minFilter = .NEAREST,
		mipmapMode = .NEAREST,
		addressModeU = .CLAMP_TO_BORDER,
		addressModeV = .CLAMP_TO_BORDER,
		addressModeW = .CLAMP_TO_BORDER,
		maxLod = 0,
		borderColor = .FLOAT_OPAQUE_WHITE,
	}
	if !check(vk.CreateSampler(r.device, &depth_info, nil, &r.shadow.depth_sampler), "vkCreateSampler") {
		return false
	}

	// Filled from the runtime sun before the first shadow pass.
	r.shadow.light_view_projection = MAT4_IDENTITY
	write_shadow_descriptors(r)
	return create_shadow_pipeline(r)
}

write_shadow_descriptors :: proc(r: ^Renderer) {
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		image_infos := [2]vk.DescriptorImageInfo {
			{
				sampler = r.shadow.compare_sampler,
				imageView = r.shadow.images[i].view,
				imageLayout = .SHADER_READ_ONLY_OPTIMAL,
			},
			{
				sampler = r.shadow.depth_sampler,
				imageView = r.shadow.images[i].view,
				imageLayout = .SHADER_READ_ONLY_OPTIMAL,
			},
		}
		writes := [2]vk.WriteDescriptorSet {
			{
				sType = .WRITE_DESCRIPTOR_SET,
				dstSet = r.scene.descriptor_sets[i],
				dstBinding = SHADOW_MAP_BINDING,
				descriptorCount = 1,
				descriptorType = .COMBINED_IMAGE_SAMPLER,
				pImageInfo = &image_infos[0],
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				dstSet = r.scene.descriptor_sets[i],
				dstBinding = SHADOW_DEPTH_BINDING,
				descriptorCount = 1,
				descriptorType = .COMBINED_IMAGE_SAMPLER,
				pImageInfo = &image_infos[1],
			},
		}
		vk.UpdateDescriptorSets(r.device, u32(len(writes)), &writes[0], 0, nil)
	}
}

create_shadow_pipeline :: proc(r: ^Renderer) -> bool {
	set_layouts := [1]vk.DescriptorSetLayout{r.scene.descriptor_set_layout}
	attributes := [1]vk.VertexInputAttributeDescription {
		{location = 0, binding = 0, format = .R32G32B32_SFLOAT, offset = 0},
	}
	return create_graphics_pipeline(
		r,
		{
			name = "shadow",
			vertex_spirv = SHADOW_VERTEX_SPIRV,
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
			depth_format = DEPTH_FORMAT,
			depth_test = true,
			depth_write = true,
			dynamic_viewport = true,
			dynamic_scissor = true,
		},
		&r.shadow.pipeline,
		&r.shadow.pipeline_layout,
	)
}

destroy_shadow :: proc(r: ^Renderer) {
	if r.device == nil {
		return
	}
	destroy_pipeline_pair(r, &r.shadow.pipeline, &r.shadow.pipeline_layout)
	for &image in r.shadow.images {
		destroy_image(r, &image)
	}
	if r.shadow.compare_sampler != 0 {
		vk.DestroySampler(r.device, r.shadow.compare_sampler, nil)
		r.shadow.compare_sampler = 0
	}
	if r.shadow.depth_sampler != 0 {
		vk.DestroySampler(r.device, r.shadow.depth_sampler, nil)
		r.shadow.depth_sampler = 0
	}
}

record_shadow_pass :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, boxes: []geometry.Box) {
	frame_index := r.frame_index
	record_depth_write_barrier(command_buffer, r.shadow.images[frame_index].image)
	depth_attachment := make_depth_attachment(r.shadow.images[frame_index].view, .DEPTH_ATTACHMENT_OPTIMAL)
	extent := vk.Extent2D{width = SHADOW_MAP_SIZE, height = SHADOW_MAP_SIZE}
	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {extent = extent},
		layerCount = 1,
		pDepthAttachment = &depth_attachment,
	}
	vk.CmdBeginRendering(command_buffer, &rendering_info)

	set_viewport(command_buffer, SHADOW_MAP_SIZE, SHADOW_MAP_SIZE)

	vk.CmdBindPipeline(command_buffer, .GRAPHICS, r.shadow.pipeline)
	bind_camera(command_buffer, r.shadow.pipeline_layout, r.scene.descriptor_sets[frame_index])

	draw_boxes(r, command_buffer, r.shadow.pipeline_layout, boxes)

	vk.CmdEndRendering(command_buffer)

	to_sample := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		srcAccessMask = {.DEPTH_STENCIL_ATTACHMENT_WRITE},
		dstAccessMask = {.SHADER_READ},
		oldLayout = .DEPTH_ATTACHMENT_OPTIMAL,
		newLayout = .SHADER_READ_ONLY_OPTIMAL,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = r.shadow.images[frame_index].image,
		subresourceRange = DEPTH_SUBRESOURCE,
	}
	vk.CmdPipelineBarrier(
		command_buffer,
		{.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS},
		{.FRAGMENT_SHADER},
		{},
		0,
		nil,
		0,
		nil,
		1,
		&to_sample,
	)
}
