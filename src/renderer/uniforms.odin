#+vet explicit-allocators
package renderer

import vk "vendor:vulkan"

INITIAL_SCENE_OBJECT_CAPACITY :: 512
INITIAL_POINT_LIGHT_CAPACITY :: 64

CLUSTER_X :: 16
CLUSTER_Y :: 9
CLUSTER_Z :: 24
CLUSTER_COUNT :: CLUSTER_X * CLUSTER_Y * CLUSTER_Z
CLUSTER_LIGHT_STRIDE :: 256
CLUSTER_LOCAL_SIZE :: 64
CLUSTER_COUNTS_SIZE :: (CLUSTER_COUNT + 1) * size_of(u32)

// screen holds gamma, width, height, and plan-view clip height. lights.x holds
// the point-light count. The other lanes are reserved by std140 alignment.
Camera_Uniform :: struct {
	view:                 Mat4,
	projection:           Mat4,
	prev_view_projection: Mat4,
	screen:               [4]f32,
	lights:               [4]f32,
	jitter:               [4]f32,
}

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

#assert(size_of(Camera_Uniform) == 240)
#assert(size_of(Object_Data) == 144)
#assert(size_of(Object_Index) == 4)
#assert(size_of(TAA_Params) == 24)

CAMERA_BINDING :: 0
OBJECT_BINDING :: 1
LIGHT_BINDING :: 3
CLUSTER_COUNTS_BINDING :: 4
CLUSTER_INDICES_BINDING :: 5

create_scene_resources :: proc(r: ^Renderer) -> bool {
	bindings := [5]vk.DescriptorSetLayoutBinding {
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

	pool_sizes := [2]vk.DescriptorPoolSize {
		{type = .UNIFORM_BUFFER, descriptorCount = MAX_FRAMES_IN_FLIGHT},
		{type = .STORAGE_BUFFER, descriptorCount = MAX_FRAMES_IN_FLIGHT * 4},
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

	if !create_scene_frame_buffers(r, INITIAL_SCENE_OBJECT_CAPACITY, INITIAL_POINT_LIGHT_CAPACITY) {
		return false
	}
	write_scene_bindings(r)
	return true
}
