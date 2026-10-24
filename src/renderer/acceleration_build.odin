#+vet explicit-allocators
package renderer

import vk "vendor:vulkan"

create_blas :: proc(r: ^Renderer) -> bool {
	triangles := vk.AccelerationStructureGeometryTrianglesDataKHR {
		sType = .ACCELERATION_STRUCTURE_GEOMETRY_TRIANGLES_DATA_KHR,
		vertexFormat = .R32G32B32_SFLOAT,
		vertexData = {deviceAddress = buffer_address(r, r.scene.vertex_buffer)},
		vertexStride = vk.DeviceSize(size_of(Vertex)),
		maxVertex = u32(len(CUBE_VERTICES)) - 1,
		indexType = .UINT16,
		indexData = {deviceAddress = buffer_address(r, r.scene.index_buffer)},
	}
	geometry := vk.AccelerationStructureGeometryKHR {
		sType = .ACCELERATION_STRUCTURE_GEOMETRY_KHR,
		geometryType = .TRIANGLES,
		flags = {.OPAQUE},
	}
	geometry.geometry.triangles = triangles

	build_info := vk.AccelerationStructureBuildGeometryInfoKHR {
		sType = .ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR,
		type = .BOTTOM_LEVEL,
		flags = {.PREFER_FAST_TRACE},
		mode = .BUILD,
		geometryCount = 1,
		pGeometries = &geometry,
	}
	max_primitive_counts := [1]u32{u32(len(CUBE_INDICES) / 3)}
	sizes := vk.AccelerationStructureBuildSizesInfoKHR {
		sType = .ACCELERATION_STRUCTURE_BUILD_SIZES_INFO_KHR,
	}
	vk.GetAccelerationStructureBuildSizesKHR(
		r.device,
		.DEVICE,
		&build_info,
		&max_primitive_counts[0],
		&sizes,
	)

	if !create_buffer(
		r,
		sizes.accelerationStructureSize,
		{.ACCELERATION_STRUCTURE_STORAGE_KHR, .SHADER_DEVICE_ADDRESS},
		{.DEVICE_LOCAL},
		&r.acceleration.blas_buffer,
		&r.acceleration.blas_memory,
	) {
		return false
	}
	create_info := vk.AccelerationStructureCreateInfoKHR {
		sType = .ACCELERATION_STRUCTURE_CREATE_INFO_KHR,
		buffer = r.acceleration.blas_buffer,
		size = sizes.accelerationStructureSize,
		type = .BOTTOM_LEVEL,
	}
	if !check(
		vk.CreateAccelerationStructureKHR(r.device, &create_info, nil, &r.acceleration.blas),
		"vkCreateAccelerationStructureKHR",
	) {
		return false
	}
	address_info := vk.AccelerationStructureDeviceAddressInfoKHR {
		sType = .ACCELERATION_STRUCTURE_DEVICE_ADDRESS_INFO_KHR,
		accelerationStructure = r.acceleration.blas,
	}
	r.acceleration.blas_address = vk.GetAccelerationStructureDeviceAddressKHR(r.device, &address_info)

	scratch_buffer: vk.Buffer
	scratch_memory: vk.DeviceMemory
	if !create_buffer(
		r,
		sizes.buildScratchSize,
		{.STORAGE_BUFFER, .SHADER_DEVICE_ADDRESS},
		{.DEVICE_LOCAL},
		&scratch_buffer,
		&scratch_memory,
	) {
		return false
	}
	defer destroy_buffer(r, &scratch_buffer, &scratch_memory)

	build_info.dstAccelerationStructure = r.acceleration.blas
	build_info.scratchData = {deviceAddress = buffer_address(r, scratch_buffer)}
	range_info := vk.AccelerationStructureBuildRangeInfoKHR {
		primitiveCount = max_primitive_counts[0],
	}

	command_buffer, ok := begin_immediate_command(r)
	if !ok {
		return false
	}
	defer free_immediate_command(r, command_buffer)

	range_ptr: [^]vk.AccelerationStructureBuildRangeInfoKHR = &range_info
	vk.CmdBuildAccelerationStructuresKHR(command_buffer, 1, &build_info, &range_ptr)
	return end_immediate_command(r, command_buffer)
}

create_tlas :: proc(r: ^Renderer, frame: ^Acceleration_Frame) -> bool {
	instances_size := vk.DeviceSize(MAX_SCENE_BOXES * size_of(vk.AccelerationStructureInstanceKHR))
	if !create_mapped_buffer(
		r,
		instances_size,
		{.STORAGE_BUFFER, .SHADER_DEVICE_ADDRESS, .ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR},
		&frame.instances_buffer,
		&frame.instances_memory,
		&frame.instances_mapped,
	) {
		return false
	}
	frame.instances_address = buffer_address(r, frame.instances_buffer)

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
		geometryCount = 1,
		pGeometries = &geometry,
	}
	max_instance_counts := [1]u32{MAX_SCENE_BOXES}
	sizes := vk.AccelerationStructureBuildSizesInfoKHR {
		sType = .ACCELERATION_STRUCTURE_BUILD_SIZES_INFO_KHR,
	}
	vk.GetAccelerationStructureBuildSizesKHR(
		r.device,
		.DEVICE,
		&build_info,
		&max_instance_counts[0],
		&sizes,
	)

	if !create_buffer(
		r,
		sizes.accelerationStructureSize,
		{.ACCELERATION_STRUCTURE_STORAGE_KHR, .SHADER_DEVICE_ADDRESS},
		{.DEVICE_LOCAL},
		&frame.tlas_buffer,
		&frame.tlas_memory,
	) {
		return false
	}
	create_info := vk.AccelerationStructureCreateInfoKHR {
		sType = .ACCELERATION_STRUCTURE_CREATE_INFO_KHR,
		buffer = frame.tlas_buffer,
		size = sizes.accelerationStructureSize,
		type = .TOP_LEVEL,
	}
	if !check(
		vk.CreateAccelerationStructureKHR(r.device, &create_info, nil, &frame.tlas),
		"vkCreateAccelerationStructureKHR",
	) {
		return false
	}

	if !create_buffer(
		r,
		sizes.buildScratchSize,
		{.STORAGE_BUFFER, .SHADER_DEVICE_ADDRESS},
		{.DEVICE_LOCAL},
		&frame.scratch_buffer,
		&frame.scratch_memory,
	) {
		return false
	}
	frame.scratch_address = buffer_address(r, frame.scratch_buffer)
	return true
}
