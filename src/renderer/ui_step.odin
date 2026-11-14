#+vet explicit-allocators
package renderer

import "core:log"

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
	snapshot.viewport_width = f32(width) / scale
	snapshot.viewport_height = f32(height) / scale
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
	palette_item_count := min(palette_source.item_count, len(palette_items))
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
	palette_hint_count := min(palette_source.hint_count, len(palette_hints))
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
		hints      = raw_data(palette_hints[:palette_hint_count]),
		hint_count = u32(palette_hint_count),
	}
	settings_options: Ui_Settings_Options
	settings := ui_settings_frame(&frame.settings, &settings_options)
	inspector_source := frame.inspector
	inspector := Ui_Inspector {
		open                  = u32(inspector_source.open),
		has_selection         = u32(inspector_source.has_selection),
		object_id             = inspector_source.object_id,
		selection             = raw_data(inspector_source.selection),
		selection_len         = u32(len(inspector_source.selection)),
		body                  = u32(inspector_source.body),
		yaw_degrees           = inspector_source.yaw_degrees,
		yaw_text              = raw_data(inspector_source.yaw_text),
		yaw_text_len          = u32(len(inspector_source.yaw_text)),
		placement_prefab      = raw_data(inspector_source.placement_prefab),
		placement_prefab_len  = u32(len(inspector_source.placement_prefab)),
		placement_text        = raw_data(inspector_source.placement_text),
		placement_text_len    = u32(len(inspector_source.placement_text)),
		has_lamp              = u32(inspector_source.has_lamp),
		lamp_kind             = u32(inspector_source.lamp_kind),
		lamp_color            = u32(inspector_source.lamp_color),
		lamp_intensity        = inspector_source.lamp_intensity,
		lamp_range            = inspector_source.lamp_range,
		lamp_intensity_text   = raw_data(inspector_source.lamp_intensity_text),
		lamp_intensity_len    = u32(len(inspector_source.lamp_intensity_text)),
		lamp_range_text       = raw_data(inspector_source.lamp_range_text),
		lamp_range_len        = u32(len(inspector_source.lamp_range_text)),
		lamp_colors           = inspector_source.lamp_colors,
		type_weight           = inspector_source.type_weight,
		type_weight_text      = raw_data(inspector_source.type_weight_text),
		type_weight_len       = u32(len(inspector_source.type_weight_text)),
		physics_debug         = u32(inspector_source.physics_debug),
	}
	if ui_frame(frame.dt, &snapshot, &panel, &menu, &settings, &palette_c, &inspector, raw_data(events[:count]), u32(count)) != 0 {
		log.error("renderer: the UI shim could not step")
	}
}

