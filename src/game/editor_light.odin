#+vet explicit-allocators
#+vet !unused-procedures // the agent harness calls this API; the game binary does not
package game

Light_Edit_Target :: enum {
	None,
	Next_Placement,
	Object,
}

// The keyboard and the harness share one rule: the open palette or the armed
// placement owns the next light, a selected lamp tunes itself, and any other
// target refuses the change.
@(private)
light_target :: proc(
	editor: ^Editor,
	sim: ^Simulation,
) -> (
	target: Light_Edit_Target,
	id: Object_Id,
	settings: Light_Settings,
	ok: bool,
) {
	switch tool in editor.tool {
	case Palette:
		if !prefab_has_light(palette_selected(tool)) {
			return .None, INVALID_OBJECT_ID, {}, false
		}
		return .Next_Placement, INVALID_OBJECT_ID, palette_light(tool), true
	case Placement:
		if !prefab_has_light(tool.prefab) {
			return .None, INVALID_OBJECT_ID, {}, false
		}
		return .Next_Placement, INVALID_OBJECT_ID, tool.light, true
	case Tool_None:
	}
	if selected_id, selected := editor_selected_object_id(editor, sim); selected {
		object, found := simulation_object_find(sim, selected_id)
		if !found || !object.light.active {
			return .None, INVALID_OBJECT_ID, {}, false
		}
		return .Object, selected_id, object.light, true
	}
	return .None, INVALID_OBJECT_ID, {}, false
}

@(private)
editor_light_change :: proc(
	editor: ^Editor,
	sim: ^Simulation,
	change: Light_Change,
) -> Edit_Result {
	target, id, settings, ok := light_target(editor, sim)
	if !ok {
		return edit_fail(.No_Lamp)
	}
	return editor_light_apply(editor, sim, target, id, settings, light_adjust(settings, change))
}

@(private)
editor_light_set_color :: proc(
	editor: ^Editor,
	sim: ^Simulation,
	color: Light_Color,
) -> Edit_Result {
	target, id, settings, ok := light_target(editor, sim)
	if !ok {
		return edit_fail(.No_Lamp)
	}
	return editor_light_apply(editor, sim, target, id, settings, light_with_color(settings, color))
}

@(private)
editor_light_set_intensity :: proc(
	editor: ^Editor,
	sim: ^Simulation,
	intensity: f32,
) -> Edit_Result {
	target, id, settings, ok := light_target(editor, sim)
	if !ok {
		return edit_fail(.No_Lamp)
	}
	return editor_light_apply(
		editor,
		sim,
		target,
		id,
		settings,
		light_with_intensity(settings, intensity),
	)
}

@(private)
editor_light_set_range :: proc(
	editor: ^Editor,
	sim: ^Simulation,
	range: f32,
) -> Edit_Result {
	target, id, settings, ok := light_target(editor, sim)
	if !ok {
		return edit_fail(.No_Lamp)
	}
	return editor_light_apply(editor, sim, target, id, settings, light_with_range(settings, range))
}

@(private)
editor_light_set_kind :: proc(
	editor: ^Editor,
	sim: ^Simulation,
	kind: Lamp_Kind,
) -> Edit_Result {
	target, id, settings, ok := light_target(editor, sim)
	if !ok {
		return edit_fail(.No_Lamp)
	}
	return editor_light_apply(editor, sim, target, id, settings, light_with_kind(settings, kind))
}

@(private)
editor_light_toggle_kind :: proc(editor: ^Editor, sim: ^Simulation) -> Edit_Result {
	target, id, settings, ok := light_target(editor, sim)
	if !ok {
		return edit_fail(.No_Lamp)
	}
	kind: Lamp_Kind = .Dynamic_Lamp
	if settings.kind == .Dynamic_Lamp {
		kind = .Static_Fixture
	}
	return editor_light_apply(editor, sim, target, id, settings, light_with_kind(settings, kind))
}

@(private)
editor_light_apply :: proc(
	editor: ^Editor,
	sim: ^Simulation,
	target: Light_Edit_Target,
	id: Object_Id,
	settings, next: Light_Settings,
) -> Edit_Result {
	if next == settings {
		return edit_ok()
	}
	switch target {
	case .None:
		return edit_fail(.Failed)
	case .Next_Placement:
		editor_set_next_light(editor, next)
		return edit_ok()
	case .Object:
		result, _ := object_history_apply(
			editor_history(editor),
			sim,
			History_Light{id = id, previous_kind = settings.kind, next = next},
		)
		if !result.applied {
			return result
		}
		return edit_ok()
	}
	return edit_fail(.Failed)
}

@(private)
editor_set_next_light :: proc(editor: ^Editor, settings: Light_Settings) {
	switch tool in editor.tool {
	case Palette:
		palette := tool
		palette_set_light(&palette, settings)
		editor.tool = palette
	case Placement:
		placement := tool
		if placement.light.active && placement.light.kind != settings.kind {
			placement.body_mode = lamp_kind_body(settings.kind)
		}
		placement.light = settings
		editor.tool = placement
	case Tool_None:
	}
}
