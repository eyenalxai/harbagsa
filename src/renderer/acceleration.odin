#+vet explicit-allocators
package renderer

import "src:geometry"
import vk "vendor:vulkan"

Acceleration_Frame :: struct {
	instances_buffer:   vk.Buffer,
	instances_memory:   vk.DeviceMemory,
	instances_mapped:   rawptr,
	instances_address:  vk.DeviceAddress,
	tlas:               vk.AccelerationStructureKHR,
	tlas_buffer:        vk.Buffer,
	tlas_memory:        vk.DeviceMemory,
	scratch_buffer:     vk.Buffer,
	scratch_memory:     vk.DeviceMemory,
	scratch_address:    vk.DeviceAddress,
}

Acceleration :: struct {
	frames:      [MAX_FRAMES_IN_FLIGHT]Acceleration_Frame,
	blas:        vk.AccelerationStructureKHR,
	blas_buffer: vk.Buffer,
	blas_memory: vk.DeviceMemory,
	blas_address: vk.DeviceAddress,
	capacity:    int,
}

buffer_address :: proc(r: ^Renderer, buffer: vk.Buffer) -> vk.DeviceAddress {
	info := vk.BufferDeviceAddressInfo {
		sType = .BUFFER_DEVICE_ADDRESS_INFO,
		buffer = buffer,
	}
	return vk.GetBufferDeviceAddress(r.device, &info)
}

acceleration_transform :: proc(m: Mat4) -> vk.TransformMatrixKHR {
	return {
		mat = {
			{m[0], m[4], m[8], m[12]},
			{m[1], m[5], m[9], m[13]},
			{m[2], m[6], m[10], m[14]},
		},
	}
}

create_acceleration_resources :: proc(r: ^Renderer) -> bool {
	if !create_blas(r) {
		return false
	}
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		if !create_tlas(r, &r.acceleration.frames[i], INITIAL_SCENE_OBJECT_CAPACITY) {
			return false
		}
	}
	r.acceleration.capacity = INITIAL_SCENE_OBJECT_CAPACITY
	write_acceleration_descriptors(r)
	return true
}

// The TLAS instance capacity follows the box count. Growth waits for the device
// because a previous frame may still read the old acceleration structure.
ensure_acceleration_capacity :: proc(r: ^Renderer, box_count: int) -> bool {
	if box_count <= r.acceleration.capacity {
		return true
	}
	capacity := max(r.acceleration.capacity, 1)
	for capacity < box_count {
		capacity *= 2
	}
	if r.device != nil {
		_ = vk.DeviceWaitIdle(r.device)
	}
	for &frame in r.acceleration.frames {
		destroy_tlas_frame(r, &frame)
		if !create_tlas(r, &frame, capacity) {
			return false
		}
	}
	r.acceleration.capacity = capacity
	write_acceleration_descriptors(r)
	return true
}

@(private)
destroy_tlas_frame :: proc(r: ^Renderer, frame: ^Acceleration_Frame) {
	if frame.tlas != 0 {
		vk.DestroyAccelerationStructureKHR(r.device, frame.tlas, nil)
		frame.tlas = 0
	}
	if frame.instances_mapped != nil {
		vk.UnmapMemory(r.device, frame.instances_memory)
		frame.instances_mapped = nil
	}
	destroy_buffer(r, &frame.instances_buffer, &frame.instances_memory)
	destroy_buffer(r, &frame.tlas_buffer, &frame.tlas_memory)
	destroy_buffer(r, &frame.scratch_buffer, &frame.scratch_memory)
}

write_acceleration_descriptors :: proc(r: ^Renderer) {
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		acceleration_write := vk.WriteDescriptorSetAccelerationStructureKHR {
			sType = .WRITE_DESCRIPTOR_SET_ACCELERATION_STRUCTURE_KHR,
			accelerationStructureCount = 1,
			pAccelerationStructures = &r.acceleration.frames[i].tlas,
		}
		write := vk.WriteDescriptorSet {
			sType = .WRITE_DESCRIPTOR_SET,
			pNext = &acceleration_write,
			dstSet = r.scene.descriptor_sets[i],
			dstBinding = ACCELERATION_BINDING,
			descriptorCount = 1,
			descriptorType = .ACCELERATION_STRUCTURE_KHR,
		}
		vk.UpdateDescriptorSets(r.device, 1, &write, 0, nil)
	}
}

record_acceleration :: proc(
	r: ^Renderer,
	command_buffer: vk.CommandBuffer,
	boxes: []geometry.Box,
) {
	frame := &r.acceleration.frames[r.frame_index]
	instances := cast([^]vk.AccelerationStructureInstanceKHR)frame.instances_mapped
	for box, index in boxes {
		instance: vk.AccelerationStructureInstanceKHR
		instance.transform = acceleration_transform(box_model_matrix(box))
		instance.mask = box_instance_mask(box)
		instance.accelerationStructureReference = u64(r.acceleration.blas_address)
		instances[index] = instance
	}

	instances_data := vk.AccelerationStructureGeometryInstancesDataKHR {
		sType = .ACCELERATION_STRUCTURE_GEOMETRY_INSTANCES_DATA_KHR,
		arrayOfPointers = false,
		data = {deviceAddress = frame.instances_address},
	}
	geometry := vk.AccelerationStructureGeometryKHR {
		sType = .ACCELERATION_STRUCTURE_GEOMETRY_KHR,
		geometryType = .INSTANCES,
	}
	geometry.geometry.instances = instances_data

	build_info := vk.AccelerationStructureBuildGeometryInfoKHR {
		sType = .ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR,
		type = .TOP_LEVEL,
		flags = {.PREFER_FAST_TRACE},
		mode = .BUILD,
		dstAccelerationStructure = frame.tlas,
		geometryCount = 1,
		pGeometries = &geometry,
		scratchData = {deviceAddress = frame.scratch_address},
	}
	range_info := vk.AccelerationStructureBuildRangeInfoKHR {
		primitiveCount = u32(len(boxes)),
	}
	range_ptr: [^]vk.AccelerationStructureBuildRangeInfoKHR = &range_info
	vk.CmdBuildAccelerationStructuresKHR(command_buffer, 1, &build_info, &range_ptr)

	barrier := vk.MemoryBarrier {
		sType = .MEMORY_BARRIER,
		srcAccessMask = {.ACCELERATION_STRUCTURE_WRITE_KHR},
		dstAccessMask = {.ACCELERATION_STRUCTURE_READ_KHR},
	}
	vk.CmdPipelineBarrier(
		command_buffer,
		{.ACCELERATION_STRUCTURE_BUILD_KHR},
		{.FRAGMENT_SHADER},
		{},
		1,
		&barrier,
		0,
		nil,
		0,
		nil,
	)
}

destroy_acceleration :: proc(r: ^Renderer) {
	if r.device == nil {
		return
	}
	for &frame in r.acceleration.frames {
		destroy_tlas_frame(r, &frame)
	}
	if r.acceleration.blas != 0 {
		vk.DestroyAccelerationStructureKHR(r.device, r.acceleration.blas, nil)
		r.acceleration.blas = 0
	}
	destroy_buffer(r, &r.acceleration.blas_buffer, &r.acceleration.blas_memory)
}
