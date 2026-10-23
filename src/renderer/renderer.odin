#+vet explicit-allocators
package renderer

import "base:runtime"
import "core:log"
import "core:mem"

import "src:geometry"
import "src:platform"
import vk "vendor:vulkan"

ENABLE_VALIDATION_LAYERS :: #config(ENABLE_VALIDATION_LAYERS, false)

MAX_FRAMES_IN_FLIGHT :: 2

VALIDATION_LAYER_NAME :: "VK_LAYER_KHRONOS_validation"

DEFAULT_CLEAR_COLOR :: [4]f32{0.10, 0.45, 0.75, 1.0}

Error :: enum {
	None,
	Vulkan_Loader,
	Vulkan_Version,
	Platform,
	Create_Instance,
	Create_Debug_Messenger,
	No_Suitable_Device,
	Create_Device,
	Create_Swapchain,
	Create_Frames,
	Create_Scene,
	Create_Overlay,
	Create_Pipeline,
}

Frame_Status :: enum {
	Ok,
	Skipped,
	Fatal,
}

Frame :: struct {
	image_index:    u32,
	command_buffer: vk.CommandBuffer,
}

Renderer :: struct {
	window:          ^platform.Window,
	allocator:       mem.Allocator,
	instance:        vk.Instance,
	debug_messenger: vk.DebugUtilsMessengerEXT,
	surface:         vk.SurfaceKHR,
	physical_device: vk.PhysicalDevice,
	memory_properties: vk.PhysicalDeviceMemoryProperties,
	device:          vk.Device,
	graphics_queue:  vk.Queue,
	present_queue:   vk.Queue,
	graphics_family: u32,
	present_family:  u32,

	swapchain:        vk.SwapchainKHR,
	swapchain_format: vk.Format,
	swapchain_extent: vk.Extent2D,
	swapchain_is_srgb: bool,
	swapchain_images: []vk.Image,
	swapchain_views:  []vk.ImageView,
	swapchain_dirty:  bool,

	command_pool:    vk.CommandPool,
	command_buffers: [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
	image_available: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	render_finished: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	in_flight:       [MAX_FRAMES_IN_FLIGHT]vk.Fence,
	frame_index:     int,
	clear_color:     [4]f32,

	scene: Scene,
	overlay: Overlay,
}

// The validation callback runs outside the normal call stack, so it needs the
// logger context captured at init time.
g_context: runtime.Context

init :: proc(window: ^platform.Window, allocator: mem.Allocator) -> (r: Renderer, err: Error) {
	r.window = window
	r.allocator = allocator
	r.clear_color = DEFAULT_CLEAR_COLOR

	if err = init_instance(&r); err != .None {
		deinit(&r)
		return
	}
	if err = init_device(&r); err != .None {
		deinit(&r)
		return
	}
	if err = init_frames(&r); err != .None {
		deinit(&r)
		return
	}
	if err = init_scene(&r); err != .None {
		deinit(&r)
		return
	}
	if err = init_overlay(&r); err != .None {
		deinit(&r)
		return
	}

	return r, .None
}

deinit :: proc(r: ^Renderer) {
	if r.device != nil {
		_ = vk.DeviceWaitIdle(r.device)
	}

	destroy_overlay(r)
	destroy_scene(r)
	destroy_swapchain(r)

	if r.device != nil {
		for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
			if r.image_available[i] != 0 {
				vk.DestroySemaphore(r.device, r.image_available[i], nil)
				r.image_available[i] = 0
			}
			if r.render_finished[i] != 0 {
				vk.DestroySemaphore(r.device, r.render_finished[i], nil)
				r.render_finished[i] = 0
			}
			if r.in_flight[i] != 0 {
				vk.DestroyFence(r.device, r.in_flight[i], nil)
				r.in_flight[i] = 0
			}
		}
		if r.command_pool != 0 {
			vk.DestroyCommandPool(r.device, r.command_pool, nil)
			r.command_pool = 0
		}
		vk.DestroyDevice(r.device, nil)
		r.device = nil
	}

	if r.instance != nil {
		if r.debug_messenger != 0 {
			vk.DestroyDebugUtilsMessengerEXT(r.instance, r.debug_messenger, nil)
			r.debug_messenger = 0
		}
		if r.surface != 0 {
			platform.destroy_vulkan_surface(r.instance, r.surface)
			r.surface = 0
		}
		vk.DestroyInstance(r.instance, nil)
		r.instance = nil
	}
}

// The two handles always live and die together.
destroy_pipeline_pair :: proc(r: ^Renderer, pipeline: ^vk.Pipeline, layout: ^vk.PipelineLayout) {
	if r.device == nil {
		return
	}
	if pipeline^ != 0 {
		vk.DestroyPipeline(r.device, pipeline^, nil)
		pipeline^ = 0
	}
	if layout^ != 0 {
		vk.DestroyPipelineLayout(r.device, layout^, nil)
		layout^ = 0
	}
}

// The platform sends this on resize, so the renderer does not compare sizes every frame.
notify_resize :: proc(r: ^Renderer) {
	r.swapchain_dirty = true
}

begin_frame :: proc(
	r: ^Renderer,
	camera: Camera,
	boxes: []geometry.Box,
	debug_lines: []geometry.Line,
	hud: HUD_State,
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
	if !record_scene(r, command_buffer, image_index, camera, boxes, debug_lines, hud) {
		return {}, .Fatal
	}

	return Frame{image_index = image_index, command_buffer = command_buffer}, .Ok
}

end_frame :: proc(r: ^Renderer, frame: Frame) -> Frame_Status {
	image_available := r.image_available[r.frame_index]
	render_finished := r.render_finished[r.frame_index]
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

check :: proc(result: vk.Result, what: string, loc := #caller_location) -> bool {
	if result == .SUCCESS {
		return true
	}
	log.errorf("renderer: %s failed: %v", what, result, location = loc)
	return false
}
