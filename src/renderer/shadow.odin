#+vet explicit-allocators
package renderer

import "core:math/linalg"

import "src:geometry"
import vk "vendor:vulkan"

SHADOW_MAP_SIZE :: 2048
LIGHT_VOLUME_RADIUS :: 30.0
LIGHT_VOLUME_DEPTH :: 60.0
LIGHT_VOLUME_CENTER :: [3]f32{0, 1.5, 0}

SHADOW_VERTEX_SPIRV :: #load("../../build/shaders/shadow.vert.spv")

Shadow :: struct {
	images:                [MAX_FRAMES_IN_FLIGHT]Image,
	sampler:               vk.Sampler,
	pipeline:              vk.Pipeline,
	pipeline_layout:       vk.PipelineLayout,
	light_view_projection: Mat4,
}

// The sun never moves, so one fixed orthographic box covers the arena.
shadow_light_matrix :: proc() -> Mat4 {
	to_light := -linalg.vector_normalize0(LIGHT_DIRECTION)
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

	sampler_info := vk.SamplerCreateInfo {
		sType = .SAMPLER_CREATE_INFO,
		magFilter = .NEAREST,
		minFilter = .NEAREST,
		mipmapMode = .NEAREST,
		addressModeU = .CLAMP_TO_BORDER,
		addressModeV = .CLAMP_TO_BORDER,
		addressModeW = .CLAMP_TO_BORDER,
		compareEnable = true,
		compareOp = .LESS_OR_EQUAL,
		maxLod = 0,
		borderColor = .FLOAT_OPAQUE_WHITE,
	}
	if !check(vk.CreateSampler(r.device, &sampler_info, nil, &r.shadow.sampler), "vkCreateSampler") {
		return false
	}

	r.shadow.light_view_projection = shadow_light_matrix()
	write_shadow_descriptors(r)
	return create_shadow_pipeline(r)
}

write_shadow_descriptors :: proc(r: ^Renderer) {
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		image_info := vk.DescriptorImageInfo {
			sampler = r.shadow.sampler,
			imageView = r.shadow.images[i].view,
			imageLayout = .SHADER_READ_ONLY_OPTIMAL,
		}
		write := vk.WriteDescriptorSet {
			sType = .WRITE_DESCRIPTOR_SET,
			dstSet = r.scene.descriptor_sets[i],
			dstBinding = 1,
			descriptorCount = 1,
			descriptorType = .COMBINED_IMAGE_SAMPLER,
			pImageInfo = &image_info,
		}
		vk.UpdateDescriptorSets(r.device, 1, &write, 0, nil)
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
	if r.shadow.sampler != 0 {
		vk.DestroySampler(r.device, r.shadow.sampler, nil)
		r.shadow.sampler = 0
	}
}

record_shadow_pass :: proc(
	r: ^Renderer,
	command_buffer: vk.CommandBuffer,
	frame_index: int,
	boxes: []geometry.Box,
) {
	to_depth := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		dstAccessMask = {.DEPTH_STENCIL_ATTACHMENT_WRITE},
		oldLayout = .UNDEFINED,
		newLayout = .DEPTH_ATTACHMENT_OPTIMAL,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = r.shadow.images[frame_index].image,
		subresourceRange = DEPTH_SUBRESOURCE,
	}
	vk.CmdPipelineBarrier(
		command_buffer,
		{.TOP_OF_PIPE},
		{.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS},
		{},
		0,
		nil,
		0,
		nil,
		1,
		&to_depth,
	)

	clear_depth := vk.ClearValue{}
	clear_depth.depthStencil = {depth = 1.0, stencil = 0}
	depth_attachment := vk.RenderingAttachmentInfo {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = r.shadow.images[frame_index].view,
		imageLayout = .DEPTH_ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .STORE,
		clearValue = clear_depth,
	}
	extent := vk.Extent2D{width = SHADOW_MAP_SIZE, height = SHADOW_MAP_SIZE}
	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {extent = extent},
		layerCount = 1,
		pDepthAttachment = &depth_attachment,
	}
	vk.CmdBeginRendering(command_buffer, &rendering_info)

	viewport := vk.Viewport {
		width = SHADOW_MAP_SIZE,
		height = SHADOW_MAP_SIZE,
		minDepth = 0,
		maxDepth = 1,
	}
	scissor := vk.Rect2D{extent = extent}
	vk.CmdSetViewport(command_buffer, 0, 1, &viewport)
	vk.CmdSetScissor(command_buffer, 0, 1, &scissor)

	vk.CmdBindPipeline(command_buffer, .GRAPHICS, r.shadow.pipeline)
	descriptor_set := r.scene.descriptor_sets[frame_index]
	vk.CmdBindDescriptorSets(
		command_buffer,
		.GRAPHICS,
		r.shadow.pipeline_layout,
		0,
		1,
		&descriptor_set,
		0,
		nil,
	)

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
