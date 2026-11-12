#+vet explicit-allocators
package game

palette_create :: proc(prefab_id: Prefab_Id) -> Palette {
	return {
		selected = prefab_id,
		body_mode = prefab(prefab_id).body_mode,
		light = prefab_light(prefab_id),
	}
}

palette_selected :: proc(palette: Palette) -> Prefab_Id {
	return palette.selected
}

palette_select :: proc(palette: ^Palette, index: int) -> bool {
	if index < 0 || index >= PREFAB_COUNT {
		return false
	}
	// A repeat selection keeps the tuned body and light; a new prefab restores its
	// defaults.
	if index != int(palette.selected) {
		palette.selected = Prefab_Id(index)
		palette.body_mode = prefab(Prefab_Id(index)).body_mode
		palette.light = prefab_light(Prefab_Id(index))
	}
	return true
}

palette_set_light :: proc(palette: ^Palette, settings: Light_Settings) {
	if palette.light.active && palette.light.kind != settings.kind {
		palette.body_mode = lamp_kind_body(settings.kind)
	}
	palette.light = settings
}

palette_light :: proc(palette: Palette) -> Light_Settings {
	settings := palette.light
	if !settings.active {
		settings = prefab_light(palette_selected(palette))
	}
	return settings
}

@(private)
editor_palette_open :: proc(editor: ^Editor) -> Edit_Result {
	if _, armed := editor.tool.(Placement); armed {
		return edit_fail(.Placement_Armed)
	}
	if _, open := editor.tool.(Palette); open {
		return edit_ok()
	}
	editor_end_drag(editor)
	editor.tool = palette_create(.Crate)
	return edit_ok()
}

@(private)
editor_palette_close :: proc(editor: ^Editor) -> Edit_Result {
	switch _ in editor.tool {
	case Palette:
		editor.tool = Tool_None{}
	case Placement:
		return edit_fail(.Placement_Armed)
	case Tool_None:
	}
	return edit_ok()
}

@(private)
editor_palette_select :: proc(editor: ^Editor, index: int) -> Edit_Result {
	palette, open := editor.tool.(Palette)
	if !open {
		return editor_palette_not_open(editor)
	}
	if !palette_select(&palette, index) {
		return edit_fail(.Bad_Index)
	}
	editor.tool = palette
	return edit_ok()
}

@(private)
editor_palette_step :: proc(editor: ^Editor, delta: int) -> Edit_Result {
	palette, open := editor.tool.(Palette)
	if !open {
		return editor_palette_not_open(editor)
	}
	if delta == 0 {
		return edit_ok()
	}
	index := (int(palette.selected) + delta) % PREFAB_COUNT
	if index < 0 {
		index += PREFAB_COUNT
	}
	return editor_palette_select(editor, index)
}

@(private)
editor_palette_flip_body :: proc(editor: ^Editor) -> Edit_Result {
	palette, open := editor.tool.(Palette)
	if !open {
		return editor_palette_not_open(editor)
	}
	mode: Body_Mode = palette.body_mode == .Static ? .Dynamic : .Static
	return editor_set_next_body(editor, mode)
}

@(private)
editor_palette_pick :: proc(editor: ^Editor, sim: ^Simulation) -> Edit_Result {
	palette, open := editor.tool.(Palette)
	if !open {
		return editor_palette_not_open(editor)
	}
	return editor_placement_arm(editor, sim, palette_selected(palette))
}

@(private)
editor_palette_not_open :: proc(editor: ^Editor) -> Edit_Result {
	if _, armed := editor.tool.(Placement); armed {
		return edit_fail(.Placement_Armed)
	}
	return edit_fail(.Palette_Closed)
}
