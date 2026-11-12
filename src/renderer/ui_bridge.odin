#+vet explicit-allocators
package renderer

import "core:log"

// The Rust UI shim owns the Vulkan device the game renders on and the Rune
// runtime that draws the overlay.

foreign import ui_lib "../../build/libharbagsa_ui.a"

foreign ui_lib {
	ui_vk_instance_extensions :: proc(count: ^u32) -> [^]cstring ---
	ui_vk_init :: proc(config: ^Ui_Vk_Config, out: ^Ui_Vk_Device) -> i32 ---
	ui_attach :: proc(target: ^Ui_Target) -> i32 ---
	ui_draw :: proc(image_index: u32) -> i32 ---
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

Ui_Target :: struct {
	format:      u32,
	width:       u32,
	height:      u32,
	scale:       f32,
	images:      [^]u64,
	image_count: u32,
}

ui_attach_target :: proc(r: ^Renderer) -> bool {
	if len(r.target.images) == 0 {
		return false
	}
	scale := clamp(f32(r.target.config.height) / 720.0, 1.0, 2.0)
	images := make([]u64, len(r.target.images), r.allocator)
	defer delete(images, r.allocator)
	for image, index in r.target.images {
		images[index] = u64(image)
	}
	target := Ui_Target {
		format      = u32(r.target.config.format),
		width       = r.target.config.width,
		height      = r.target.config.height,
		scale       = scale,
		images      = raw_data(images),
		image_count = u32(len(images)),
	}
	if ui_attach(&target) != 0 {
		log.error("renderer: the UI shim could not attach to the target")
		return false
	}
	return true
}
