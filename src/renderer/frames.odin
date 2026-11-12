#+vet explicit-allocators
package renderer

import "core:log"

import "src:perf"
import vk "vendor:vulkan"

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
	if !check(vk.AllocateCommandBuffers(r.device, &alloc_info, &r.finalize_buffers[0]), "vkAllocateCommandBuffers") {
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

MAX_FRAME_ATTEMPTS :: 2

Frame_Result :: struct {
	status: Frame_Status,
	// The frame ring slot the submission used; -1 when every attempt skipped.
	slot:   int,
}

// One call owns the frame protocol. A swapchain recreate can skip the begin or
// the present, so the retry lives here instead of at each caller.
render_frame :: proc(
	r: ^Renderer,
	input: Render_Input,
	capture := Frame_Capture{},
) -> Frame_Result {
	if r.ui_ready {
		ui_step(r, input.hud)
	}
	for _ in 0 ..< MAX_FRAME_ATTEMPTS {
		frame, begin_status := begin_frame(r, input, capture)
		if begin_status == .Skipped {
			continue
		}
		if begin_status != .Ok {
			return {status = begin_status, slot = -1}
		}
		slot := r.frame_index
		switch end_frame(r, frame) {
		case .Ok:
			return {status = .Ok, slot = slot}
		case .Skipped:
			continue
		case .Fatal:
			return {status = .Fatal, slot = -1}
		}
	}
	return {status = .Skipped, slot = -1}
}

@(private)
begin_frame :: proc(
	r: ^Renderer,
	input: Render_Input,
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
	if counts := cast([^]u32)r.scene.cluster_counts_mapped[r.frame_index]; counts != nil {
		r.cluster_overflow = counts[CLUSTER_COUNT]
	}
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
	slots := capture_slot_count(capture)
	if slots > 0 && !ensure_readback_slots(r, u32(slots)) {
		return {}, .Fatal
	}
	if capture_has_term_views(capture) && !ensure_view_images(r) {
		return {}, .Fatal
	}
	if !record_scene(r, command_buffer, image_index, input, capture) {
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

	return Frame {
		image_index = image_index,
		command_buffer = command_buffer,
		capture = capture_slot_count(capture) > 0,
		color_slot = capture_target_slot(capture, .Color),
		wait = input.pick_at != nil,
		ui_enabled = input.hud.enabled,
	}, .Ok
}

@(private)
end_frame :: proc(r: ^Renderer, frame: Frame) -> Frame_Status {
	command_buffer := frame.command_buffer
	image_index := frame.image_index

	if r.target.kind == .Swapchain {
		image_available := r.image_available[r.frame_index]
		wait_stage := vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT}
		submit := vk.SubmitInfo{
			sType              = .SUBMIT_INFO,
			waitSemaphoreCount = 1,
			pWaitSemaphores    = &image_available,
			pWaitDstStageMask  = &wait_stage,
			commandBufferCount = 1,
			pCommandBuffers    = &command_buffer,
		}
		if !check(vk.QueueSubmit(r.graphics_queue, 1, &submit, vk.Fence(0)), "vkQueueSubmit") {
			return .Fatal
		}
	} else {
		submit := vk.SubmitInfo{
			sType              = .SUBMIT_INFO,
			commandBufferCount = 1,
			pCommandBuffers    = &command_buffer,
		}
		if !check(vk.QueueSubmit(r.graphics_queue, 1, &submit, vk.Fence(0)), "vkQueueSubmit") {
			return .Fatal
		}
	}

	if r.ui_ready && frame.ui_enabled && ui_draw(image_index) != 0 {
		log.error("renderer: the UI shim could not draw")
		return .Fatal
	}

	finalize := r.finalize_buffers[r.frame_index]
	if !check(vk.ResetCommandBuffer(finalize, {}), "vkResetCommandBuffer") {
		return .Fatal
	}
	finalize_begin := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	if !check(vk.BeginCommandBuffer(finalize, &finalize_begin), "vkBeginCommandBuffer") {
		return .Fatal
	}
	if frame.color_slot >= 0 {
		if !record_capture_copy(r, finalize, image_index, .Color, frame.color_slot) {
			return .Fatal
		}
	}
	if r.target.kind == .Swapchain {
		record_present_barrier(r, finalize, image_index)
	}
	if !check(vk.EndCommandBuffer(finalize), "vkEndCommandBuffer") {
		return .Fatal
	}
	if r.target.kind == .Swapchain {
		render_finished := r.target.render_finished[image_index]
		finalize_submit := vk.SubmitInfo{
			sType                = .SUBMIT_INFO,
			commandBufferCount   = 1,
			pCommandBuffers      = &finalize,
			signalSemaphoreCount = 1,
			pSignalSemaphores    = &render_finished,
		}
		if !check(vk.QueueSubmit(r.graphics_queue, 1, &finalize_submit, r.in_flight[r.frame_index]), "vkQueueSubmit") {
			return .Fatal
		}
	} else {
		finalize_submit := vk.SubmitInfo{
			sType              = .SUBMIT_INFO,
			commandBufferCount = 1,
			pCommandBuffers    = &finalize,
		}
		if !check(vk.QueueSubmit(r.graphics_queue, 1, &finalize_submit, r.in_flight[r.frame_index]), "vkQueueSubmit") {
			return .Fatal
		}
	}
	if validation_failed() {
		return .Fatal
	}

	if (frame.capture || frame.wait) &&
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
