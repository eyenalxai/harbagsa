#+vet explicit-allocators
#+vet !unused-procedures // the frame package builds the view
package game

import "core:fmt"

import "src:ui"

PALETTE_TITLE :: "Object palette"
PALETTE_KEY_COUNT :: 9

PALETTE_KEYS := [PALETTE_KEY_COUNT]string{"1", "2", "3", "4", "5", "6", "7", "8", "9"}

PALETTE_HINTS := [5]ui.Hint_Cell {
	{keys = "1-9", action = "select"},
	{keys = "Arrows", action = "move"},
	{keys = "Enter", action = "pick"},
	{keys = "M", action = "body"},
	{keys = "Esc", action = "close"},
}

PALETTE_LIGHT_HINT :: ui.Hint_Cell{keys = "C [ ] , . K", action = "light / kind"}

debug_palette_view :: proc(sim: ^Simulation, debug: ^Debug_Mode) -> ui.Palette {
	palette: ui.Palette
	palette.open = debug.active && debug.palette.open
	if !palette.open {
		return palette
	}
	palette.title = PALETTE_TITLE
	palette.selected = debug.palette.selected
	palette.body = body_mode_name(debug.palette.body_mode)

	count := min(PREFAB_COUNT, ui.PALETTE_MAX_ITEMS)
	for id, index in Prefab_Id {
		if index >= count {
			break
		}
		info := PREFABS[id]
		key := ""
		if index < len(PALETTE_KEYS) {
			key = PALETTE_KEYS[index]
		}
		item := ui.Palette_Item {
			name = info.name,
			short_name = info.short_name,
			half_extents = info.half_extents,
			color = prefab_color(id),
			base_pitch = info.base_pitch,
			body = body_mode_name(info.body_mode),
			key = key,
			emissive = info.light.active,
		}
		if info.light.active {
			item.light_length = write_light_line(
				item.light_line[:],
				prefab_light(id),
			)
		}
		palette.items[index] = item
	}
	palette.item_count = count
	palette_light_preview(&palette, debug, count)

	if palette.selected >= 0 && palette.selected < count {
		info := PREFABS[Prefab_Id(palette.selected)]
		size := fmt.bprintf(
			palette.size[:],
			"%.1f × %.1f × %.1f m",
			info.half_extents.x * 2.0,
			info.half_extents.y * 2.0,
			info.half_extents.z * 2.0,
		)
		palette.size_length = len(size)
	}
	count_text := fmt.bprintf(
		palette.count[:],
		"%d",
		simulation_object_count(sim),
	)
	palette.count_length = len(count_text)

	hint_count := len(PALETTE_HINTS)
	for hint, index in PALETTE_HINTS {
		palette.hints[index] = hint
	}
	if palette.selected >= 0 && prefab_has_light(palette_selected(debug.palette)) {
		palette.hints[hint_count] = PALETTE_LIGHT_HINT
		hint_count += 1
	}
	palette.hint_count = hint_count
	return palette
}

// The preview wants the tuned next placement, not the catalog default, so the
// selected card carries the colour the ghost and the next placement will use.
@(private)
palette_light_preview :: proc(palette: ^ui.Palette, debug: ^Debug_Mode, count: int) {
	if palette.selected < 0 || palette.selected >= count {
		return
	}
	id := palette_selected(debug.palette)
	if !prefab_has_light(id) {
		return
	}
	light := placement_light_for(debug, id)
	item := &palette.items[palette.selected]
	item.color = light_color4(light.color)
	item.light_length = write_light_line(item.light_line[:], light)
}

@(private)
write_light_line :: proc(buffer: []u8, light: Light_Settings) -> int {
	text := fmt.bprintf(
		buffer,
		"%s %s · %.1f · %.0f m",
		lamp_kind_name(light.kind),
		light_color_name(light.color),
		light.intensity,
		light.range,
	)
	return len(text)
}
