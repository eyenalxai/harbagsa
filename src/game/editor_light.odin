#+vet explicit-allocators
package game

Light_Edit_Target :: enum {
	None,
	Next_Placement,
	Object,
}

Light_Target :: struct {
	kind:     Light_Edit_Target,
	id:       Object_Id,
	settings: Light_Settings,
	ok:       bool,
}

Light_Edit_Adjust :: struct {
	change: Light_Change,
}
Light_Edit_Color :: struct {
	color: Light_Color,
}
Light_Edit_Intensity :: struct {
	intensity: f32,
}
Light_Edit_Range :: struct {
	range: f32,
}
Light_Edit_Kind :: struct {
	kind: Lamp_Kind,
}
Light_Edit_Toggle :: struct {}

Light_Edit :: union #no_nil {
	Light_Edit_Adjust,
	Light_Edit_Color,
	Light_Edit_Intensity,
	Light_Edit_Range,
	Light_Edit_Kind,
	Light_Edit_Toggle,
}

// The keyboard and the harness share one rule: the open palette or the armed
// placement owns the next light, a selected lamp tunes itself, and any other
// target refuses the change.
@(private)
light_target :: proc(editor: ^Editor, sim: ^Simulation) -> Light_Target {
	switch tool in editor.tool {
	case Palette:
		if !prefab_has_light(palette_selected(tool)) {
			return {}
		}
		return {kind = .Next_Placement, settings = palette_light(tool), ok = true}
	case Placement:
		if !prefab_has_light(tool.prefab) {
			return {}
		}
		return {kind = .Next_Placement, settings = tool.light, ok = true}
	case Tool_None:
	}
	if selected_id, selected := editor_selected_object_id(editor, sim); selected {
		object, found := simulation_object_find(sim, selected_id)
		if !found || !object.light.active {
			return {}
		}
		return {kind = .Object, id = selected_id, settings = object.light, ok = true}
	}
	return {}
}

@(private)
editor_light_edit :: proc(
	editor: ^Editor,
	sim: ^Simulation,
	edit: Light_Edit,
) -> Edit_Result {
	target := light_target(editor, sim)
	if !target.ok {
		return edit_fail(.No_Lamp)
	}
	next := target.settings
	switch value in edit {
	case Light_Edit_Adjust:
		next = light_adjust(target.settings, value.change)
	case Light_Edit_Color:
		next = light_with_color(target.settings, value.color)
	case Light_Edit_Intensity:
		next = light_with_intensity(target.settings, value.intensity)
	case Light_Edit_Range:
		next = light_with_range(target.settings, value.range)
	case Light_Edit_Kind:
		next = light_with_kind(target.settings, value.kind)
	case Light_Edit_Toggle:
		kind: Lamp_Kind = .Dynamic_Lamp
		if target.settings.kind == .Dynamic_Lamp {
			kind = .Static_Fixture
		}
		next = light_with_kind(target.settings, kind)
	}
	return editor_light_apply(editor, sim, target, next)
}

@(private)
editor_light_apply :: proc(
	editor: ^Editor,
	sim: ^Simulation,
	target: Light_Target,
	next: Light_Settings,
) -> Edit_Result {
	if next == target.settings {
		return edit_ok()
	}
	switch target.kind {
	case .None:
		return edit_fail(.Failed)
	case .Next_Placement:
		editor_set_next_light(editor, next)
		return edit_ok()
	case .Object:
		result, _ := object_history_apply(
			editor_history(editor),
			sim,
			History_Light{id = target.id, previous_kind = target.settings.kind, next = next},
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
