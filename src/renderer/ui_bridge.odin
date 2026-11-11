#+vet explicit-allocators
package renderer

// The Rust UI shim owns the Vulkan device the game renders on and, later, the
// Rune runtime that draws the overlay.

foreign import ui_lib "../../build/libharbagsa_ui.a"

foreign ui_lib {
	ui_vk_instance_extensions :: proc(count: ^u32) -> [^]cstring ---
	ui_vk_init :: proc(config: ^Ui_Vk_Config, out: ^Ui_Vk_Device) -> i32 ---
}

Ui_Vk_Config :: struct {
	instance:        rawptr,
	physical_device: rawptr,
	graphics_family: u32,
	present_family:  u32,
}

Ui_Vk_Device :: struct {
	device:         rawptr,
	graphics_queue: rawptr,
	present_queue:  rawptr,
}
