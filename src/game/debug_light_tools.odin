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
// selection swallows the key.
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

debug_light_change :: proc(dm: ^Debug_Mode, sim: ^Simulation, change: Light_Change) -> bool {
	target, id, settings, ok := light_target(dm, sim)
	if !ok {
		return false
	}
	next := light_adjust(settings, change)
	if next == settings {
		return true
	}
	return light_store(dm, sim, target, id, next)
}

debug_light_set_color :: proc(dm: ^Debug_Mode, sim: ^Simulation, color: Light_Color) -> bool {
	target, id, settings, ok := light_target(dm, sim)
	if !ok {
		return false
	}
	next := light_with_color(settings, color)
	if next == settings {
		return true
	}
	return light_store(dm, sim, target, id, next)
}

debug_light_set_intensity :: proc(dm: ^Debug_Mode, sim: ^Simulation, intensity: f32) -> bool {
	target, id, settings, ok := light_target(dm, sim)
	if !ok {
		return false
	}
	next := light_with_intensity(settings, intensity)
	if next == settings {
		return true
	}
	return light_store(dm, sim, target, id, next)
}

debug_light_set_range :: proc(dm: ^Debug_Mode, sim: ^Simulation, range: f32) -> bool {
	target, id, settings, ok := light_target(dm, sim)
	if !ok {
		return false
	}
	next := light_with_range(settings, range)
	if next == settings {
		return true
	}
	return light_store(dm, sim, target, id, next)
}

debug_edit_lights :: proc(dm: ^Debug_Mode, sim: ^Simulation, input: Debug_Input) {
	if input.light_color_pressed {
		_ = debug_light_change(dm, sim, .Color)
	}
	if input.light_intensity_down_pressed {
		_ = debug_light_change(dm, sim, .Intensity_Down)
	}
	if input.light_intensity_up_pressed {
		_ = debug_light_change(dm, sim, .Intensity_Up)
	}
	if input.light_range_down_pressed {
		_ = debug_light_change(dm, sim, .Range_Down)
	}
	if input.light_range_up_pressed {
		_ = debug_light_change(dm, sim, .Range_Up)
	}
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
