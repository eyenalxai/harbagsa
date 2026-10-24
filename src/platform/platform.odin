#+vet explicit-allocators
package platform

import "core:log"
import "core:strings"
import "vendor:sdl3"
import vk "vendor:vulkan"

Error :: enum {
	None,
	SDL_Init,
	Create_Window,
	Vulkan_Extensions,
	Create_Surface,
}

Window :: struct {
	handle:           ^sdl3.Window,
	capture_on_click: bool,
}

init :: proc(title: cstring, width, height: i32, fullscreen := false) -> (window: Window, err: Error) {
	if !sdl3.Init({.VIDEO}) {
		log.errorf("platform: SDL_Init failed: %v", sdl3.GetError())
		return {}, .SDL_Init
	}

	flags := sdl3.WindowFlags{.VULKAN, .RESIZABLE}
	if fullscreen {
		flags |= {.FULLSCREEN}
	}
	window.handle = sdl3.CreateWindow(title, width, height, flags)
	if window.handle == nil {
		message := string(sdl3.GetError())
		log.errorf("platform: SDL_CreateWindow failed: %s", message)
		if strings.contains(message, "VK_KHR_surface") {
			log.error("platform: no working Vulkan driver; check the installed ICD and VK_ICD_FILENAMES")
		}
		sdl3.Quit()
		return {}, .Create_Window
	}
	window.capture_on_click = true

	return window, .None
}

deinit :: proc(window: ^Window) {
	if window.handle != nil {
		sdl3.DestroyWindow(window.handle)
		window.handle = nil
	}
	sdl3.Quit()
}

vulkan_loader_proc :: proc() -> rawptr {
	return rawptr(sdl3.Vulkan_GetVkGetInstanceProcAddr())
}

// The slice points into SDL storage and stays valid for the window's lifetime.
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
