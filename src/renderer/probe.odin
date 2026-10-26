#+vet explicit-allocators
package renderer

import "core:mem"

import vk "vendor:vulkan"

PROBE_GRID_SIZE :: 8
PROBE_TEXELS :: PROBE_GRID_SIZE * PROBE_GRID_SIZE
PROBE_RAYS :: 256
PROBE_RAY_LOCAL_SIZE :: 64
PROBE_IRRADIANCE_ENCODING_GAMMA :: f32(5.0)
PROBE_DISTANCE_EXPONENT :: f32(50.0)
PROBE_HYSTERESIS :: f32(0.75)
PROBE_LARGE_CHANGE_THRESHOLD :: f32(0.25)
PROBE_VISIBILITY_BIAS :: f32(0.05)
PROBE_VISIBILITY_MIN_BIAS :: f32(0.05)

// The shader mirror is in shaders/probe.glsl.
Probe_Volume :: struct {
	min:          [3]f32,
	spacing:      f32,
	counts:       [3]u32,
	probe_offset: u32,
}

#assert(size_of(Probe_Volume) == 32)

Probe_Push :: struct {
	first_probe: u32,
	probe_count: u32,
	reset:       u32,
	pad:         u32,
}

#assert(size_of(Probe_Push) == 16)

Probe_Buffer :: struct {
	buffer: vk.Buffer,
	memory: vk.DeviceMemory,
	mapped: rawptr,
	bytes:  vk.DeviceSize,
}

Probe :: struct {
	allocator: mem.Allocator,
	volumes:   [dynamic]Probe_Volume,

	volume: Probe_Buffer,

	irradiance: [MAX_FRAMES_IN_FLIGHT]Probe_Buffer,
	depth:      [MAX_FRAMES_IN_FLIGHT]Probe_Buffer,
	positions:  [MAX_FRAMES_IN_FLIGHT]Probe_Buffer,
	rays:       [MAX_FRAMES_IN_FLIGHT]Probe_Buffer,

	ray_pipeline:   vk.Pipeline,
	ray_layout:     vk.PipelineLayout,
	blend_pipeline: vk.Pipeline,
	blend_layout:   vk.PipelineLayout,

	volume_count: u32,
	probe_count:  u32,
	frame:        u32,
	energy:       f32,
	reset:        bool,
	light_hash:   u64,
	sun_hash:     u64,
	has_hash:     bool,
}

PROBE_RAY_SPIRV :: #load("../../build/shaders/probe_ray.comp.spv")
PROBE_BLEND_SPIRV :: #load("../../build/shaders/probe_blend.comp.spv")

create_probe_resources :: proc(r: ^Renderer) -> bool {
	r.probe.allocator = r.allocator
	r.probe.volumes = make([dynamic]Probe_Volume, 0, 0, r.allocator)
	return create_probe_buffers(r)
}

create_probe_pipelines :: proc(r: ^Renderer) -> bool {
	set_layouts := [1]vk.DescriptorSetLayout{r.scene.descriptor_set_layout}
	push_constant := vk.PushConstantRange {
		stageFlags = {.COMPUTE},
		offset = 0,
		size = u32(size_of(Probe_Push)),
	}
	if !create_compute_pipeline(
		r,
		{
			spirv = PROBE_RAY_SPIRV,
			name = "probe rays",
			set_layouts = set_layouts[:],
			push_constant = push_constant,
		},
		&r.probe.ray_pipeline,
		&r.probe.ray_layout,
	) {
		return false
	}
	return create_compute_pipeline(
		r,
		{
			spirv = PROBE_BLEND_SPIRV,
			name = "probe blend",
			set_layouts = set_layouts[:],
			push_constant = push_constant,
		},
		&r.probe.blend_pipeline,
		&r.probe.blend_layout,
	)
}

create_probe_buffer :: proc(
	r: ^Renderer,
	size: vk.DeviceSize,
	target: ^Probe_Buffer,
) -> bool {
	if !create_mapped_buffer(
		r,
		size,
		{.STORAGE_BUFFER},
		&target.buffer,
		&target.memory,
		&target.mapped,
	) {
		return false
	}
	mem.set(target.mapped, 0, int(size))
	target.bytes = size
	return true
}

create_probe_buffers :: proc(r: ^Renderer) -> bool {
	volume_slots := max(int(r.probe.volume_count), 1)
	volume_bytes := vk.DeviceSize(volume_slots * size_of(Probe_Volume))
	if !create_probe_buffer(r, volume_bytes, &r.probe.volume) {
		return false
	}
	volume_data := cast([^]Probe_Volume)r.probe.volume.mapped
	for volume, index in r.probe.volumes {
		volume_data[index] = volume
	}

	probe_slots := max(int(r.probe.probe_count), 1)
	sizes := [4]vk.DeviceSize {
		vk.DeviceSize(probe_slots * PROBE_TEXELS * size_of([4]f32)),
		vk.DeviceSize(probe_slots * PROBE_TEXELS * size_of([2]f32)),
		vk.DeviceSize(probe_slots * size_of([4]f32)),
		vk.DeviceSize(probe_slots * PROBE_RAYS * size_of([4]f32)),
	}
	for frame in 0 ..< MAX_FRAMES_IN_FLIGHT {
		targets := [4]^Probe_Buffer {
			&r.probe.irradiance[frame],
			&r.probe.depth[frame],
			&r.probe.positions[frame],
			&r.probe.rays[frame],
		}
		for target, index in targets {
			if !create_probe_buffer(r, sizes[index], target) {
				return false
			}
		}
	}
	return true
}

destroy_probe_buffer :: proc(r: ^Renderer, target: ^Probe_Buffer) {
	if target.mapped != nil {
		vk.UnmapMemory(r.device, target.memory)
		target.mapped = nil
	}
	destroy_buffer(r, &target.buffer, &target.memory)
	target.bytes = 0
}

destroy_probe_buffers :: proc(r: ^Renderer) {
	destroy_probe_buffer(r, &r.probe.volume)
	for frame in 0 ..< MAX_FRAMES_IN_FLIGHT {
		destroy_probe_buffer(r, &r.probe.irradiance[frame])
		destroy_probe_buffer(r, &r.probe.depth[frame])
		destroy_probe_buffer(r, &r.probe.positions[frame])
		destroy_probe_buffer(r, &r.probe.rays[frame])
	}
}

destroy_probe :: proc(r: ^Renderer) {
	if r.device != nil {
		destroy_pipeline_pair(r, &r.probe.ray_pipeline, &r.probe.ray_layout)
		destroy_pipeline_pair(r, &r.probe.blend_pipeline, &r.probe.blend_layout)
		destroy_probe_buffers(r)
	}
	if r.probe.volumes != nil {
		delete(r.probe.volumes)
	}
	r.probe = {}
}

// Probe volumes are scene data. A change recreates the atlas and clears it,
// because old probes belong to a different room and must not bleed into the new
// one. The scene is static in normal play, so this runs once.
ensure_probe_resources :: proc(r: ^Renderer, volumes: []Probe_Volume) -> bool {
	total := 0
	for volume in volumes {
		total += int(volume.counts.x * volume.counts.y * volume.counts.z)
	}

	same := len(volumes) == len(r.probe.volumes) && u32(total) == r.probe.probe_count
	if same {
		for volume, index in volumes {
			current := r.probe.volumes[index]
			if volume.min != current.min ||
			   volume.spacing != current.spacing ||
			   volume.counts != current.counts {
				same = false
				break
			}
		}
	}
	if same {
		return true
	}

	if r.device != nil {
		_ = vk.DeviceWaitIdle(r.device)
	}
	destroy_probe_buffers(r)
	r.probe.volume_count = u32(len(volumes))
	r.probe.probe_count = u32(total)
	r.probe.frame = 0
	r.probe.reset = true
	r.probe.has_hash = false
	clear(&r.probe.volumes)
	offset := u32(0)
	for volume in volumes {
		copy := volume
		copy.probe_offset = offset
		append(&r.probe.volumes, copy)
		offset += volume.counts.x * volume.counts.y * volume.counts.z
	}
	if !create_probe_buffers(r) {
		destroy_probe_buffers(r)
		return false
	}
	write_scene_bindings(r)
	return true
}

draw_probes :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, pass: ^Pass) {
	if r.probe.probe_count == 0 {
		return
	}
	push := Probe_Push {
		first_probe = 0,
		probe_count = r.probe.probe_count,
		reset       = r.probe.reset ? 1 : 0,
	}
	descriptor_set := &r.scene.descriptor_sets[r.frame_index]

	vk.CmdBindPipeline(command_buffer, .COMPUTE, r.probe.ray_pipeline)
	vk.CmdBindDescriptorSets(
		command_buffer,
		.COMPUTE,
		r.probe.ray_layout,
		0,
		1,
		descriptor_set,
		0,
		nil,
	)
	vk.CmdPushConstants(
		command_buffer,
		r.probe.ray_layout,
		{.COMPUTE},
		0,
		u32(size_of(Probe_Push)),
		&push,
	)
	ray_groups := r.probe.probe_count * PROBE_RAYS / PROBE_RAY_LOCAL_SIZE
	vk.CmdDispatch(command_buffer, ray_groups, 1, 1)

	ray_barrier := vk.BufferMemoryBarrier {
		sType = .BUFFER_MEMORY_BARRIER,
		srcAccessMask = {.SHADER_WRITE},
		dstAccessMask = {.SHADER_READ},
		buffer = r.probe.rays[r.frame_index].buffer,
		offset = 0,
		size = r.probe.rays[r.frame_index].bytes,
	}
	vk.CmdPipelineBarrier(
		command_buffer,
		{.COMPUTE_SHADER},
		{.COMPUTE_SHADER},
		{},
		0,
		nil,
		1,
		&ray_barrier,
		0,
		nil,
	)

	vk.CmdBindPipeline(command_buffer, .COMPUTE, r.probe.blend_pipeline)
	vk.CmdBindDescriptorSets(
		command_buffer,
		.COMPUTE,
		r.probe.blend_layout,
		0,
		1,
		descriptor_set,
		0,
		nil,
	)
	vk.CmdPushConstants(
		command_buffer,
		r.probe.blend_layout,
		{.COMPUTE},
		0,
		u32(size_of(Probe_Push)),
		&push,
	)
	vk.CmdDispatch(command_buffer, r.probe.probe_count, 1, 1)
	r.probe.frame += 1
	r.probe.reset = false
}

probe_light_hash :: proc(lights: []Light) -> u64 {
	hash := u64(1469598103934665603)
	for light in lights {
		for value in ([?]f32{light.position.x, light.position.y, light.position.z, light.intensity, light.color.x, light.color.y, light.color.z, light.range}) {
			hash = (hash ~ u64(transmute(u32)value)) * 1099511628211
		}
	}
	return hash
}

probe_sun_hash :: proc(direction: [3]f32, angular_diameter: f32) -> u64 {
	hash := u64(1469598103934665603)
	for value in ([?]f32{direction.x, direction.y, direction.z, angular_diameter}) {
		hash = (hash ~ u64(transmute(u32)value)) * 1099511628211
	}
	return hash
}

probe_after :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, pass: ^Pass) {
	if r.probe.probe_count == 0 {
		return
	}
	frame := r.frame_index
	barriers := [2]vk.BufferMemoryBarrier {
		{
			sType = .BUFFER_MEMORY_BARRIER,
			srcAccessMask = {.SHADER_WRITE},
			dstAccessMask = {.SHADER_READ},
			buffer = r.probe.irradiance[frame].buffer,
			offset = 0,
			size = r.probe.irradiance[frame].bytes,
		},
		{
			sType = .BUFFER_MEMORY_BARRIER,
			srcAccessMask = {.SHADER_WRITE},
			dstAccessMask = {.SHADER_READ},
			buffer = r.probe.depth[frame].buffer,
			offset = 0,
			size = r.probe.depth[frame].bytes,
		},
	}
	vk.CmdPipelineBarrier(
		command_buffer,
		{.COMPUTE_SHADER},
		{.FRAGMENT_SHADER},
		{},
		0,
		nil,
		u32(len(barriers)),
		&barriers[0],
		0,
		nil,
	)
}
