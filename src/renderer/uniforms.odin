#+vet explicit-allocators
package renderer

import vk "vendor:vulkan"

MAX_SCENE_BOXES :: 256

// The uniform block mirrors camera.glsl. Mat4 is column-major, so the
// matrices upload directly. screen carries the gamma flag in .x, the render
// extent in .y and .z, and the TAA sample phase in .w. sun.x is the tangent
// of the sun angular radius, sun.y the camera far plane, so the sky pass
// writes the same depth as the velocity clear, sun.z the point light count,
// and sun.w the point-light shadow flag. occlusion.x is the AO radius in
// metres, y the strength, and z the enabled flag.
Camera_Uniform :: struct {
	view:                 Mat4,
	projection:           Mat4,
	prev_view_projection: Mat4,
	light_direction:      [4]f32,
	screen:               [4]f32,
	sun:                  [4]f32,
	jitter:               [4]f32,
	occlusion:            [4]f32,
}

// color.rgb is the box colour and color.a the emissive strength.
Object_Data :: struct {
	model:      Mat4,
	prev_model: Mat4,
	color:      [4]f32,
}

Object_Index :: struct {
	index: u32,
}

TAA_Params :: struct {
	gamma:          f32,
	history_valid:  f32,
	max_samples:    f32,
	history_weight: f32,
	clamp_enabled:  f32,
	force_trust:    f32,
}

#assert(size_of(Camera_Uniform) == 272)
#assert(size_of(Object_Data) == 144)
#assert(size_of(Object_Index) == 4)
#assert(size_of(TAA_Params) == 24)

CAMERA_BINDING :: 0
OBJECT_BINDING :: 1
ACCELERATION_BINDING :: 2
LIGHT_BINDING :: 3

create_scene_resources :: proc(r: ^Renderer) -> bool {
	bindings := [4]vk.DescriptorSetLayoutBinding {
		{
			binding = CAMERA_BINDING,
			descriptorType = .UNIFORM_BUFFER,
			descriptorCount = 1,
			stageFlags = {.VERTEX, .FRAGMENT},
		},
		{
			binding = OBJECT_BINDING,
			descriptorType = .STORAGE_BUFFER,
			descriptorCount = 1,
			stageFlags = {.VERTEX, .FRAGMENT},
		},
		{
			binding = ACCELERATION_BINDING,
			descriptorType = .ACCELERATION_STRUCTURE_KHR,
			descriptorCount = 1,
			stageFlags = {.FRAGMENT},
		},
		{
			binding = LIGHT_BINDING,
			descriptorType = .STORAGE_BUFFER,
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
		vk.CreateDescriptorSetLayout(r.device, &layout_info, nil, &r.scene.descriptor_set_layout),
		"vkCreateDescriptorSetLayout",
	) {
		return false
	}

	pool_sizes := [3]vk.DescriptorPoolSize {
		{type = .UNIFORM_BUFFER, descriptorCount = MAX_FRAMES_IN_FLIGHT},
		{type = .STORAGE_BUFFER, descriptorCount = MAX_FRAMES_IN_FLIGHT * 2},
		{type = .ACCELERATION_STRUCTURE_KHR, descriptorCount = MAX_FRAMES_IN_FLIGHT},
	}
	pool_info := vk.DescriptorPoolCreateInfo {
		sType = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets = MAX_FRAMES_IN_FLIGHT,
		poolSizeCount = u32(len(pool_sizes)),
		pPoolSizes = &pool_sizes[0],
	}
	if !check(vk.CreateDescriptorPool(r.device, &pool_info, nil, &r.scene.descriptor_pool), "vkCreateDescriptorPool") {
		return false
	}

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
		if !create_mapped_buffer(
			r,
			vk.DeviceSize(MAX_SCENE_BOXES * size_of(Object_Data)),
			{.STORAGE_BUFFER},
			&r.scene.object_buffers[i],
			&r.scene.object_memory[i],
			&r.scene.object_mapped[i],
		) {
			return false
		}
		if !create_mapped_buffer(
			r,
			vk.DeviceSize(MAX_POINT_LIGHTS * size_of(Light)),
			{.STORAGE_BUFFER},
			&r.scene.light_buffers[i],
			&r.scene.light_memory[i],
			&r.scene.light_mapped[i],
		) {
			return false
		}

		buffer_infos := [3]vk.DescriptorBufferInfo {
			{
				buffer = r.scene.camera_buffers[i],
				offset = 0,
				range = vk.DeviceSize(size_of(Camera_Uniform)),
			},
			{
				buffer = r.scene.object_buffers[i],
				offset = 0,
				range = vk.DeviceSize(MAX_SCENE_BOXES * size_of(Object_Data)),
			},
			{
				buffer = r.scene.light_buffers[i],
				offset = 0,
				range = vk.DeviceSize(MAX_POINT_LIGHTS * size_of(Light)),
			},
		}
		writes := [3]vk.WriteDescriptorSet {
			{
				sType = .WRITE_DESCRIPTOR_SET,
				dstSet = r.scene.descriptor_sets[i],
				dstBinding = CAMERA_BINDING,
				descriptorCount = 1,
				descriptorType = .UNIFORM_BUFFER,
				pBufferInfo = &buffer_infos[0],
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				dstSet = r.scene.descriptor_sets[i],
				dstBinding = OBJECT_BINDING,
				descriptorCount = 1,
				descriptorType = .STORAGE_BUFFER,
				pBufferInfo = &buffer_infos[1],
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				dstSet = r.scene.descriptor_sets[i],
				dstBinding = LIGHT_BINDING,
				descriptorCount = 1,
				descriptorType = .STORAGE_BUFFER,
				pBufferInfo = &buffer_infos[2],
			},
		}
		vk.UpdateDescriptorSets(r.device, u32(len(writes)), &writes[0], 0, nil)
	}

	return true
}
