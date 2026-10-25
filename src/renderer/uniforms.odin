#+vet explicit-allocators
package renderer

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
// probe.x is the probe volume count, probe.y the total probe count, and probe.z
// the probe indirect flag.
Camera_Uniform :: struct {
	view:                 Mat4,
	projection:           Mat4,
	prev_view_projection: Mat4,
	light_direction:      [4]f32,
	screen:               [4]f32,
	sun:                  [4]f32,
	jitter:               [4]f32,
	occlusion:            [4]f32,
	probe:                [4]f32,
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

#assert(size_of(Camera_Uniform) == 288)
#assert(size_of(Object_Data) == 144)
#assert(size_of(Object_Index) == 4)
#assert(size_of(TAA_Params) == 24)

CAMERA_BINDING :: 0
OBJECT_BINDING :: 1
ACCELERATION_BINDING :: 2
LIGHT_BINDING :: 3
CLUSTER_COUNTS_BINDING :: 4
CLUSTER_INDICES_BINDING :: 5
PROBE_VOLUMES_BINDING :: 6
PROBE_IRRADIANCE_BINDING :: 7
PROBE_DEPTH_BINDING :: 8

create_scene_resources :: proc(r: ^Renderer) -> bool {
	bindings := [9]vk.DescriptorSetLayoutBinding {
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
			stageFlags = {.VERTEX, .FRAGMENT, .COMPUTE},
		},
		{
			binding = ACCELERATION_BINDING,
			descriptorType = .ACCELERATION_STRUCTURE_KHR,
			descriptorCount = 1,
			stageFlags = {.FRAGMENT, .COMPUTE},
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
		{
			binding = PROBE_VOLUMES_BINDING,
			descriptorType = .STORAGE_BUFFER,
			descriptorCount = 1,
			stageFlags = {.FRAGMENT, .COMPUTE},
		},
		{
			binding = PROBE_IRRADIANCE_BINDING,
			descriptorType = .STORAGE_BUFFER,
			descriptorCount = 1,
			stageFlags = {.FRAGMENT, .COMPUTE},
		},
		{
			binding = PROBE_DEPTH_BINDING,
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
		{type = .STORAGE_BUFFER, descriptorCount = MAX_FRAMES_IN_FLIGHT * 7},
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
