#+vet explicit-allocators
#+vet !unused-procedures // the harness clicks the view; the game binary does not
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
	ui_frame :: proc(dt: f64, snapshot: ^Ui_Snapshot, events: [^]Ui_Event, count: u32) -> i32 ---
	ui_actions :: proc(count: ^u32) -> [^]Ui_Action ---
	ui_actions_clear :: proc() ---
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

Ui_Snapshot :: struct {
	speed:        f32,
	grounded:     u32,
	menu_open:    u32,
	palette_open: u32,
}

Ui_Event :: struct {
	kind:  u32,
	flags: u32,
	x:     f32,
	y:     f32,
	dx:    f32,
	dy:    f32,
	key:   i32,
}

Ui_Action :: struct {
	kind:  u32,
	value: i32,
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

ui_step :: proc(r: ^Renderer, frame: UI_Frame) {
	width, height := target_extent(r)
	if width == 0 || height == 0 {
		return
	}
	scale := clamp(f32(height) / 720.0, 1.0, 2.0)
	x := frame.pointer.x * f32(width) / scale
	y := frame.pointer.y * f32(height) / scale

	events: [16]Ui_Event
	count := 0
	events[count] = {kind = 1, x = x, y = y}
	count += 1
	if frame.pointer_pressed {
		events[count] = {kind = 2, x = x, y = y}
		count += 1
	}
	if !frame.pointer_down && r.ui_pointer_down {
		events[count] = {kind = 3, x = x, y = y}
		count += 1
	}
	r.ui_pointer_down = frame.pointer_down
	for key in frame.keys {
		code: i32
		switch key {
		case .Up:
			code = 2
		case .Down:
			code = 3
		case .Left:
			code = 4
		case .Right:
			code = 5
		case .Confirm:
			code = 0
		case .Escape:
			code = 1
		}
		events[count] = {kind = 5, key = code}
		count += 1
	}

	snapshot := Ui_Snapshot {
		speed        = frame.snapshot.speed,
		grounded     = frame.snapshot.grounded,
		menu_open    = frame.snapshot.menu_open,
		palette_open = frame.snapshot.palette_open,
	}
	if ui_frame(frame.dt, &snapshot, raw_data(events[:count]), u32(count)) != 0 {
		log.error("renderer: the UI shim could not step")
	}
}

ui_actions_slice :: proc() -> []Ui_Action {
	count: u32
	pointer := ui_actions(&count)
	if pointer == nil || count == 0 {
		return nil
	}
	return pointer[:count]
}

ui_click :: proc(r: ^Renderer, x, y: f32) -> []Ui_Action {
	events := [3]Ui_Event {
		{kind = 1, x = x, y = y},
		{kind = 2, x = x, y = y},
		{kind = 3, x = x, y = y},
	}
	snapshot: Ui_Snapshot
	if ui_frame(0, &snapshot, raw_data(events[:]), 3) != 0 {
		return nil
	}
	return ui_actions_slice()
}
