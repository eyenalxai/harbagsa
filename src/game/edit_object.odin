#+vet explicit-allocators
#+vet !unused-procedures // the agent harness and tests call this API; the game binary does not
package game

import "core:math"

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
	object_history_record(debug_history(dm), sim)
	target := center
	target.y = max(target.y, prefab(object.prefab).half_extents.y)
	dm.drag_position = target
	if !simulation_move_object(sim, object.id, target) {
		return edit_fail(.Failed)
	}
	return edit_ok()
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
	object_history_record(debug_history(dm), sim)
	yaw := simulation_object_yaw(sim, object.id) + degrees * math.PI / 180.0
	if !simulation_set_object_yaw(sim, object.id, yaw) {
		return edit_fail(.Failed)
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
		palette_set_body(&dm.palette, mode)
		return edit_ok()
	}
	object, ok := selected_object(dm, sim)
	if !ok {
		palette_set_body(&dm.palette, mode)
		return edit_ok()
	}
	if object.body_mode == mode {
		return edit_ok()
	}
	object_history_record(debug_history(dm), sim)
	if !simulation_convert_object(sim, object.id, mode) {
		return edit_fail(.Failed)
	}
	return edit_ok()
}

@(private)
edit_flip_body :: proc(dm: ^Debug_Mode, sim: ^Simulation) -> Edit_Result {
	if editor_uses_next_placement(dm) {
		palette_flip_body(&dm.palette)
		return edit_ok()
	}
	object, ok := selected_object(dm, sim)
	if !ok {
		palette_flip_body(&dm.palette)
		return edit_ok()
	}
	mode: Body_Mode = object.body_mode == .Static ? .Dynamic : .Static
	object_history_record(debug_history(dm), sim)
	if !simulation_convert_object(sim, object.id, mode) {
		return edit_fail(.Failed)
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
	object_history_record(debug_history(dm), sim)
	if !simulation_remove_object(sim, object.id) {
		return edit_fail(.Failed)
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

	history := debug_history(dm)
	snapshot := object_snapshot_capture(sim, history.allocator)
	spawn := Object_Spawn {
		prefab    = object.prefab,
		body_mode = object.body_mode,
		center    = b3.Body_GetPosition(object.body) + {prefab(object.prefab).half_extents.x, 0.0, 0.0},
		light     = object.light,
	}
	id := create_object_rotated(
		sim,
		spawn,
		b3.Body_GetRotation(object.body),
		object.color,
		object.light,
		false,
	)
	if id == INVALID_OBJECT_ID {
		object_snapshot_destroy(&snapshot, history.allocator)
		return edit_fail(.Failed)
	}
	object_history_push(history, snapshot)
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
	if !object_history_undo(debug_history(dm), sim) {
		return edit_fail(.Nothing_To_Undo)
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
	if !object_history_redo(debug_history(dm), sim) {
		return edit_fail(.Nothing_To_Redo)
	}
	debug_mode_end_drag(dm)
	if _, ok := debug_selected_object_id(dm, sim); !ok {
		debug_mode_clear_selection(dm)
	}
	return edit_ok()
}

