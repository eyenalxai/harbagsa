#+vet explicit-allocators
package platform

import vk "vendor:vulkan"

import "src:renderer"

renderer_platform :: proc(window: ^Window) -> renderer.Platform {
	return {
		user            = window,
		get_loader      = sdl_loader,
		get_extensions  = sdl_extensions,
		create_surface  = sdl_surface,
		destroy_surface = sdl_destroy_surface,
		pixel_size      = sdl_size,
	}
}

@(private)
sdl_loader :: proc(user: rawptr) -> rawptr {
	return vulkan_loader_proc()
}

@(private)
sdl_extensions :: proc(user: rawptr) -> ([]cstring, bool) {
	extensions, err := vulkan_extensions()
	return extensions, err == .None
}

@(private)
sdl_surface :: proc(user: rawptr, instance: vk.Instance) -> (vk.SurfaceKHR, bool) {
	window := cast(^Window)user
	surface, err := create_vulkan_surface(window, instance)
	return surface, err == .None
}

@(private)
sdl_destroy_surface :: proc(user: rawptr, instance: vk.Instance, surface: vk.SurfaceKHR) {
	destroy_vulkan_surface(instance, surface)
}

@(private)
sdl_size :: proc(user: rawptr) -> (u32, u32) {
	return pixel_size(cast(^Window)user)
}
