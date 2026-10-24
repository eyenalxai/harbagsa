#+vet explicit-allocators
#+vet !unused-procedures // the agent harness and tests call this API; the game binary does not
package game

import "core:math"

import b3 "libs:box3d"

debug_select_object :: proc(dm: ^Debug_Mode, sim: ^Simulation, id: Object_Id) -> bool {
	if id == INVALID_OBJECT_ID {
		debug_mode_clear_selection(dm)
		return true
	}
	object, ok := simulation_object_find(sim, id)
	if !ok {
		return false
	}
	debug_mode_end_drag(dm)
	dm.selection = .Object
	dm.selected_object_id = object.id
	dm.drag_position = simulation_object_box(sim, id).center
	return true
}

debug_move_selected :: proc(dm: ^Debug_Mode, sim: ^Simulation, center: b3.Vec3) -> bool {
	object, ok := selected_object(dm, sim)
	if !ok {
		return false
	}
	object_history_record(debug_history(dm), sim)
	target := center
	target.y = max(target.y, prefab(object.prefab).half_extents.y)
	dm.drag_position = target
	return simulation_move_object(sim, object.id, target)
}

debug_rotate_selected :: proc(dm: ^Debug_Mode, sim: ^Simulation, degrees: f32) -> bool {
	object, ok := selected_object(dm, sim)
	if !ok {
		return false
	}
	if degrees == 0.0 {
		return true
	}
	object_history_record(debug_history(dm), sim)
	yaw := simulation_object_yaw(sim, object.id) + degrees * math.PI / 180.0
	return simulation_set_object_yaw(sim, object.id, yaw)
}

debug_turn_selected :: proc(dm: ^Debug_Mode, sim: ^Simulation, steps: int, large: bool) -> bool {
	step: f32 = large ? PLACEMENT_YAW_STEP_LARGE : PLACEMENT_YAW_STEP
	return debug_rotate_selected(dm, sim, f32(steps) * step)
}

debug_convert_selected :: proc(dm: ^Debug_Mode, sim: ^Simulation, mode: Body_Mode) -> bool {
	object, ok := selected_object(dm, sim)
	if !ok {
		return false
	}
	if object.body_mode == mode {
		return true
	}
	object_history_record(debug_history(dm), sim)
	return simulation_convert_object(sim, object.id, mode)
}

debug_delete_selected :: proc(dm: ^Debug_Mode, sim: ^Simulation) -> bool {
	object, ok := selected_object(dm, sim)
	if !ok {
		return false
	}
	object_history_record(debug_history(dm), sim)
	if !simulation_remove_object(sim, object.id) {
		return false
	}
	debug_mode_clear_selection(dm)
	return true
}

debug_duplicate_selected :: proc(dm: ^Debug_Mode, sim: ^Simulation) -> Object_Id {
	object, ok := selected_object(dm, sim)
	if !ok || simulation_object_count(sim) >= MAX_PLACED_OBJECTS {
		return INVALID_OBJECT_ID
	}
	object_history_record(debug_history(dm), sim)
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
	if id != INVALID_OBJECT_ID {
		_ = debug_select_object(dm, sim, id)
	}
	return id
}

// M follows the palette rule: while the palette is open it changes the next
// placement; otherwise it flips the selected object when there is one.
debug_body_key :: proc(dm: ^Debug_Mode, sim: ^Simulation) {
	if dm.palette.open {
		debug_palette_flip_body(dm)
		return
	}
	if debug_flip_selected_body(dm, sim) {
		return
	}
	debug_palette_flip_body(dm)
}

debug_flip_selected_body :: proc(dm: ^Debug_Mode, sim: ^Simulation) -> bool {
	object, ok := selected_object(dm, sim)
	if !ok {
		return false
	}
	mode: Body_Mode = object.body_mode == .Static ? .Dynamic : .Static
	return debug_convert_selected(dm, sim, mode)
}

debug_undo :: proc(dm: ^Debug_Mode, sim: ^Simulation) -> bool {
	if !object_history_undo(debug_history(dm), sim) {
		return false
	}
	debug_mode_end_drag(dm)
	if _, ok := debug_selected_object_id(dm, sim); !ok {
		debug_mode_clear_selection(dm)
	}
	return true
}

debug_redo :: proc(dm: ^Debug_Mode, sim: ^Simulation) -> bool {
	if !object_history_redo(debug_history(dm), sim) {
		return false
	}
	debug_mode_end_drag(dm)
	if _, ok := debug_selected_object_id(dm, sim); !ok {
		debug_mode_clear_selection(dm)
	}
	return true
}

@(private)
selected_object :: proc(dm: ^Debug_Mode, sim: ^Simulation) -> (Placed_Object, bool) {
	id, ok := debug_selected_object_id(dm, sim)
	if !ok {
		return {}, false
	}
	return simulation_object_find(sim, id)
}
