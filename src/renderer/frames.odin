#+vet explicit-allocators
package renderer

import vk "vendor:vulkan"

init_frames :: proc(r: ^Renderer) -> Error {
	pool_info := vk.CommandPoolCreateInfo{
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = r.graphics_family,
	}
	if !check(vk.CreateCommandPool(r.device, &pool_info, nil, &r.command_pool), "vkCreateCommandPool") {
		return .Create_Frames
	}

	alloc_info := vk.CommandBufferAllocateInfo{
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = r.command_pool,
		level              = .PRIMARY,
		commandBufferCount = MAX_FRAMES_IN_FLIGHT,
	}
	if !check(vk.AllocateCommandBuffers(r.device, &alloc_info, &r.command_buffers[0]), "vkAllocateCommandBuffers") {
		return .Create_Frames
	}

	semaphore_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}
	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		if !check(
			vk.CreateSemaphore(r.device, &semaphore_info, nil, &r.image_available[i]),
			"vkCreateSemaphore",
		) {
			return .Create_Frames
		}
		if !check(
			vk.CreateSemaphore(r.device, &semaphore_info, nil, &r.render_finished[i]),
			"vkCreateSemaphore",
		) {
			return .Create_Frames
		}
		if !check(vk.CreateFence(r.device, &fence_info, nil, &r.in_flight[i]), "vkCreateFence") {
			return .Create_Frames
		}
	}

	return .None
}
