#+vet explicit-allocators
package renderer

import vk "vendor:vulkan"

// The uniform block mirrors the GLSL Camera block in both shader stages.
// Mat4 is column-major, so the view and projection matrices upload directly.
Camera_Uniform :: struct {
	view:            Mat4,
	projection:      Mat4,
	light_direction: [4]f32,
	ambient:         [4]f32,
	gamma:           [4]f32,
}

// The push constant block mirrors the GLSL PushConstants block in the vertex
// shader. The color travels to the fragment stage as a varying.
Push_Constants :: struct {
	model: Mat4,
	color: [4]f32,
}

#assert(size_of(Camera_Uniform) == 176)
#assert(size_of(Push_Constants) == 80)

create_camera_resources :: proc(r: ^Renderer) -> bool {
	binding := vk.DescriptorSetLayoutBinding {
		binding = 0,
		descriptorType = .UNIFORM_BUFFER,
		descriptorCount = 1,
		stageFlags = {.VERTEX, .FRAGMENT},
	}
	layout_info := vk.DescriptorSetLayoutCreateInfo {
		sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 1,
		pBindings = &binding,
	}
	if !check(
		vk.CreateDescriptorSetLayout(r.device, &layout_info, nil, &r.scene.descriptor_set_layout),
		"vkCreateDescriptorSetLayout",
	) {
		return false
	}

	pool_size := vk.DescriptorPoolSize {
		type = .UNIFORM_BUFFER,
		descriptorCount = MAX_FRAMES_IN_FLIGHT,
	}
	pool_info := vk.DescriptorPoolCreateInfo {
		sType = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets = MAX_FRAMES_IN_FLIGHT,
		poolSizeCount = 1,
		pPoolSizes = &pool_size,
	}
	if !check(vk.CreateDescriptorPool(r.device, &pool_info, nil, &r.scene.descriptor_pool), "vkCreateDescriptorPool") {
		return false
	}

	// One set per frame matches the per-frame camera buffer.
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		allocate_info := vk.DescriptorSetAllocateInfo {
			sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
			descriptorPool = r.scene.descriptor_pool,
			descriptorSetCount = 1,
			pSetLayouts = &r.scene.descriptor_set_layout,
		}
		if !check(
			vk.AllocateDescriptorSets(r.device, &allocate_info, &r.scene.descriptor_sets[i]),
			"vkAllocateDescriptorSets",
		) {
			return false
		}
	}

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		if !create_mapped_buffer(
			r,
			vk.DeviceSize(size_of(Camera_Uniform)),
			{.UNIFORM_BUFFER},
			&r.scene.camera_buffers[i],
			&r.scene.camera_memory[i],
			&r.scene.camera_mapped[i],
		) {
			return false
		}

		buffer_info := vk.DescriptorBufferInfo {
			buffer = r.scene.camera_buffers[i],
			offset = 0,
			range = vk.DeviceSize(size_of(Camera_Uniform)),
		}
		write := vk.WriteDescriptorSet {
			sType = .WRITE_DESCRIPTOR_SET,
			dstSet = r.scene.descriptor_sets[i],
			dstBinding = 0,
			descriptorCount = 1,
			descriptorType = .UNIFORM_BUFFER,
			pBufferInfo = &buffer_info,
		}
		vk.UpdateDescriptorSets(r.device, 1, &write, 0, nil)
	}

	return true
}
