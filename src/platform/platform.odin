#+vet explicit-allocators
package platform

import "core:c"
import "core:log"
import "vendor:sdl3"
import vk "vendor:vulkan"

// Window and event handling backed by SDL3, plus the SDL3 Vulkan surface
// helpers. The renderer owns every Vulkan object; this module only creates the
// window, hands out the instance extension list, and makes the surface.

Error :: enum {
	None,
	SDL_Init,
	Create_Window,
	Vulkan_Extensions,
	Create_Surface,
}

Window :: struct {
	handle: ^sdl3.Window,
}

// The events the main loop cares about. Input events are added by a later
// ticket.
Events :: struct {
	quit: bool,
}

init :: proc(title: cstring, width, height: i32) -> (window: Window, err: Error) {
	if !sdl3.Init({.VIDEO}) {
		log.errorf("platform: SDL_Init failed: %v", sdl3.GetError())
		return {}, .SDL_Init
	}

	window.handle = sdl3.CreateWindow(title, width, height, {.VULKAN, .RESIZABLE})
	if window.handle == nil {
		log.errorf("platform: SDL_CreateWindow failed: %v", sdl3.GetError())
		sdl3.Quit()
		return {}, .Create_Window
	}

	return window, .None
}

deinit :: proc(window: ^Window) {
	if window.handle != nil {
		sdl3.DestroyWindow(window.handle)
		window.handle = nil
	}
	sdl3.Quit()
}

// vulkan_loader_proc returns vkGetInstanceProcAddr from the Vulkan loader that
// SDL opened for the window.
vulkan_loader_proc :: proc() -> rawptr {
	return rawptr(sdl3.Vulkan_GetVkGetInstanceProcAddr())
}

// vulkan_extensions returns the instance extensions that the window needs.
// The slice points into SDL-owned storage and stays valid for the window's
// lifetime.
vulkan_extensions :: proc() -> (extensions: []cstring, err: Error) {
	count: u32
	names := sdl3.Vulkan_GetInstanceExtensions(&count)
	if names == nil || count == 0 {
		log.errorf("platform: SDL_Vulkan_GetInstanceExtensions failed: %v", sdl3.GetError())
		return nil, .Vulkan_Extensions
	}
	return names[:count], .None
}

create_vulkan_surface :: proc(window: ^Window, instance: vk.Instance) -> (surface: vk.SurfaceKHR, err: Error) {
	if !sdl3.Vulkan_CreateSurface(window.handle, instance, nil, &surface) {
		log.errorf("platform: SDL_Vulkan_CreateSurface failed: %v", sdl3.GetError())
		return 0, .Create_Surface
	}
	return surface, .None
}

destroy_vulkan_surface :: proc(instance: vk.Instance, surface: vk.SurfaceKHR) {
	sdl3.Vulkan_DestroySurface(instance, surface, nil)
}

poll_events :: proc() -> (events: Events) {
	event: sdl3.Event
	for sdl3.PollEvent(&event) {
		apply_event(&events, &event)
	}
	return
}

// wait_events blocks until one event arrives or the timeout expires, then
// drains the queue. The main loop uses it while the window is minimized so the
// process does not spin.
wait_events :: proc(timeout_ms: i32) -> (events: Events) {
	event: sdl3.Event
	if !sdl3.WaitEventTimeout(&event, timeout_ms) {
		return
	}
	apply_event(&events, &event)

	rest := poll_events()
	events.quit = events.quit || rest.quit
	return
}

is_minimized :: proc(window: ^Window) -> bool {
	return .MINIMIZED in sdl3.GetWindowFlags(window.handle)
}

// pixel_size returns the drawable size in pixels, or zero when the window has
// no drawable area (for example while minimized).
pixel_size :: proc(window: ^Window) -> (width, height: u32) {
	w, h: c.int
	if !sdl3.GetWindowSizeInPixels(window.handle, &w, &h) {
		log.errorf("platform: SDL_GetWindowSizeInPixels failed: %v", sdl3.GetError())
		return 0, 0
	}
	if w <= 0 || h <= 0 {
		return 0, 0
	}
	return u32(w), u32(h)
}

apply_event :: proc(events: ^Events, event: ^sdl3.Event) {
	#partial switch event.type {
	case .QUIT, .WINDOW_CLOSE_REQUESTED:
		events.quit = true
	}
}
