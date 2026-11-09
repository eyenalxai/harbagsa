#+vet explicit-allocators
#+vet !unused-procedures // the agent harness calls this API; the game binary does not
package game

import b3 "libs:box3d"

@(private)
edit_world_reason :: proc(dm: ^Debug_Mode) -> Edit_Reason {
	switch active_tool(dm) {
	case .Palette:
		return .Palette_Open
	case .Placement:
		return .Placement_Armed
	case .None:
	}
	return .None
}

@(private)
selected_object :: proc(dm: ^Debug_Mode, sim: ^Simulation) -> (Placed_Object, bool) {
	id, ok := debug_selected_object_id(dm, sim)
	if !ok {
		return {}, false
	}
	return simulation_object_find(sim, id)
}

@(private)
commit_move :: proc(
	dm: ^Debug_Mode,
	sim: ^Simulation,
	object: Placed_Object,
	target: b3.Vec3,
	record: bool,
) -> Edit_Result {
	if !b3.Body_IsValid(object.body) {
		return edit_fail(.Failed)
	}
	resolved := target
	resolved.y = max(resolved.y, prefab(object.prefab).half_extents.y)
	if resolved == b3.Body_GetPosition(object.body) {
		return edit_no_change()
	}
	if record {
		result, _ := object_history_apply(
			debug_history(dm),
			sim,
			History_Move{id = object.id, center = resolved},
		)
		if !result.applied {
			return result
		}
	} else if !simulation_move_object(sim, object.id, resolved) {
		return edit_fail(.Failed)
	}
	dm.drag_position = resolved
	return edit_ok()
}

@(private)
edit_select_object :: proc(dm: ^Debug_Mode, sim: ^Simulation, id: Object_Id) -> Edit_Result {
	debug_mode_end_drag(dm)
	if id == INVALID_OBJECT_ID {
		debug_mode_clear_selection(dm)
		return edit_ok()
	}
	if _, ok := simulation_object_find(sim, id); !ok {
		return edit_fail(.Unknown_Object)
	}
	dm.selection = .Object
	dm.selected_object_id = id
	dm.drag_position = simulation_object_box(sim, id).center
	return edit_ok()
}

@(private)
edit_move_selected :: proc(dm: ^Debug_Mode, sim: ^Simulation, center: b3.Vec3) -> Edit_Result {
	if reason := edit_world_reason(dm); reason != .None {
		return edit_fail(reason)
	}
	object, ok := selected_object(dm, sim)
	if !ok {
		return edit_fail(.No_Selection)
	}
	return commit_move(dm, sim, object, center, true)
}

@(private)
edit_rotate_selected :: proc(dm: ^Debug_Mode, sim: ^Simulation, degrees: f32) -> Edit_Result {
	if reason := edit_world_reason(dm); reason != .None {
		return edit_fail(reason)
	}
	object, ok := selected_object(dm, sim)
	if !ok {
		return edit_fail(.No_Selection)
	}
	if degrees == 0.0 {
		return edit_ok()
	}
	result, _ := object_history_apply(
		debug_history(dm),
		sim,
		History_Rotate{id = object.id, degrees = degrees},
	)
	if !result.applied {
		return result
	}
	return edit_ok()
}

@(private)
edit_turn :: proc(dm: ^Debug_Mode, sim: ^Simulation, steps: int, large: bool) -> Edit_Result {
	if active_tool(dm) == .Placement {
		debug_placement_turn(dm, steps, large)
		return edit_ok()
	}
	step: f32 = large ? PLACEMENT_YAW_STEP_LARGE : PLACEMENT_YAW_STEP
	return edit_rotate_selected(dm, sim, f32(steps) * step)
}

@(private)
edit_set_body :: proc(dm: ^Debug_Mode, sim: ^Simulation, mode: Body_Mode) -> Edit_Result {
	if editor_uses_next_placement(dm) {
		if prefab_has_light(palette_selected(dm.palette)) {
			return edit_fail(.Lamp_Body_Follows_Kind)
		}
		palette_set_body(&dm.palette, mode)
		return edit_ok()
	}
	object, ok := selected_object(dm, sim)
	if !ok {
		if prefab_has_light(palette_selected(dm.palette)) {
			return edit_fail(.Lamp_Body_Follows_Kind)
		}
		palette_set_body(&dm.palette, mode)
		return edit_ok()
	}
	if object.light.active {
		return edit_fail(.Lamp_Body_Follows_Kind)
	}
	if object.body_mode == mode {
		return edit_ok()
	}
	result, _ := object_history_apply(
		debug_history(dm),
		sim,
		History_Convert{id = object.id, mode = mode},
	)
	if !result.applied {
		return result
	}
	return edit_ok()
}

@(private)
edit_flip_body :: proc(dm: ^Debug_Mode, sim: ^Simulation) -> Edit_Result {
	if editor_uses_next_placement(dm) {
		if prefab_has_light(palette_selected(dm.palette)) {
			return edit_fail(.Lamp_Body_Follows_Kind)
		}
		palette_flip_body(&dm.palette)
		return edit_ok()
	}
	object, ok := selected_object(dm, sim)
	if !ok {
		if prefab_has_light(palette_selected(dm.palette)) {
			return edit_fail(.Lamp_Body_Follows_Kind)
		}
		palette_flip_body(&dm.palette)
		return edit_ok()
	}
	if object.light.active {
		return edit_fail(.Lamp_Body_Follows_Kind)
	}
	mode: Body_Mode = object.body_mode == .Static ? .Dynamic : .Static
	result, _ := object_history_apply(
		debug_history(dm),
		sim,
		History_Convert{id = object.id, mode = mode},
	)
	if !result.applied {
		return result
	}
	return edit_ok()
}

@(private)
edit_delete_selected :: proc(dm: ^Debug_Mode, sim: ^Simulation) -> Edit_Result {
	if reason := edit_world_reason(dm); reason != .None {
		return edit_fail(reason)
	}
	object, ok := selected_object(dm, sim)
	if !ok {
		return edit_fail(.No_Selection)
	}
	result, _ := object_history_apply(debug_history(dm), sim, History_Delete{id = object.id})
	if !result.applied {
		return result
	}
	debug_mode_clear_selection(dm)
	return edit_ok()
}

@(private)
edit_duplicate_selected :: proc(dm: ^Debug_Mode, sim: ^Simulation) -> Edit_Result {
	if reason := edit_world_reason(dm); reason != .None {
		return edit_fail(reason)
	}
	object, ok := selected_object(dm, sim)
	if !ok {
		return edit_fail(.No_Selection)
	}

	result, id := object_history_apply(debug_history(dm), sim, History_Duplicate{id = object.id})
	if !result.applied {
		return result
	}
	debug_mode_end_drag(dm)
	dm.selection = .Object
	dm.selected_object_id = id
	dm.drag_position = simulation_object_box(sim, id).center
	return edit_ok()
}

@(private)
edit_undo :: proc(dm: ^Debug_Mode, sim: ^Simulation) -> Edit_Result {
	if reason := edit_world_reason(dm); reason != .None {
		return edit_fail(reason)
	}
	result := object_history_undo(debug_history(dm), sim)
	if !result.applied {
		return result
	}
	debug_mode_end_drag(dm)
	if _, ok := debug_selected_object_id(dm, sim); !ok {
		debug_mode_clear_selection(dm)
	}
	return edit_ok()
}

@(private)
edit_redo :: proc(dm: ^Debug_Mode, sim: ^Simulation) -> Edit_Result {
	if reason := edit_world_reason(dm); reason != .None {
		return edit_fail(reason)
	}
	result := object_history_redo(debug_history(dm), sim)
	if !result.applied {
		return result
	}
	debug_mode_end_drag(dm)
	if _, ok := debug_selected_object_id(dm, sim); !ok {
		debug_mode_clear_selection(dm)
	}
	return edit_ok()
}

