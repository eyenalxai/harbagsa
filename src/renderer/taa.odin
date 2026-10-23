#+vet explicit-allocators
package renderer

import "core:log"

import vk "vendor:vulkan"

SCENE_COLOR_FORMAT :: vk.Format.R16G16B16A16_SFLOAT
VELOCITY_FORMAT :: vk.Format.R16G16B16A16_SFLOAT
HISTORY_FORMAT :: vk.Format.R16G16B16A16_SFLOAT

TAA_HISTORY_IMAGES :: 2
TAA_DESCRIPTOR_SETS :: MAX_FRAMES_IN_FLIGHT * TAA_HISTORY_IMAGES

TAA :: struct {
	targets_extent: vk.Extent2D,

	prev_models:              [MAX_SCENE_BOXES]Mat4,
	prev_model_count:         int,
	prev_view_projection:     Mat4,
	has_prev_view_projection: bool,

	depth:       [MAX_FRAMES_IN_FLIGHT]Image,
	scene_color: [MAX_FRAMES_IN_FLIGHT]Image,
	velocity:    [MAX_FRAMES_IN_FLIGHT]Image,
	history:     [TAA_HISTORY_IMAGES]Image,

	history_read:    int,
	history_valid:   bool,
	history_layouts: [TAA_HISTORY_IMAGES]vk.ImageLayout,

	sampler:               vk.Sampler,
	descriptor_set_layout: vk.DescriptorSetLayout,
	descriptor_pool:       vk.DescriptorPool,
	descriptor_sets:       [TAA_DESCRIPTOR_SETS]vk.DescriptorSet,

	pipeline:        vk.Pipeline,
	pipeline_layout: vk.PipelineLayout,
	pipeline_format: vk.Format,
}

init_taa :: proc(r: ^Renderer) -> Error {
	if !check_taa_formats(r) {
		return .Create_TAA
	}
	if !create_taa_targets(r) {
		return .Create_TAA
	}
	if !create_taa_sampler(r) {
		return .Create_TAA
	}
	if !create_taa_descriptors(r) {
		return .Create_TAA
	}
	if !create_taa_pipeline(r) {
		return .Create_TAA
	}
	return .None
}

destroy_taa :: proc(r: ^Renderer) {
	if r.device != nil {
		destroy_pipeline_pair(r, &r.taa.pipeline, &r.taa.pipeline_layout)
		if r.taa.descriptor_pool != 0 {
			vk.DestroyDescriptorPool(r.device, r.taa.descriptor_pool, nil)
			r.taa.descriptor_pool = 0
		}
		if r.taa.descriptor_set_layout != 0 {
			vk.DestroyDescriptorSetLayout(r.device, r.taa.descriptor_set_layout, nil)
			r.taa.descriptor_set_layout = 0
		}
		if r.taa.sampler != 0 {
			vk.DestroySampler(r.device, r.taa.sampler, nil)
			r.taa.sampler = 0
		}
	}
	destroy_taa_targets(r)
}

check_taa_formats :: proc(r: ^Renderer) -> bool {
	required := vk.FormatFeatureFlags{.COLOR_ATTACHMENT, .SAMPLED_IMAGE, .SAMPLED_IMAGE_FILTER_LINEAR}
	formats := [3]vk.Format{SCENE_COLOR_FORMAT, VELOCITY_FORMAT, HISTORY_FORMAT}
	for format in formats {
		properties: vk.FormatProperties
		vk.GetPhysicalDeviceFormatProperties(r.physical_device, format, &properties)
		if (properties.optimalTilingFeatures & required) != required {
			log.errorf("renderer: format %v lacks the TAA color, sample, or filter features", format)
			return false
		}
	}
	return true
}

create_taa_targets :: proc(r: ^Renderer) -> bool {
	destroy_taa_targets(r)

	extent := r.swapchain_extent
	if extent.width == 0 || extent.height == 0 {
		log.error("renderer: cannot create TAA targets without a swapchain extent")
		return false
	}

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		depth, depth_ok := create_image(
			r,
			extent.width,
			extent.height,
			DEPTH_FORMAT,
			{.DEPTH_STENCIL_ATTACHMENT},
			{.DEPTH},
		)
		if !depth_ok {
			destroy_taa_targets(r)
			return false
		}
		r.taa.depth[i] = depth

		color, color_ok := create_image(
			r,
			extent.width,
			extent.height,
			SCENE_COLOR_FORMAT,
			{.COLOR_ATTACHMENT, .SAMPLED},
			{.COLOR},
		)
		if !color_ok {
			destroy_taa_targets(r)
			return false
		}
		r.taa.scene_color[i] = color

		velocity, velocity_ok := create_image(
			r,
			extent.width,
			extent.height,
			VELOCITY_FORMAT,
			{.COLOR_ATTACHMENT, .SAMPLED},
			{.COLOR},
		)
		if !velocity_ok {
			destroy_taa_targets(r)
			return false
		}
		r.taa.velocity[i] = velocity
	}

	for i in 0 ..< TAA_HISTORY_IMAGES {
		history, history_ok := create_image(
			r,
			extent.width,
			extent.height,
			HISTORY_FORMAT,
			{.COLOR_ATTACHMENT, .SAMPLED},
			{.COLOR},
		)
		if !history_ok {
			destroy_taa_targets(r)
			return false
		}
		r.taa.history[i] = history
	}

	r.taa.targets_extent = extent
	r.taa.prev_model_count = 0
	r.taa.has_prev_view_projection = false
	r.taa.history_read = 0
	r.taa.history_valid = false
	r.taa.history_layouts = {.UNDEFINED, .UNDEFINED}
	return true
}

destroy_taa_targets :: proc(r: ^Renderer) {
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		destroy_image(r, &r.taa.depth[i])
		destroy_image(r, &r.taa.scene_color[i])
		destroy_image(r, &r.taa.velocity[i])
	}
	for i in 0 ..< TAA_HISTORY_IMAGES {
		destroy_image(r, &r.taa.history[i])
	}
	r.taa.targets_extent = {}
	r.taa.history_valid = false
	r.taa.history_layouts = {.UNDEFINED, .UNDEFINED}
}

create_taa_sampler :: proc(r: ^Renderer) -> bool {
	info := vk.SamplerCreateInfo {
		sType        = .SAMPLER_CREATE_INFO,
		magFilter    = .LINEAR,
		minFilter    = .LINEAR,
		mipmapMode   = .NEAREST,
		addressModeU = .CLAMP_TO_EDGE,
		addressModeV = .CLAMP_TO_EDGE,
		addressModeW = .CLAMP_TO_EDGE,
		maxLod       = 0,
	}
	return check(vk.CreateSampler(r.device, &info, nil, &r.taa.sampler), "vkCreateSampler")
}
