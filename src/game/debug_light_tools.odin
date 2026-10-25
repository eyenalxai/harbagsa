#+vet explicit-allocators
#+vet !unused-procedures // the agent harness and tests call this API; the game binary does not
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
	if dm.palette.open || dm.placement.armed {
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
	if dm.sun.active {
		return edit_fail(.Sun_Active)
	}
	target, id, settings, ok := light_target(dm, sim)
	if !ok {
		return edit_fail(.No_Lamp)
	}
	next := light_adjust(settings, change)
	if next == settings {
		return edit_ok()
	}
	if !light_store(dm, sim, target, id, next) {
		return edit_fail(.Failed)
	}
	return edit_ok()
}

@(private)
edit_light_set_color :: proc(dm: ^Debug_Mode, sim: ^Simulation, color: Light_Color) -> Edit_Result {
	if dm.sun.active {
		return edit_fail(.Sun_Active)
	}
	target, id, settings, ok := light_target(dm, sim)
	if !ok {
		return edit_fail(.No_Lamp)
	}
	next := light_with_color(settings, color)
	if next == settings {
		return edit_ok()
	}
	if !light_store(dm, sim, target, id, next) {
		return edit_fail(.Failed)
	}
	return edit_ok()
}

@(private)
edit_light_set_intensity :: proc(
	dm: ^Debug_Mode,
	sim: ^Simulation,
	intensity: f32,
) -> Edit_Result {
	if dm.sun.active {
		return edit_fail(.Sun_Active)
	}
	target, id, settings, ok := light_target(dm, sim)
	if !ok {
		return edit_fail(.No_Lamp)
	}
	next := light_with_intensity(settings, intensity)
	if next == settings {
		return edit_ok()
	}
	if !light_store(dm, sim, target, id, next) {
		return edit_fail(.Failed)
	}
	return edit_ok()
}

@(private)
edit_light_set_range :: proc(dm: ^Debug_Mode, sim: ^Simulation, range: f32) -> Edit_Result {
	if dm.sun.active {
		return edit_fail(.Sun_Active)
	}
	target, id, settings, ok := light_target(dm, sim)
	if !ok {
		return edit_fail(.No_Lamp)
	}
	next := light_with_range(settings, range)
	if next == settings {
		return edit_ok()
	}
	if !light_store(dm, sim, target, id, next) {
		return edit_fail(.Failed)
	}
	return edit_ok()
}

@(private)
light_store :: proc(
	dm: ^Debug_Mode,
	sim: ^Simulation,
	target: Light_Edit_Target,
	id: Object_Id,
	settings: Light_Settings,
) -> bool {
	switch target {
	case .None:
		return false
	case .Palette:
		palette_set_light(&dm.palette, settings)
		return true
	case .Object:
		object_history_record(debug_history(dm), sim)
		return simulation_set_object_light(sim, id, settings)
	}
	return false
}

@(private)
palette_light :: proc(dm: ^Debug_Mode) -> Light_Settings {
	settings := dm.palette.light
	if !settings.active {
		settings = prefab_light(palette_selected(dm.palette))
	}
	return settings
}
