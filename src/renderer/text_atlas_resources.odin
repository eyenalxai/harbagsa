#+vet explicit-allocators
package renderer

import "core:log"

import vk "vendor:vulkan"

TEXT_ATLAS_BINDING :: 0

// The atlas changes only when the UI density does, so one sampler and one
// descriptor set outlive the texture they read.
init_text_atlas_resources :: proc(r: ^Renderer) -> bool {
	if !text_atlas_rebuild(r) {
		return false
	}

	sampler_info := vk.SamplerCreateInfo {
		sType        = .SAMPLER_CREATE_INFO,
		magFilter    = .LINEAR,
		minFilter    = .LINEAR,
		mipmapMode   = .NEAREST,
		addressModeU = .CLAMP_TO_EDGE,
		addressModeV = .CLAMP_TO_EDGE,
		addressModeW = .CLAMP_TO_EDGE,
		maxLod       = 0,
	}
	if !check(vk.CreateSampler(r.device, &sampler_info, nil, &r.overlay.atlas_sampler), "vkCreateSampler") {
		return false
	}

	bindings := [1]vk.DescriptorSetLayoutBinding {
		{
			binding = TEXT_ATLAS_BINDING,
			descriptorType = .COMBINED_IMAGE_SAMPLER,
			descriptorCount = 1,
			stageFlags = {.FRAGMENT},
		},
	}
	layout_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = u32(len(bindings)),
		pBindings    = &bindings[0],
	}
	if !check(
		vk.CreateDescriptorSetLayout(r.device, &layout_info, nil, &r.overlay.atlas_layout),
		"vkCreateDescriptorSetLayout",
	) {
		return false
	}

	pool_size := vk.DescriptorPoolSize {
		type            = .COMBINED_IMAGE_SAMPLER,
		descriptorCount = 1,
	}
	pool_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets       = 1,
		poolSizeCount = 1,
		pPoolSizes    = &pool_size,
	}
	if !check(vk.CreateDescriptorPool(r.device, &pool_info, nil, &r.overlay.atlas_pool), "vkCreateDescriptorPool") {
		return false
	}

	allocate := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = r.overlay.atlas_pool,
		descriptorSetCount = 1,
		pSetLayouts        = &r.overlay.atlas_layout,
	}
	if !check(vk.AllocateDescriptorSets(r.device, &allocate, &r.overlay.atlas_set), "vkAllocateDescriptorSets") {
		return false
	}
	text_atlas_bind(r)
	return true
}

// Repacks the atlas for the overlay's current theme and points the descriptor at
// the new texture. Rebuilding mid-run needs an idle device, because the old
// image may still be sampled by a frame in flight; init has nothing in flight.
text_atlas_rebuild :: proc(r: ^Renderer) -> bool {
	o := &r.overlay
	set := text_theme_layer_set(o.theme)
	atlas, built := text_atlas_build(r.allocator, &set)
	if !built {
		return false
	}
	text_atlas_destroy(&o.atlas, r.allocator)
	o.atlas = atlas

	destroy_image(r, &o.atlas_image)
	image, uploaded := upload_texture(r, atlas.width, atlas.height, .R8_UNORM, atlas.pixels)
	if !uploaded {
		return false
	}
	o.atlas_image = image
	if o.atlas_set != 0 {
		text_atlas_bind(r)
	}
	return true
}

text_atlas_sync :: proc(r: ^Renderer) -> bool {
	if text_atlas_covers(&r.overlay.atlas, text_theme_layer_set(r.overlay.theme)) {
		return true
	}
	if !check(vk.DeviceWaitIdle(r.device), "vkDeviceWaitIdle") {
		return false
	}
	if !text_atlas_rebuild(r) {
		return false
	}
	log.infof("text atlas: rebuilt for %d UI layers", r.overlay.atlas.count)
	return true
}

@(private)
text_atlas_bind :: proc(r: ^Renderer) {
	o := &r.overlay
	descriptor := vk.DescriptorImageInfo {
		sampler     = o.atlas_sampler,
		imageView   = o.atlas_image.view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}
	write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstSet          = o.atlas_set,
		dstBinding      = TEXT_ATLAS_BINDING,
		descriptorCount = 1,
		descriptorType  = .COMBINED_IMAGE_SAMPLER,
		pImageInfo      = &descriptor,
	}
	vk.UpdateDescriptorSets(r.device, 1, &write, 0, nil)
}

destroy_text_atlas_resources :: proc(r: ^Renderer) {
	overlay := &r.overlay
	if r.device != nil {
		if overlay.atlas_pool != 0 {
			vk.DestroyDescriptorPool(r.device, overlay.atlas_pool, nil)
			overlay.atlas_pool = 0
			overlay.atlas_set = 0
		}
		if overlay.atlas_layout != 0 {
			vk.DestroyDescriptorSetLayout(r.device, overlay.atlas_layout, nil)
			overlay.atlas_layout = 0
		}
		if overlay.atlas_sampler != 0 {
			vk.DestroySampler(r.device, overlay.atlas_sampler, nil)
			overlay.atlas_sampler = 0
		}
		destroy_image(r, &overlay.atlas_image)
	}
	text_atlas_destroy(&overlay.atlas, r.allocator)
}
