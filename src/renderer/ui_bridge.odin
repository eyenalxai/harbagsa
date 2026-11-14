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
	ui_frame :: proc(dt: f64, snapshot: ^Ui_Snapshot, panel: ^Ui_Panel, menu: ^Ui_Menu, settings: ^Ui_Settings, palette: ^Ui_Palette, inspector: ^Ui_Inspector, events: [^]Ui_Event, count: u32) -> i32 ---
	ui_click_point :: proc(x, y: f32) -> i32 ---
	ui_element_center :: proc(pointer: [^]u8, len: u32, x: ^f32, y: ^f32) -> i32 ---
	ui_drag_at :: proc(x, y, dx, dy: f32, steps: u32, hold: u32, cancel: u32) -> i32 ---
	ui_drag_element :: proc(pointer: [^]u8, len: u32, dx, dy: f32, steps: u32, hold: u32, cancel: u32) -> i32 ---
	ui_wheel_at :: proc(x, y, dx, dy: f32) -> i32 ---
	ui_wheel_element :: proc(pointer: [^]u8, len: u32, dx, dy: f32) -> i32 ---
	ui_focus :: proc(focused: u32) -> i32 ---
	ui_interaction :: proc(out: ^Ui_Interaction) -> i32 ---
	ui_tree_json :: proc(len: ^u32) -> [^]u8 ---
	ui_actions :: proc(count: ^u32) -> [^]Ui_Action ---
	ui_actions_clear :: proc() ---
}

UI_INTERACTION_KEY_BYTES :: 96

Ui_Interaction :: struct {
	focus:       [UI_INTERACTION_KEY_BYTES]u8,
	focus_len:   u32,
	hover:       [UI_INTERACTION_KEY_BYTES]u8,
	hover_len:   u32,
	pressed:     [UI_INTERACTION_KEY_BYTES]u8,
	pressed_len: u32,
	scroll_offset: f32,
	scroll_max:    f32,
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
	speed:           f32,
	grounded:        u32,
	menu_open:       u32,
	palette_open:    u32,
	fx:              u32,
	weight:          f32,
	viewport_width:  f32,
	viewport_height: f32,
}

Ui_Row :: struct {
	kind:      u32,
	flags:     u32,
	label:     [^]u8,
	label_len: u32,
	value:     [^]u8,
	value_len: u32,
}

Ui_Hint :: struct {
	keys:       [^]u8,
	keys_len:   u32,
	action:     [^]u8,
	action_len: u32,
}

Ui_Menu :: struct {
	open:       u32,
	title:      [^]u8,
	title_len:  u32,
	note:       [^]u8,
	note_len:   u32,
	hints:      [^]Ui_Hint,
	hint_count: u32,
}

Ui_Option :: struct {
	text:   [^]u8,
	length: u32,
}

Ui_Settings :: struct {
	window_mode:       u32,
	display:           u32,
	resolution:        i32,
	sprint_mode:       u32,
	hud_opacity:       f32,
	reduce_motion:     u32,
	window_modes:      [^]Ui_Option,
	window_mode_count: u32,
	displays:          [^]Ui_Option,
	display_count:     u32,
	resolutions:        [^]Ui_Option,
	resolution_count:   u32,
	resolution_current: Ui_Option,
	resolution_missing: u32,
	sprint_modes:       [^]Ui_Option,
	sprint_mode_count:  u32,
}

Ui_Palette_Item :: struct {
	name:           [^]u8,
	name_len:       u32,
	short:          [^]u8,
	short_len:      u32,
	half_extents:   [3]f32,
	color:          [4]f32,
	base_pitch:     f32,
	body:           [^]u8,
	body_len:       u32,
	key:            [^]u8,
	key_len:        u32,
	light_line:     [^]u8,
	light_line_len: u32,
	emissive:       u32,
}

Ui_Palette :: struct {
	open:       u32,
	title:      [^]u8,
	title_len:  u32,
	items:      [^]Ui_Palette_Item,
	item_count: u32,
	selected:   u32,
	body:       [^]u8,
	body_len:   u32,
	size:       [^]u8,
	size_len:   u32,
	hints:      [^]Ui_Hint,
	hint_count: u32,
}

Ui_Panel :: struct {
	rows:             [^]Ui_Row,
	row_count:        u32,
	notice:           [^]u8,
	notice_len:       u32,
	capture_hint:     [^]u8,
	capture_hint_len: u32,
	captured:         u32,
	palette_open:     u32,
}

Ui_Event :: UI_Event

Ui_Action :: struct {
	kind:   u32,
	id:     u32,
	value:  i32,
	scalar: f32,
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

ui_actions_slice :: proc() -> []Ui_Action {
	count: u32
	pointer := ui_actions(&count)
	if pointer == nil || count == 0 {
		return nil
	}
	return pointer[:count]
}

ui_click_at :: proc(x, y: f32) -> []Ui_Action {
	if ui_click_point(x, y) != 0 {
		return nil
	}
	return ui_actions_slice()
}

ui_find_element :: proc(key: string) -> (x, y: f32, ok: bool) {
	if ui_element_center(raw_data(key), u32(len(key)), &x, &y) != 0 {
		return 0, 0, false
	}
	return x, y, true
}

ui_drag_point :: proc(x, y, dx, dy: f32, steps: int, hold, cancel: bool) -> bool {
	return ui_drag_at(x, y, dx, dy, u32(steps), u32(hold), u32(cancel)) == 0
}

ui_drag_key :: proc(key: string, dx, dy: f32, steps: int, hold, cancel: bool) -> bool {
	return ui_drag_element(
		raw_data(key),
		u32(len(key)),
		dx,
		dy,
		u32(steps),
		u32(hold),
		u32(cancel),
	) == 0
}

ui_wheel_point :: proc(x, y, dx, dy: f32) -> bool {
	return ui_wheel_at(x, y, dx, dy) == 0
}

ui_wheel_key :: proc(key: string, dx, dy: f32) -> bool {
	return ui_wheel_element(raw_data(key), u32(len(key)), dx, dy) == 0
}

ui_query_interaction :: proc() -> (Ui_Interaction, bool) {
	interaction: Ui_Interaction
	if ui_interaction(&interaction) != 0 {
		return {}, false
	}
	return interaction, true
}

ui_tree_bytes :: proc() -> []u8 {
	count: u32
	pointer := ui_tree_json(&count)
	if pointer == nil || count == 0 {
		return nil
	}
	return pointer[:count]
}
