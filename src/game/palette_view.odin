#+vet explicit-allocators
#+vet !unused-procedures // the frame tests build the view through frame
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
		palette.items[index] = {
			name = info.name,
			short_name = info.short_name,
			half_extents = info.half_extents,
			color = info.color,
			base_pitch = info.base_pitch,
			body = body_mode_name(info.body_mode),
			key = key,
		}
	}
	palette.item_count = count

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
		"%d / %d",
		simulation_object_count(sim),
		MAX_PLACED_OBJECTS,
	)
	palette.count_length = len(count_text)

	for hint, index in PALETTE_HINTS {
		palette.hints[index] = hint
	}
	palette.hint_count = len(PALETTE_HINTS)
	return palette
}
