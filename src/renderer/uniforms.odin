#+vet explicit-allocators
package renderer

import "core:mem"

import vk "vendor:vulkan"

// Initial capacities. The buffers grow on demand; these are not limits.
INITIAL_SCENE_OBJECT_CAPACITY :: 512
INITIAL_POINT_LIGHT_CAPACITY :: 64

// Cluster grid. The shader constants live in shaders/cluster.glsl and must
// match these.
CLUSTER_X :: 16
CLUSTER_Y :: 9
CLUSTER_Z :: 24
CLUSTER_COUNT :: CLUSTER_X * CLUSTER_Y * CLUSTER_Z
CLUSTER_LIGHT_STRIDE :: 256
CLUSTER_LOCAL_SIZE :: 64
// The counts buffer holds one count per cluster plus one overflow counter.
CLUSTER_COUNTS_SIZE :: (CLUSTER_COUNT + 1) * size_of(u32)

// The uniform block mirrors camera.glsl. Mat4 is column-major, so the
// matrices upload directly. screen carries the gamma flag in .x, the render
// extent in .y and .z, and the TAA sample phase in .w. sun.x is the tangent
// of the sun angular radius, sun.y the camera far plane, so the sky pass
// writes the same depth as the velocity clear, sun.z the point light count,
// and sun.w the point-light shadow flag. occlusion.x is the AO radius in
// metres, y the strength, z the enabled flag, and w the plan-view clip height.
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
CLUSTER_COUNTS_BINDING :: 4
CLUSTER_INDICES_BINDING :: 5

create_scene_resources :: proc(r: ^Renderer) -> bool {
	bindings := [6]vk.DescriptorSetLayoutBinding {
		{
			binding = CAMERA_BINDING,
			descriptorType = .UNIFORM_BUFFER,
			descriptorCount = 1,
			stageFlags = {.VERTEX, .FRAGMENT, .COMPUTE},
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
			stageFlags = {.FRAGMENT, .COMPUTE},
		},
		{
			binding = CLUSTER_COUNTS_BINDING,
			descriptorType = .STORAGE_BUFFER,
			descriptorCount = 1,
			stageFlags = {.FRAGMENT, .COMPUTE},
		},
		{
			binding = CLUSTER_INDICES_BINDING,
			descriptorType = .STORAGE_BUFFER,
			descriptorCount = 1,
			stageFlags = {.FRAGMENT, .COMPUTE},
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
		{type = .STORAGE_BUFFER, descriptorCount = MAX_FRAMES_IN_FLIGHT * 4},
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

	if !create_scene_frame_buffers(
		r,
		INITIAL_SCENE_OBJECT_CAPACITY,
		INITIAL_POINT_LIGHT_CAPACITY,
	) {
		return false
	}
	write_scene_bindings(r)
	return true
}

@(private)
create_scene_frame_buffers :: proc(
	r: ^Renderer,
	object_capacity, light_capacity: int,
) -> bool {
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
			vk.DeviceSize(object_capacity * size_of(Object_Data)),
			{.STORAGE_BUFFER},
			&r.scene.object_buffers[i],
			&r.scene.object_memory[i],
			&r.scene.object_mapped[i],
		) {
			return false
		}
		if !create_mapped_buffer(
			r,
			vk.DeviceSize(light_capacity * size_of(Light)),
			{.STORAGE_BUFFER},
			&r.scene.light_buffers[i],
			&r.scene.light_memory[i],
			&r.scene.light_mapped[i],
		) {
			return false
		}
		if !create_mapped_buffer(
			r,
			vk.DeviceSize(CLUSTER_COUNTS_SIZE),
			{.STORAGE_BUFFER, .TRANSFER_DST},
			&r.scene.cluster_counts_buffers[i],
			&r.scene.cluster_counts_memory[i],
			&r.scene.cluster_counts_mapped[i],
		) {
			return false
		}
		counts := cast([^]u32)r.scene.cluster_counts_mapped[i]
		mem.set(rawptr(counts), 0, CLUSTER_COUNTS_SIZE)
		if !create_mapped_buffer(
			r,
			vk.DeviceSize(CLUSTER_COUNT * CLUSTER_LIGHT_STRIDE * size_of(u32)),
			{.STORAGE_BUFFER},
			&r.scene.cluster_indices_buffers[i],
			&r.scene.cluster_indices_memory[i],
			&r.scene.cluster_indices_mapped[i],
		) {
			return false
		}
	}
	r.scene.object_capacity = object_capacity
	r.scene.light_capacity = light_capacity
	return true
}

@(private)
destroy_scene_frame_buffers :: proc(r: ^Renderer) {
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		if r.scene.camera_mapped[i] != nil {
			vk.UnmapMemory(r.device, r.scene.camera_memory[i])
			r.scene.camera_mapped[i] = nil
		}
		destroy_buffer(r, &r.scene.camera_buffers[i], &r.scene.camera_memory[i])

		if r.scene.object_mapped[i] != nil {
			vk.UnmapMemory(r.device, r.scene.object_memory[i])
			r.scene.object_mapped[i] = nil
		}
		destroy_buffer(r, &r.scene.object_buffers[i], &r.scene.object_memory[i])

		if r.scene.light_mapped[i] != nil {
			vk.UnmapMemory(r.device, r.scene.light_memory[i])
			r.scene.light_mapped[i] = nil
		}
		destroy_buffer(r, &r.scene.light_buffers[i], &r.scene.light_memory[i])

		if r.scene.cluster_counts_mapped[i] != nil {
			vk.UnmapMemory(r.device, r.scene.cluster_counts_memory[i])
			r.scene.cluster_counts_mapped[i] = nil
		}
		destroy_buffer(
			r,
			&r.scene.cluster_counts_buffers[i],
			&r.scene.cluster_counts_memory[i],
		)

		if r.scene.cluster_indices_mapped[i] != nil {
			vk.UnmapMemory(r.device, r.scene.cluster_indices_memory[i])
			r.scene.cluster_indices_mapped[i] = nil
		}
		destroy_buffer(
			r,
			&r.scene.cluster_indices_buffers[i],
			&r.scene.cluster_indices_memory[i],
		)
	}
	r.scene.object_capacity = 0
	r.scene.light_capacity = 0
}

@(private)
write_scene_bindings :: proc(r: ^Renderer) {
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		buffer_infos := [5]vk.DescriptorBufferInfo {
			{
				buffer = r.scene.camera_buffers[i],
				offset = 0,
				range = vk.DeviceSize(size_of(Camera_Uniform)),
			},
			{
				buffer = r.scene.object_buffers[i],
				offset = 0,
				range = vk.DeviceSize(r.scene.object_capacity * size_of(Object_Data)),
			},
			{
				buffer = r.scene.light_buffers[i],
				offset = 0,
				range = vk.DeviceSize(r.scene.light_capacity * size_of(Light)),
			},
			{
				buffer = r.scene.cluster_counts_buffers[i],
				offset = 0,
				range = vk.DeviceSize(CLUSTER_COUNTS_SIZE),
			},
			{
				buffer = r.scene.cluster_indices_buffers[i],
				offset = 0,
				range = vk.DeviceSize(CLUSTER_COUNT * CLUSTER_LIGHT_STRIDE * size_of(u32)),
			},
		}
		writes := [5]vk.WriteDescriptorSet {
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
			{
				sType = .WRITE_DESCRIPTOR_SET,
				dstSet = r.scene.descriptor_sets[i],
				dstBinding = CLUSTER_COUNTS_BINDING,
				descriptorCount = 1,
				descriptorType = .STORAGE_BUFFER,
				pBufferInfo = &buffer_infos[3],
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				dstSet = r.scene.descriptor_sets[i],
				dstBinding = CLUSTER_INDICES_BINDING,
				descriptorCount = 1,
				descriptorType = .STORAGE_BUFFER,
				pBufferInfo = &buffer_infos[4],
			},
		}
		vk.UpdateDescriptorSets(r.device, u32(len(writes)), &writes[0], 0, nil)
	}
}

// A scene that grows past the current buffers reallocates them. Growth waits
// for the device because a previous frame may still read the old buffer. It is
// rare, and the alternative is a per-frame capacity check on every upload.
ensure_scene_capacity :: proc(
	r: ^Renderer,
	object_count, light_count: int,
) -> bool {
	if object_count <= r.scene.object_capacity && light_count <= r.scene.light_capacity {
		return true
	}
	object_capacity := max(r.scene.object_capacity, 1)
	for object_capacity < object_count {
		object_capacity *= 2
	}
	light_capacity := max(r.scene.light_capacity, 1)
	for light_capacity < light_count {
		light_capacity *= 2
	}

	if r.device != nil {
		_ = vk.DeviceWaitIdle(r.device)
	}
	destroy_scene_frame_buffers(r)
	if !create_scene_frame_buffers(r, object_capacity, light_capacity) {
		return false
	}
	write_scene_bindings(r)
	return true
}
