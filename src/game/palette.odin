#+vet explicit-allocators
#+vet !unused-procedures // the agent harness and tests call this API; the game binary does not
package game

Palette :: struct {
	open:      bool,
	selected:  int,
	body_mode: Body_Mode,
	light:     Light_Settings,
}

palette_selected :: proc(palette: Palette) -> Prefab_Id {
	return Prefab_Id(palette.selected)
}

palette_open :: proc(palette: ^Palette) {
	palette.open = true
}

palette_close :: proc(palette: ^Palette) {
	palette.open = false
}

palette_select :: proc(palette: ^Palette, index: int) -> bool {
	if index < 0 || index >= PREFAB_COUNT {
		return false
	}
	// A repeat selection keeps the tuned body and light; a new prefab restores its
	// defaults.
	if index != palette.selected {
		palette.selected = index
		palette.body_mode = prefab(Prefab_Id(index)).body_mode
		palette.light = prefab_light(Prefab_Id(index))
	}
	return true
}

palette_set_light :: proc(palette: ^Palette, settings: Light_Settings) {
	palette.light = settings
}

palette_set_body :: proc(palette: ^Palette, mode: Body_Mode) {
	palette.body_mode = mode
}

palette_flip_body :: proc(palette: ^Palette) {
	palette.body_mode = palette.body_mode == .Static ? .Dynamic : .Static
}

debug_palette_open :: proc(dm: ^Debug_Mode) {
	debug_placement_cancel(dm)
	debug_sun_cancel(dm)
	palette_open(&dm.palette)
}

debug_palette_close :: proc(dm: ^Debug_Mode) {
	palette_close(&dm.palette)
}

debug_palette_select :: proc(dm: ^Debug_Mode, index: int) -> bool {
	selected := palette_select(&dm.palette, index)
	if selected && dm.placement.armed {
		dm.placement.prefab = palette_selected(dm.palette)
	}
	return selected
}

debug_palette_set_body :: proc(dm: ^Debug_Mode, mode: Body_Mode) {
	palette_set_body(&dm.palette, mode)
}

debug_palette_flip_body :: proc(dm: ^Debug_Mode) {
	palette_flip_body(&dm.palette)
}

debug_palette_pick :: proc(dm: ^Debug_Mode, sim: ^Simulation) -> bool {
	if !debug_placement_arm(dm, sim, palette_selected(dm.palette)) {
		return false
	}
	palette_close(&dm.palette)
	return true
}
