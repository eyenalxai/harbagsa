#+vet explicit-allocators
package renderer

import "core:log"

import "src:geometry"
import "src:perf"
import vk "vendor:vulkan"

Frame_View :: struct {
	camera:               Camera,
	light_direction:      [3]f32,
	sun_angular_diameter: f32,
	boxes:                []geometry.Box,
	lights:               []Light,
	debug_lines:          []geometry.Line,
	hud:                  HUD_Frame,
	view_flags:           View_Flags,
}

create_semaphore :: proc(r: ^Renderer, semaphore: ^vk.Semaphore) -> bool {
	info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}
	return check(vk.CreateSemaphore(r.device, &info, nil, semaphore), "vkCreateSemaphore")
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

	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		if !create_semaphore(r, &r.image_available[i]) {
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
	view: Frame_View,
	capture := Frame_Capture{},
) -> (
	frame: Frame,
	status: Frame_Status,
) {
	if validation_failed() {
		return {}, .Fatal
	}

	if r.target.config.width == 0 || r.target.config.height == 0 {
		return {}, .Skipped
	}

	if r.target.dirty {
		status = recreate_swapchain(r)
		if status != .Ok {
			return {}, status
		}
		if validation_failed() {
			return {}, .Fatal
		}
	}

	if !check(vk.WaitForFences(r.device, 1, &r.in_flight[r.frame_index], true, max(u64)), "vkWaitForFences") {
		return {}, .Fatal
	}
	read_timing(r)

	image_index: u32
	if r.target.kind == .Swapchain {
		acquire := vk.AcquireNextImageKHR(
			r.device,
			r.target.swapchain,
			max(u64),
			r.image_available[r.frame_index],
			0,
			&image_index,
		)
		#partial switch acquire {
		case .SUCCESS:
		case .SUBOPTIMAL_KHR:
			r.target.dirty = true
		case .ERROR_OUT_OF_DATE_KHR:
			r.timing_valid[r.frame_index] = false
			r.target.dirty = true
			return {}, .Skipped
		case:
			log.errorf("renderer: vkAcquireNextImageKHR failed: %v", acquire)
			return {}, .Fatal
		}
	}

	if !check(vk.ResetFences(r.device, 1, &r.in_flight[r.frame_index]), "vkResetFences") {
		return {}, .Fatal
	}

	command_buffer := r.command_buffers[r.frame_index]
	if !check(vk.ResetCommandBuffer(command_buffer, {}), "vkResetCommandBuffer") {
		return {}, .Fatal
	}
	if !record_scene(r, command_buffer, image_index, view, capture) {
		return {}, .Fatal
	}
	r.timing_frames[r.frame_index] = u64(r.frame_count)
	r.timing_valid[r.frame_index] = true
	if r.recorder != nil {
		perf.recorder_mark(r.recorder, .Record)
	}
	if validation_failed() {
		return {}, .Fatal
	}

	return Frame{image_index = image_index, command_buffer = command_buffer, capture = capture.enabled}, .Ok
}

end_frame :: proc(r: ^Renderer, frame: Frame) -> Frame_Status {
	command_buffer := frame.command_buffer
	image_index := frame.image_index

	if r.target.kind == .Swapchain {
		image_available := r.image_available[r.frame_index]
		render_finished := r.target.render_finished[image_index]
		wait_stage := vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT}
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
	} else {
		submit := vk.SubmitInfo{
			sType              = .SUBMIT_INFO,
			commandBufferCount = 1,
			pCommandBuffers    = &command_buffer,
		}
		if !check(vk.QueueSubmit(r.graphics_queue, 1, &submit, r.in_flight[r.frame_index]), "vkQueueSubmit") {
			return .Fatal
		}
	}
	if validation_failed() {
		return .Fatal
	}

	if frame.capture &&
	   !check(
		   vk.WaitForFences(r.device, 1, &r.in_flight[r.frame_index], true, max(u64)),
		   "vkWaitForFences",
	   ) {
		return .Fatal
	}

	status: Frame_Status = .Ok
	if r.target.kind == .Swapchain {
		render_finished := r.target.render_finished[image_index]
		present := vk.PresentInfoKHR{
			sType              = .PRESENT_INFO_KHR,
			waitSemaphoreCount = 1,
			pWaitSemaphores    = &render_finished,
			swapchainCount     = 1,
			pSwapchains        = &r.target.swapchain,
			pImageIndices      = &image_index,
		}
		present_result := vk.QueuePresentKHR(r.present_queue, &present)
		#partial switch present_result {
		case .SUCCESS:
		case .SUBOPTIMAL_KHR:
			r.target.dirty = true
		case .ERROR_OUT_OF_DATE_KHR:
			r.target.dirty = true
			status = .Skipped
		case:
			log.errorf("renderer: vkQueuePresentKHR failed: %v", present_result)
			status = .Fatal
		}
	}
	if validation_failed() {
		return .Fatal
	}

	r.frame_index = (r.frame_index + 1) % frames_in_flight(r.target.kind)
	return status
}
