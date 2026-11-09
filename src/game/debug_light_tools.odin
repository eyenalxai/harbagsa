#+vet explicit-allocators
#+vet !unused-procedures // the agent harness calls this API; the game binary does not
package game

Light_Edit_Target :: enum {
	None,
	Palette,
	Object,
}

// The keyboard and the harness share one rule: the open palette or the armed
// tool tunes the next placement, a selected lamp tunes itself, and a non-lamp
// target refuses the change.
@(private)
light_target :: proc(
	dm: ^Debug_Mode,
	sim: ^Simulation,
) -> (
	target: Light_Edit_Target,
	id: Object_Id,
	settings: Light_Settings,
	ok: bool,
) {
	if editor_uses_next_placement(dm) {
		if !prefab_has_light(palette_selected(dm.palette)) {
			return .None, INVALID_OBJECT_ID, {}, false
		}
		return .Palette, INVALID_OBJECT_ID, palette_light(dm), true
	}
	if selected_id, selected := debug_selected_object_id(dm, sim); selected {
		object, found := simulation_object_find(sim, selected_id)
		if !found || !object.light.active {
			return .None, INVALID_OBJECT_ID, {}, false
		}
		return .Object, selected_id, object.light, true
	}
	if !prefab_has_light(palette_selected(dm.palette)) {
		return .None, INVALID_OBJECT_ID, {}, false
	}
	return .Palette, INVALID_OBJECT_ID, palette_light(dm), true
}

@(private)
edit_light_change :: proc(dm: ^Debug_Mode, sim: ^Simulation, change: Light_Change) -> Edit_Result {
	target, id, settings, ok := light_target(dm, sim)
	if !ok {
		return edit_fail(.No_Lamp)
	}
	return light_apply(dm, sim, target, id, settings, light_adjust(settings, change))
}

@(private)
edit_light_set_color :: proc(dm: ^Debug_Mode, sim: ^Simulation, color: Light_Color) -> Edit_Result {
	target, id, settings, ok := light_target(dm, sim)
	if !ok {
		return edit_fail(.No_Lamp)
	}
	return light_apply(dm, sim, target, id, settings, light_with_color(settings, color))
}

@(private)
edit_light_set_intensity :: proc(
	dm: ^Debug_Mode,
	sim: ^Simulation,
	intensity: f32,
) -> Edit_Result {
	target, id, settings, ok := light_target(dm, sim)
	if !ok {
		return edit_fail(.No_Lamp)
	}
	return light_apply(dm, sim, target, id, settings, light_with_intensity(settings, intensity))
}

@(private)
edit_light_set_range :: proc(dm: ^Debug_Mode, sim: ^Simulation, range: f32) -> Edit_Result {
	target, id, settings, ok := light_target(dm, sim)
	if !ok {
		return edit_fail(.No_Lamp)
	}
	return light_apply(dm, sim, target, id, settings, light_with_range(settings, range))
}

@(private)
edit_light_set_kind :: proc(dm: ^Debug_Mode, sim: ^Simulation, kind: Lamp_Kind) -> Edit_Result {
	target, id, settings, ok := light_target(dm, sim)
	if !ok {
		return edit_fail(.No_Lamp)
	}
	return light_apply_kind(dm, sim, target, id, settings, kind)
}

@(private)
edit_light_toggle_kind :: proc(dm: ^Debug_Mode, sim: ^Simulation) -> Edit_Result {
	target, id, settings, ok := light_target(dm, sim)
	if !ok {
		return edit_fail(.No_Lamp)
	}
	kind: Lamp_Kind = .Dynamic_Lamp
	if settings.kind == .Dynamic_Lamp {
		kind = .Static_Fixture
	}
	return light_apply_kind(dm, sim, target, id, settings, kind)
}

@(private)
light_apply_kind :: proc(
	dm: ^Debug_Mode,
	sim: ^Simulation,
	target: Light_Edit_Target,
	id: Object_Id,
	settings: Light_Settings,
	kind: Lamp_Kind,
) -> Edit_Result {
	return light_apply(dm, sim, target, id, settings, light_with_kind(settings, kind))
}

@(private)
light_apply :: proc(
	dm: ^Debug_Mode,
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
	case .Palette:
		palette_set_light(&dm.palette, next)
		return edit_ok()
	case .Object:
		result, _ := object_history_apply(
			debug_history(dm),
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
palette_light :: proc(dm: ^Debug_Mode) -> Light_Settings {
	settings := dm.palette.light
	if !settings.active {
		settings = prefab_light(palette_selected(dm.palette))
	}
	return settings
}
