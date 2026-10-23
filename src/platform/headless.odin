#+vet explicit-allocators
#+vet !unused-procedures // the harness builds the headless adapter; the game binary does not
package platform

import "core:dynlib"

import vk "vendor:vulkan"

import "src:renderer"

VULKAN_LIBRARIES :: []string{"libvulkan.so.1", "libvulkan.so"}

Headless :: struct {
	library: dynlib.Library,
	width:   u32,
	height:  u32,
}

headless_init :: proc(headless: ^Headless, width, height: u32) -> bool {
	headless.width = width
	headless.height = height
	for name in VULKAN_LIBRARIES {
		library, ok := dynlib.load_library(name, allocator = context.temp_allocator)
		if ok {
			headless.library = library
			return true
		}
	}
	return false
}

headless_deinit :: proc(headless: ^Headless) {
	if headless.library != nil {
		dynlib.unload_library(headless.library)
		headless.library = nil
	}
}

headless_platform :: proc(headless: ^Headless) -> renderer.Platform {
	return {
		user            = headless,
		get_loader      = headless_loader,
		get_extensions  = headless_extensions,
		create_surface  = headless_surface,
		destroy_surface = headless_destroy_surface,
		pixel_size      = headless_size,
	}
}

@(private)
headless_loader :: proc(user: rawptr) -> rawptr {
	headless := cast(^Headless)user
	if headless.library == nil {
		return nil
	}
	address, found := dynlib.symbol_address(
		headless.library,
		"vkGetInstanceProcAddr",
		context.temp_allocator,
	)
	if !found {
		return nil
	}
	return address
}

@(private)
headless_extensions :: proc(user: rawptr) -> ([]cstring, bool) {
	return nil, true
}

@(private)
headless_surface :: proc(user: rawptr, instance: vk.Instance) -> (vk.SurfaceKHR, bool) {
	return 0, false
}

@(private)
headless_destroy_surface :: proc(user: rawptr, instance: vk.Instance, surface: vk.SurfaceKHR) {
}

@(private)
headless_size :: proc(user: rawptr) -> (u32, u32) {
	headless := cast(^Headless)user
	return headless.width, headless.height
}
