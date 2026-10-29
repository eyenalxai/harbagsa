#+vet explicit-allocators
#+vet !unused-procedures // the agent harness calls this API; the game binary does not
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
	if prefab_has_light(palette_selected(palette^)) {
		light := palette.light
		light.kind = lamp_kind_for_body(mode)
		palette.light = light
	}
}

palette_flip_body :: proc(palette: ^Palette) {
	mode := palette.body_mode == .Static ? Body_Mode.Dynamic : Body_Mode.Static
	palette_set_body(palette, mode)
}
