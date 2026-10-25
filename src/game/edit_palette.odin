#+vet explicit-allocators
#+vet !unused-procedures // the agent harness and tests call this API; the game binary does not
package game

@(private)
edit_palette_open :: proc(dm: ^Debug_Mode) -> Edit_Result {
	take_tool(dm, .Palette)
	debug_mode_end_drag(dm)
	palette_open(&dm.palette)
	return edit_ok()
}

@(private)
edit_palette_close :: proc(dm: ^Debug_Mode) -> Edit_Result {
	palette_close(&dm.palette)
	return edit_ok()
}

@(private)
edit_palette_select :: proc(dm: ^Debug_Mode, index: int) -> Edit_Result {
	if !palette_select(&dm.palette, index) {
		return edit_fail(.Bad_Index)
	}
	if dm.placement.armed {
		dm.placement.prefab = palette_selected(dm.palette)
	}
	return edit_ok()
}

@(private)
edit_palette_step :: proc(dm: ^Debug_Mode, delta: int) -> Edit_Result {
	if delta == 0 {
		return edit_ok()
	}
	index := (dm.palette.selected + delta) % PREFAB_COUNT
	if index < 0 {
		index += PREFAB_COUNT
	}
	return edit_palette_select(dm, index)
}

@(private)
edit_palette_flip_body :: proc(dm: ^Debug_Mode) -> Edit_Result {
	palette_flip_body(&dm.palette)
	return edit_ok()
}

@(private)
edit_palette_pick :: proc(dm: ^Debug_Mode, sim: ^Simulation) -> Edit_Result {
	if !edit_placement_arm(dm, sim, palette_selected(dm.palette)).applied {
		return edit_fail(.Failed)
	}
	palette_close(&dm.palette)
	return edit_ok()
}

