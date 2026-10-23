#+vet explicit-allocators
package renderer

import "core:log"

import "src:geometry"
import "src:platform"
import vk "vendor:vulkan"

Frame_Status :: enum {
	Ok,
	Skipped,
	Fatal,
}

Frame :: struct {
	image_index:    u32,
	command_buffer: vk.CommandBuffer,
}

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
		if !check(vk.CreateFence(r.device, &fence_info, nil, &r.in_flight[i]), "vkCreateFence") {
			return .Create_Frames
		}
	}

	return .None
}

begin_frame :: proc(
	r: ^Renderer,
	camera: Camera,
	light_direction: [3]f32,
	boxes: []geometry.Box,
	debug_lines: []geometry.Line,
	hud: HUD_Frame,
) -> (
	frame: Frame,
	status: Frame_Status,
) {
	width, height := platform.pixel_size(r.window)
	if width == 0 || height == 0 {
		return {}, .Skipped
	}

	if r.swapchain_dirty {
		status = recreate_swapchain(r)
		if status != .Ok {
			return {}, status
		}
	}

	if !check(vk.WaitForFences(r.device, 1, &r.in_flight[r.frame_index], true, max(u64)), "vkWaitForFences") {
		return {}, .Fatal
	}

	image_index: u32
	acquire := vk.AcquireNextImageKHR(
		r.device,
		r.swapchain,
		max(u64),
		r.image_available[r.frame_index],
		0,
		&image_index,
	)
	#partial switch acquire {
	case .SUCCESS:
	case .SUBOPTIMAL_KHR:
		r.swapchain_dirty = true
	case .ERROR_OUT_OF_DATE_KHR:
		r.swapchain_dirty = true
		return {}, .Skipped
	case:
		log.errorf("renderer: vkAcquireNextImageKHR failed: %v", acquire)
		return {}, .Fatal
	}

	if !check(vk.ResetFences(r.device, 1, &r.in_flight[r.frame_index]), "vkResetFences") {
		return {}, .Fatal
	}

	command_buffer := r.command_buffers[r.frame_index]
	if !check(vk.ResetCommandBuffer(command_buffer, {}), "vkResetCommandBuffer") {
		return {}, .Fatal
	}
	if !record_frame(
		r,
		command_buffer,
		image_index,
		camera,
		light_direction,
		boxes,
		debug_lines,
		hud,
	) {
		return {}, .Fatal
	}

	return Frame{image_index = image_index, command_buffer = command_buffer}, .Ok
}

end_frame :: proc(r: ^Renderer, frame: Frame) -> Frame_Status {
	image_available := r.image_available[r.frame_index]
	render_finished := r.render_finished[frame.image_index]
	wait_stage := vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT}
	command_buffer := frame.command_buffer
	image_index := frame.image_index

	submit := vk.SubmitInfo{
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = 1,
		pWaitSemaphores      = &image_available,
		pWaitDstStageMask    = &wait_stage,
		commandBufferCount   = 1,
		pCommandBuffers      = &command_buffer,
		signalSemaphoreCount = 1,
		pSignalSemaphores    = &render_finished,
	}
	if !check(vk.QueueSubmit(r.graphics_queue, 1, &submit, r.in_flight[r.frame_index]), "vkQueueSubmit") {
		return .Fatal
	}

	present := vk.PresentInfoKHR{
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &render_finished,
		swapchainCount     = 1,
		pSwapchains        = &r.swapchain,
		pImageIndices      = &image_index,
	}
	present_result := vk.QueuePresentKHR(r.present_queue, &present)

	status: Frame_Status = .Ok
	#partial switch present_result {
	case .SUCCESS:
	case .SUBOPTIMAL_KHR:
		r.swapchain_dirty = true
	case .ERROR_OUT_OF_DATE_KHR:
		r.swapchain_dirty = true
		status = .Skipped
	case:
		log.errorf("renderer: vkQueuePresentKHR failed: %v", present_result)
		status = .Fatal
	}

	r.frame_index = (r.frame_index + 1) % MAX_FRAMES_IN_FLIGHT
	return status
}
