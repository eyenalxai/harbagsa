#+vet explicit-allocators
package renderer

import "core:mem"

import vk "vendor:vulkan"

PROBE_GRID_SIZE :: 8
PROBE_TEXELS :: PROBE_GRID_SIZE * PROBE_GRID_SIZE

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
	frame:       u32,
	reset:       u32,
}

#assert(size_of(Probe_Push) == 16)

Probe :: struct {
	allocator: mem.Allocator,
	volumes:   [dynamic]Probe_Volume,

	volume_buffer: vk.Buffer,
	volume_memory: vk.DeviceMemory,
	volume_mapped: rawptr,
	volume_bytes:  vk.DeviceSize,

	irradiance_buffers: [MAX_FRAMES_IN_FLIGHT]vk.Buffer,
	irradiance_memory:  [MAX_FRAMES_IN_FLIGHT]vk.DeviceMemory,
	irradiance_mapped:  [MAX_FRAMES_IN_FLIGHT]rawptr,
	irradiance_bytes:   vk.DeviceSize,

	depth_buffers: [MAX_FRAMES_IN_FLIGHT]vk.Buffer,
	depth_memory:  [MAX_FRAMES_IN_FLIGHT]vk.DeviceMemory,
	depth_mapped:  [MAX_FRAMES_IN_FLIGHT]rawptr,
	depth_bytes:   vk.DeviceSize,

	pipeline: vk.Pipeline,
	layout:   vk.PipelineLayout,

	volume_count: u32,
	probe_count:  u32,
	frame:        u32,
	energy:       f32,
	reset:        bool,
	light_hash:   u64,
	sun_hash:     u64,
	has_hash:     bool,
}

PROBE_UPDATE_SPIRV :: #load("../../build/shaders/probe_update.comp.spv")

create_probe_resources :: proc(r: ^Renderer) -> bool {
	r.probe.allocator = r.allocator
	r.probe.volumes = make([dynamic]Probe_Volume, 0, 0, r.allocator)
	return create_probe_buffers(r)
}

create_probe_pipeline :: proc(r: ^Renderer) -> bool {
	set_layouts := [1]vk.DescriptorSetLayout{r.scene.descriptor_set_layout}
	return create_compute_pipeline(
		r,
		{
			spirv = PROBE_UPDATE_SPIRV,
			name = "probe update",
			set_layouts = set_layouts[:],
			push_constant = vk.PushConstantRange {
				stageFlags = {.COMPUTE},
				offset = 0,
				size = u32(size_of(Probe_Push)),
			},
		},
		&r.probe.pipeline,
		&r.probe.layout,
	)
}

create_probe_buffers :: proc(r: ^Renderer) -> bool {
	volume_slots := max(int(r.probe.volume_count), 1)
	r.probe.volume_bytes = vk.DeviceSize(volume_slots * size_of(Probe_Volume))
	if !create_mapped_buffer(
		r,
		r.probe.volume_bytes,
		{.STORAGE_BUFFER},
		&r.probe.volume_buffer,
		&r.probe.volume_memory,
		&r.probe.volume_mapped,
	) {
		return false
	}
	mem.set(r.probe.volume_mapped, 0, int(r.probe.volume_bytes))
	volume_data := cast([^]Probe_Volume)r.probe.volume_mapped
	for volume, index in r.probe.volumes {
		volume_data[index] = volume
	}

	probe_slots := max(int(r.probe.probe_count), 1)
	r.probe.irradiance_bytes = vk.DeviceSize(
		probe_slots * PROBE_TEXELS * size_of([4]f32),
	)
	r.probe.depth_bytes = vk.DeviceSize(
		probe_slots * PROBE_TEXELS * size_of([2]f32),
	)
	for frame in 0 ..< MAX_FRAMES_IN_FLIGHT {
		if !create_mapped_buffer(
			r,
			r.probe.irradiance_bytes,
			{.STORAGE_BUFFER},
			&r.probe.irradiance_buffers[frame],
			&r.probe.irradiance_memory[frame],
			&r.probe.irradiance_mapped[frame],
		) {
			return false
		}
		mem.set(r.probe.irradiance_mapped[frame], 0, int(r.probe.irradiance_bytes))
		if !create_mapped_buffer(
			r,
			r.probe.depth_bytes,
			{.STORAGE_BUFFER},
			&r.probe.depth_buffers[frame],
			&r.probe.depth_memory[frame],
			&r.probe.depth_mapped[frame],
		) {
			return false
		}
		mem.set(r.probe.depth_mapped[frame], 0, int(r.probe.depth_bytes))
	}
	return true
}

destroy_probe_buffers :: proc(r: ^Renderer) {
	if r.probe.volume_mapped != nil {
		vk.UnmapMemory(r.device, r.probe.volume_memory)
		r.probe.volume_mapped = nil
	}
	destroy_buffer(r, &r.probe.volume_buffer, &r.probe.volume_memory)
	r.probe.volume_bytes = 0

	for frame in 0 ..< MAX_FRAMES_IN_FLIGHT {
		if r.probe.irradiance_mapped[frame] != nil {
			vk.UnmapMemory(r.device, r.probe.irradiance_memory[frame])
			r.probe.irradiance_mapped[frame] = nil
		}
		destroy_buffer(
			r,
			&r.probe.irradiance_buffers[frame],
			&r.probe.irradiance_memory[frame],
		)

		if r.probe.depth_mapped[frame] != nil {
			vk.UnmapMemory(r.device, r.probe.depth_memory[frame])
			r.probe.depth_mapped[frame] = nil
		}
		destroy_buffer(r, &r.probe.depth_buffers[frame], &r.probe.depth_memory[frame])
	}
	r.probe.irradiance_bytes = 0
	r.probe.depth_bytes = 0
}

destroy_probe :: proc(r: ^Renderer) {
	if r.device != nil {
		destroy_pipeline_pair(r, &r.probe.pipeline, &r.probe.layout)
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
	first := u32(0)
	count := r.probe.probe_count
	push := Probe_Push {
		first_probe = first,
		probe_count = count,
		frame       = r.probe.frame,
		reset       = r.probe.reset ? 1 : 0,
	}
	vk.CmdBindPipeline(command_buffer, .COMPUTE, r.probe.pipeline)
	vk.CmdBindDescriptorSets(
		command_buffer,
		.COMPUTE,
		r.probe.layout,
		0,
		1,
		&r.scene.descriptor_sets[r.frame_index],
		0,
		nil,
	)
	vk.CmdPushConstants(
		command_buffer,
		r.probe.layout,
		{.COMPUTE},
		0,
		u32(size_of(Probe_Push)),
		&push,
	)
	vk.CmdDispatch(command_buffer, count, 1, 1)
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
	barriers := [2]vk.BufferMemoryBarrier {
		{
			sType = .BUFFER_MEMORY_BARRIER,
			srcAccessMask = {.SHADER_WRITE},
			dstAccessMask = {.SHADER_READ},
			buffer = r.probe.irradiance_buffers[r.frame_index],
			offset = 0,
			size = r.probe.irradiance_bytes,
		},
		{
			sType = .BUFFER_MEMORY_BARRIER,
			srcAccessMask = {.SHADER_WRITE},
			dstAccessMask = {.SHADER_READ},
			buffer = r.probe.depth_buffers[r.frame_index],
			offset = 0,
			size = r.probe.depth_bytes,
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
