#+vet explicit-allocators
package renderer

import "core:mem"

import vk "vendor:vulkan"

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
		buffer_infos := [8]vk.DescriptorBufferInfo {
			{buffer = r.scene.camera_buffers[i], range = vk.DeviceSize(size_of(Camera_Uniform))},
			{
				buffer = r.scene.object_buffers[i],
				range = vk.DeviceSize(r.scene.object_capacity * size_of(Object_Data)),
			},
			{
				buffer = r.scene.light_buffers[i],
				range = vk.DeviceSize(r.scene.light_capacity * size_of(Light)),
			},
			{buffer = r.scene.cluster_counts_buffers[i], range = vk.DeviceSize(CLUSTER_COUNTS_SIZE)},
			{
				buffer = r.scene.cluster_indices_buffers[i],
				range = vk.DeviceSize(CLUSTER_COUNT * CLUSTER_LIGHT_STRIDE * size_of(u32)),
			},
			{
				buffer = r.bake.faces_buffer,
				range = vk.DeviceSize(r.bake.faces_bytes),
			},
			{
				buffer = r.bake.states_buffer,
				range = vk.DeviceSize(r.bake.states_bytes),
			},
			{
				buffer = r.bake.volume_buffer,
				range = vk.DeviceSize(size_of(Bake_Volume_Uniform)),
			},
		}
		lightmap_info := vk.DescriptorImageInfo {
			sampler = r.bake.sampler,
			imageView = r.bake.lightmap.view,
			imageLayout = .SHADER_READ_ONLY_OPTIMAL,
		}
		probe_irradiance_info := vk.DescriptorImageInfo {
			sampler = r.bake.sampler,
			imageView = r.bake.probe_irradiance.view,
			imageLayout = .SHADER_READ_ONLY_OPTIMAL,
		}
		probe_moments_info := vk.DescriptorImageInfo {
			sampler = r.bake.sampler,
			imageView = r.bake.probe_moments.view,
			imageLayout = .SHADER_READ_ONLY_OPTIMAL,
		}
		writes := [11]vk.WriteDescriptorSet {
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
			{
				sType = .WRITE_DESCRIPTOR_SET,
				dstSet = r.scene.descriptor_sets[i],
				dstBinding = LIGHTMAP_BINDING,
				descriptorCount = 1,
				descriptorType = .COMBINED_IMAGE_SAMPLER,
				pImageInfo = &lightmap_info,
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				dstSet = r.scene.descriptor_sets[i],
				dstBinding = LIGHTMAP_FACES_BINDING,
				descriptorCount = 1,
				descriptorType = .STORAGE_BUFFER,
				pBufferInfo = &buffer_infos[5],
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				dstSet = r.scene.descriptor_sets[i],
				dstBinding = PROBE_IRRADIANCE_BINDING,
				descriptorCount = 1,
				descriptorType = .COMBINED_IMAGE_SAMPLER,
				pImageInfo = &probe_irradiance_info,
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				dstSet = r.scene.descriptor_sets[i],
				dstBinding = PROBE_MOMENTS_BINDING,
				descriptorCount = 1,
				descriptorType = .COMBINED_IMAGE_SAMPLER,
				pImageInfo = &probe_moments_info,
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				dstSet = r.scene.descriptor_sets[i],
				dstBinding = PROBE_STATES_BINDING,
				descriptorCount = 1,
				descriptorType = .STORAGE_BUFFER,
				pBufferInfo = &buffer_infos[6],
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				dstSet = r.scene.descriptor_sets[i],
				dstBinding = PROBE_VOLUME_BINDING,
				descriptorCount = 1,
				descriptorType = .UNIFORM_BUFFER,
				pBufferInfo = &buffer_infos[7],
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
