#+vet explicit-allocators
package renderer

import vk "vendor:vulkan"

Platform :: struct {
	user:             rawptr,
	get_loader:       proc(user: rawptr) -> rawptr,
	get_extensions:   proc(user: rawptr) -> ([]cstring, bool),
	create_surface:   proc(user: rawptr, instance: vk.Instance) -> (vk.SurfaceKHR, bool),
	destroy_surface:  proc(user: rawptr, instance: vk.Instance, surface: vk.SurfaceKHR),
	pixel_size:       proc(user: rawptr) -> (u32, u32),
}
