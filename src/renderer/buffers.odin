#+vet explicit-allocators
package renderer

import "core:log"
import "core:mem"

import vk "vendor:vulkan"

create_buffer :: proc(
	r: ^Renderer,
	size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	properties: vk.MemoryPropertyFlags,
	buffer: ^vk.Buffer,
	memory: ^vk.DeviceMemory,
) -> bool {
	if size == 0 {
		log.error("renderer: refusing to create an empty buffer")
		return false
	}

	create_info := vk.BufferCreateInfo {
		sType = .BUFFER_CREATE_INFO,
		size = size,
		usage = usage,
		sharingMode = .EXCLUSIVE,
	}
	if !check(vk.CreateBuffer(r.device, &create_info, nil, buffer), "vkCreateBuffer") {
		return false
	}

	requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(r.device, buffer^, &requirements)
	memory_type, found := find_memory_type(r, requirements.memoryTypeBits, properties)
	if !found {
		log.error("renderer: no memory type matches the requested buffer properties")
		destroy_buffer(r, buffer, memory)
		return false
	}

	allocate_flags := vk.MemoryAllocateFlagsInfo {
		sType = .MEMORY_ALLOCATE_FLAGS_INFO,
		flags = {.DEVICE_ADDRESS},
	}
	allocate_info := vk.MemoryAllocateInfo {
		sType = .MEMORY_ALLOCATE_INFO,
		allocationSize = requirements.size,
		memoryTypeIndex = memory_type,
	}
	if (usage & {.SHADER_DEVICE_ADDRESS}) != {} {
		allocate_info.pNext = &allocate_flags
	}
	if !check(vk.AllocateMemory(r.device, &allocate_info, nil, memory), "vkAllocateMemory") {
		destroy_buffer(r, buffer, memory)
		return false
	}
	if !check(vk.BindBufferMemory(r.device, buffer^, memory^, 0), "vkBindBufferMemory") {
		destroy_buffer(r, buffer, memory)
		return false
	}
	return true
}

// Host-visible and permanently mapped. Unmap before destroy_buffer.
create_mapped_buffer :: proc(
	r: ^Renderer,
	size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	buffer: ^vk.Buffer,
	memory: ^vk.DeviceMemory,
	mapped: ^rawptr,
) -> bool {
	if !create_buffer(r, size, usage, {.HOST_VISIBLE, .HOST_COHERENT}, buffer, memory) {
		return false
	}
	if !check(vk.MapMemory(r.device, memory^, 0, size, {}, mapped), "vkMapMemory") {
		destroy_buffer(r, buffer, memory)
		return false
	}
	return true
}

destroy_buffer :: proc(r: ^Renderer, buffer: ^vk.Buffer, memory: ^vk.DeviceMemory) {
	if r.device != nil {
		if buffer^ != 0 {
			vk.DestroyBuffer(r.device, buffer^, nil)
			buffer^ = 0
		}
		if memory^ != 0 {
			vk.FreeMemory(r.device, memory^, nil)
			memory^ = 0
		}
	}
}

create_device_buffer :: proc(
	r: ^Renderer,
	data: rawptr,
	size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	buffer: ^vk.Buffer,
	memory: ^vk.DeviceMemory,
) -> bool {
	staging_buffer: vk.Buffer
	staging_memory: vk.DeviceMemory
	defer destroy_buffer(r, &staging_buffer, &staging_memory)

	if !create_buffer(
		r,
		size,
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
		&staging_buffer,
		&staging_memory,
	) {
		return false
	}

	mapped: rawptr
	if !check(vk.MapMemory(r.device, staging_memory, 0, size, {}, &mapped), "vkMapMemory") {
		return false
	}
	mem.copy(mapped, data, int(size))
	vk.UnmapMemory(r.device, staging_memory)

	if !create_buffer(r, size, usage | {.TRANSFER_DST}, {.DEVICE_LOCAL}, buffer, memory) {
		return false
	}

	allocate_info := vk.CommandBufferAllocateInfo {
		sType = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool = r.command_pool,
		level = .PRIMARY,
		commandBufferCount = 1,
	}
	command_buffer: vk.CommandBuffer
	if !check(vk.AllocateCommandBuffers(r.device, &allocate_info, &command_buffer), "vkAllocateCommandBuffers") {
		return false
	}
	defer vk.FreeCommandBuffers(r.device, r.command_pool, 1, &command_buffer)

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	if !check(vk.BeginCommandBuffer(command_buffer, &begin_info), "vkBeginCommandBuffer") {
		return false
	}
	copy_region := vk.BufferCopy{size = size}
	vk.CmdCopyBuffer(command_buffer, staging_buffer, buffer^, 1, &copy_region)
	if !check(vk.EndCommandBuffer(command_buffer), "vkEndCommandBuffer") {
		return false
	}

	submit := vk.SubmitInfo {
		sType = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers = &command_buffer,
	}
	if !check(vk.QueueSubmit(r.graphics_queue, 1, &submit, 0), "vkQueueSubmit") {
		return false
	}
	return check(vk.QueueWaitIdle(r.graphics_queue), "vkQueueWaitIdle")
}

find_memory_type :: proc(
	r: ^Renderer,
	type_bits: u32,
	properties: vk.MemoryPropertyFlags,
) -> (
	memory_type: u32,
	ok: bool,
) {
	for i in 0 ..< r.memory_properties.memoryTypeCount {
		if type_bits & (u32(1) << i) == 0 {
			continue
		}
		available := r.memory_properties.memoryTypes[i].propertyFlags
		if available & properties == properties {
			return u32(i), true
		}
	}
	return 0, false
}

begin_immediate_command :: proc(r: ^Renderer) -> (command_buffer: vk.CommandBuffer, ok: bool) {
	allocate_info := vk.CommandBufferAllocateInfo {
		sType = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool = r.command_pool,
		level = .PRIMARY,
		commandBufferCount = 1,
	}
	if !check(vk.AllocateCommandBuffers(r.device, &allocate_info, &command_buffer), "vkAllocateCommandBuffers") {
		return nil, false
	}
	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	if !check(vk.BeginCommandBuffer(command_buffer, &begin_info), "vkBeginCommandBuffer") {
		free_immediate_command(r, command_buffer)
		return nil, false
	}
	return command_buffer, true
}

end_immediate_command :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer) -> bool {
	if !check(vk.EndCommandBuffer(command_buffer), "vkEndCommandBuffer") {
		return false
	}
	buffer := command_buffer
	submit := vk.SubmitInfo {
		sType = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers = &buffer,
	}
	if !check(vk.QueueSubmit(r.graphics_queue, 1, &submit, 0), "vkQueueSubmit") {
		return false
	}
	return check(vk.QueueWaitIdle(r.graphics_queue), "vkQueueWaitIdle")
}

free_immediate_command :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer) {
	if command_buffer != nil {
		buffer := command_buffer
		vk.FreeCommandBuffers(r.device, r.command_pool, 1, &buffer)
	}
}
