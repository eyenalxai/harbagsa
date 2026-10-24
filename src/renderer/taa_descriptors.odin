#+vet explicit-allocators
package renderer

import "core:log"

import vk "vendor:vulkan"

create_taa_descriptors :: proc(r: ^Renderer) -> bool {
	bindings := [4]vk.DescriptorSetLayoutBinding {
		{
			binding = 0,
			descriptorType = .COMBINED_IMAGE_SAMPLER,
			descriptorCount = 1,
			stageFlags = {.FRAGMENT},
		},
		{
			binding = 1,
			descriptorType = .COMBINED_IMAGE_SAMPLER,
			descriptorCount = 1,
			stageFlags = {.FRAGMENT},
		},
		{
			binding = 2,
			descriptorType = .COMBINED_IMAGE_SAMPLER,
			descriptorCount = 1,
			stageFlags = {.FRAGMENT},
		},
		{
			binding = 3,
			descriptorType = .COMBINED_IMAGE_SAMPLER,
			descriptorCount = 1,
			stageFlags = {.FRAGMENT},
		},
	}
	layout_info := vk.DescriptorSetLayoutCreateInfo {
		sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = u32(len(bindings)),
		pBindings = &bindings[0],
	}
	if !check(
		vk.CreateDescriptorSetLayout(r.device, &layout_info, nil, &r.taa.descriptor_set_layout),
		"vkCreateDescriptorSetLayout",
	) {
		return false
	}

	pool_size := vk.DescriptorPoolSize {
		type = .COMBINED_IMAGE_SAMPLER,
		descriptorCount = TAA_DESCRIPTOR_SETS * u32(len(bindings)),
	}
	pool_info := vk.DescriptorPoolCreateInfo {
		sType = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets = TAA_DESCRIPTOR_SETS,
		poolSizeCount = 1,
		pPoolSizes = &pool_size,
	}
	if !check(vk.CreateDescriptorPool(r.device, &pool_info, nil, &r.taa.descriptor_pool), "vkCreateDescriptorPool") {
		return false
	}

	for i in 0 ..< TAA_DESCRIPTOR_SETS {
		allocate_info := vk.DescriptorSetAllocateInfo {
			sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
			descriptorPool = r.taa.descriptor_pool,
			descriptorSetCount = 1,
			pSetLayouts = &r.taa.descriptor_set_layout,
		}
		if !check(
			vk.AllocateDescriptorSets(r.device, &allocate_info, &r.taa.descriptor_sets[i]),
			"vkAllocateDescriptorSets",
		) {
			return false
		}
	}

	return write_taa_descriptors(r)
}

write_taa_descriptors :: proc(r: ^Renderer) -> bool {
	taa := &r.taa
	if taa.descriptor_set_layout == 0 || taa.descriptor_pool == 0 {
		return false
	}

	for frame in 0 ..< MAX_FRAMES_IN_FLIGHT {
		for read in 0 ..< TAA_HISTORY_IMAGES {
			set := taa.descriptor_sets[frame * TAA_HISTORY_IMAGES + read]
			if set == 0 {
				log.error("renderer: TAA descriptor set is not allocated")
				return false
			}

			images := [4]vk.DescriptorImageInfo {
				{
					sampler = taa.sampler,
					imageView = taa.scene_color[frame].view,
					imageLayout = .SHADER_READ_ONLY_OPTIMAL,
				},
				{
					sampler = taa.sampler,
					imageView = taa.velocity[frame].view,
					imageLayout = .SHADER_READ_ONLY_OPTIMAL,
				},
				{
					sampler = taa.sampler,
					imageView = taa.history[read].view,
					imageLayout = .SHADER_READ_ONLY_OPTIMAL,
				},
				{
					sampler = taa.sampler,
					imageView = taa.counts[read].view,
					imageLayout = .SHADER_READ_ONLY_OPTIMAL,
				},
			}
			writes := [4]vk.WriteDescriptorSet {
				{
					sType = .WRITE_DESCRIPTOR_SET,
					dstSet = set,
					dstBinding = 0,
					descriptorCount = 1,
					descriptorType = .COMBINED_IMAGE_SAMPLER,
					pImageInfo = &images[0],
				},
				{
					sType = .WRITE_DESCRIPTOR_SET,
					dstSet = set,
					dstBinding = 1,
					descriptorCount = 1,
					descriptorType = .COMBINED_IMAGE_SAMPLER,
					pImageInfo = &images[1],
				},
				{
					sType = .WRITE_DESCRIPTOR_SET,
					dstSet = set,
					dstBinding = 2,
					descriptorCount = 1,
					descriptorType = .COMBINED_IMAGE_SAMPLER,
					pImageInfo = &images[2],
				},
				{
					sType = .WRITE_DESCRIPTOR_SET,
					dstSet = set,
					dstBinding = 3,
					descriptorCount = 1,
					descriptorType = .COMBINED_IMAGE_SAMPLER,
					pImageInfo = &images[3],
				},
			}
			vk.UpdateDescriptorSets(r.device, u32(len(writes)), &writes[0], 0, nil)
		}
	}
	return true
}
