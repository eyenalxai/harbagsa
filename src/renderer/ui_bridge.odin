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
	ui_frame :: proc(dt: f64, snapshot: ^Ui_Snapshot, panel: ^Ui_Panel, menu: ^Ui_Menu, settings: ^Ui_Settings, palette: ^Ui_Palette, events: [^]Ui_Event, count: u32) -> i32 ---
	ui_click_point :: proc(x, y: f32) -> i32 ---
	ui_click_element :: proc(pointer: [^]u8, len: u32) -> i32 ---
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
	fx:           u32,
	weight:       f32,
}

Ui_Row :: struct {
	kind:      u32,
	flags:     u32,
	label:     [^]u8,
	label_len: u32,
	value:     [^]u8,
	value_len: u32,
	ratio:     f32,
	ticks:     u32,
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
	resolution:        u32,
	sprint_mode:       u32,
	hud_opacity:       f32,
	reduce_motion:     u32,
	window_modes:      [^]Ui_Option,
	window_mode_count: u32,
	displays:          [^]Ui_Option,
	display_count:     u32,
	resolutions:       [^]Ui_Option,
	resolution_count:  u32,
	sprint_modes:      [^]Ui_Option,
	sprint_mode_count: u32,
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
	count:      [^]u8,
	count_len:  u32,
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

ui_step :: proc(r: ^Renderer, hud: HUD_Frame) {
	if !hud.enabled {
		return
	}
	frame := hud.ui
	width, height := target_extent(r)
	if width == 0 || height == 0 {
		return
	}
	scale := clamp(f32(height) / 720.0, 1.0, 2.0)

	events: [64]Ui_Event
	count := min(len(frame.events), len(events))
	for event, index in frame.events[:count] {
		events[index] = {
			kind  = event.kind,
			flags = event.flags,
			x     = event.x * f32(width) / scale,
			y     = event.y * f32(height) / scale,
			dx    = event.dx,
			dy    = event.dy,
			key   = event.key,
		}
	}

	snapshot := frame.snapshot
	snapshot.weight = hud.weight
	rows: [64]Ui_Row
	row_count := min(len(frame.panel_rows), len(rows))
	for row, index in frame.panel_rows[:row_count] {
		flags: u32
		if row.numeric {
			flags |= 1
		}
		if row.blocked {
			flags |= 2
		}
		rows[index] = {
			kind      = u32(row.kind),
			flags     = flags,
			label     = raw_data(row.label),
			label_len = u32(len(row.label)),
			value     = raw_data(row.value),
			value_len = u32(len(row.value)),
			ratio     = row.ratio,
			ticks     = u32(row.ticks),
		}
	}
	panel := Ui_Panel {
		rows             = raw_data(rows[:row_count]),
		row_count        = u32(row_count),
		notice           = raw_data(frame.notice),
		notice_len       = u32(len(frame.notice)),
		capture_hint     = raw_data(frame.capture_hint),
		capture_hint_len = u32(len(frame.capture_hint)),
		captured         = u32(frame.captured),
		palette_open     = u32(frame.palette_open),
	}
	hints: [16]Ui_Hint
	hint_count := min(len(frame.menu.hints), len(hints))
	for hint, index in frame.menu.hints[:hint_count] {
		hints[index] = {
			keys       = raw_data(hint.keys),
			keys_len   = u32(len(hint.keys)),
			action     = raw_data(hint.action),
			action_len = u32(len(hint.action)),
		}
	}
	menu := Ui_Menu {
		open       = frame.snapshot.menu_open,
		title      = raw_data(frame.menu.title),
		title_len  = u32(len(frame.menu.title)),
		note       = raw_data(frame.menu.note),
		note_len   = u32(len(frame.menu.note)),
		hints      = raw_data(hints[:hint_count]),
		hint_count = u32(hint_count),
	}
	palette_source := frame.palette
	palette_items: [12]Ui_Palette_Item
	palette_item_count := min(len(palette_source.items), len(palette_items))
	for &item, index in palette_source.items[:palette_item_count] {
		palette_items[index] = {
			name           = raw_data(item.name),
			name_len       = u32(len(item.name)),
			short          = raw_data(item.short_name),
			short_len      = u32(len(item.short_name)),
			half_extents   = item.half_extents,
			color          = item.color,
			base_pitch     = item.base_pitch,
			body           = raw_data(item.body),
			body_len       = u32(len(item.body)),
			key            = raw_data(item.key),
			key_len        = u32(len(item.key)),
			light_line     = raw_data(item.light_line[:item.light_length]),
			light_line_len = u32(item.light_length),
			emissive       = u32(item.emissive),
		}
	}
	palette_hints: [8]Ui_Hint
	palette_hint_count := min(len(palette_source.hints), len(palette_hints))
	for hint, index in palette_source.hints[:palette_hint_count] {
		palette_hints[index] = {
			keys       = raw_data(hint.keys),
			keys_len   = u32(len(hint.keys)),
			action     = raw_data(hint.action),
			action_len = u32(len(hint.action)),
		}
	}
	palette_c := Ui_Palette {
		open       = u32(palette_source.open),
		title      = raw_data(palette_source.title),
		title_len  = u32(len(palette_source.title)),
		items      = raw_data(palette_items[:palette_item_count]),
		item_count = u32(palette_item_count),
		selected   = u32(palette_source.selected),
		body       = raw_data(palette_source.body),
		body_len   = u32(len(palette_source.body)),
		size       = raw_data(palette_source.size[:palette_source.size_length]),
		size_len   = u32(palette_source.size_length),
		count      = raw_data(palette_source.count[:palette_source.count_length]),
		count_len  = u32(palette_source.count_length),
		hints      = raw_data(palette_hints[:palette_hint_count]),
		hint_count = u32(palette_hint_count),
	}
	settings_options: Ui_Settings_Options
	settings := ui_settings_frame(&frame.settings, &settings_options)
	if ui_frame(frame.dt, &snapshot, &panel, &menu, &settings, &palette_c, raw_data(events[:count]), u32(count)) != 0 {
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

ui_click_at :: proc(x, y: f32) -> []Ui_Action {
	if ui_click_point(x, y) != 0 {
		return nil
	}
	return ui_actions_slice()
}

ui_click_key :: proc(key: string) -> []Ui_Action {
	if ui_click_element(raw_data(key), u32(len(key))) != 0 {
		return nil
	}
	return ui_actions_slice()
}
