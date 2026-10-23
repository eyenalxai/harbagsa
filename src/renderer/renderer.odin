#+vet explicit-allocators
package renderer

import "base:runtime"
import "core:log"
import "core:mem"

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
	Create_Target,
	Create_Swapchain,
	Create_Frames,
	Create_Scene,
	Create_Shadow,
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
	capture:        bool,
}

Config :: struct {
	platform: Platform,
	target:   Target_Kind,
	width:    u32,
	height:   u32,
}

Renderer :: struct {
	platform:          Platform,
	allocator:         mem.Allocator,
	instance:          vk.Instance,
	debug_messenger:   vk.DebugUtilsMessengerEXT,
	physical_device:   vk.PhysicalDevice,
	memory_properties: vk.PhysicalDeviceMemoryProperties,
	device:            vk.Device,
	graphics_queue:    vk.Queue,
	present_queue:     vk.Queue,
	graphics_family:   u32,
	present_family:    u32,

	command_pool:    vk.CommandPool,
	command_buffers: [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
	image_available: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	render_finished: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	in_flight:       [MAX_FRAMES_IN_FLIGHT]vk.Fence,
	frame_index:     int,
	clear_color:     [4]f32,

	target:  Target,
	scene:   Scene,
	shadow:  Shadow,
	overlay: Overlay,
}

// The validation callback runs outside the normal call stack, so it needs the
// logger context captured at init time.
g_context: runtime.Context

init :: proc(config: Config, allocator: mem.Allocator) -> (r: Renderer, err: Error) {
	r.platform = config.platform
	r.allocator = allocator
	r.clear_color = DEFAULT_CLEAR_COLOR
	r.target.kind = config.target

	if err = init_instance(&r); err != .None {
		deinit(&r)
		return
	}
	if config.target == .Swapchain {
		if err = create_platform_surface(&r); err != .None {
			deinit(&r)
			return
		}
	}
	if err = init_device(&r); err != .None {
		deinit(&r)
		return
	}
	if err = create_target(&r, config.width, config.height); err != .None {
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
	destroy_target(r)

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
	if r.target.kind == .Swapchain {
		r.target.dirty = true
	}
}

check :: proc(result: vk.Result, what: string, loc := #caller_location) -> bool {
	if result == .SUCCESS {
		return true
	}
	log.errorf("renderer: %s failed: %v", what, result, location = loc)
	return false
}
