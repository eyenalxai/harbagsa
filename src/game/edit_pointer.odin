#+vet explicit-allocators
#+vet !unused-procedures // the agent harness calls this API; the game binary does not
package game

import b3 "libs:box3d"

OBJECT_DRAG_SCALE :: 0.02
OBJECT_WHEEL_STEP :: 0.5

@(private)
edit_primary_press :: proc(dm: ^Debug_Mode, sim: ^Simulation, captured: bool) -> Edit_Result {
	switch active_tool(dm) {
	case .Palette:
		return edit_no_change()
	case .Placement:
		if !captured {
			return edit_no_change()
		}
		return edit_placement_place(dm, sim)
	case .None:
	}
	if !captured {
		return edit_no_change()
	}

	hit := debug_aim_ray(dm, sim)
	if hit.hit {
		id := simulation_object_id_for_body(sim, b3.Shape_GetBody(hit.shapeId))
		if id != INVALID_OBJECT_ID {
			dm.selection = .Object
			dm.selected_object_id = id
			dm.dragging = .Object
			dm.drag_recorded = false
			dm.drag_position = simulation_object_box(sim, id).center
			return edit_ok()
		}
	}
	if dm.selection == .Object {
		debug_mode_clear_selection(dm)
	}
	return edit_ok()
}

@(private)
edit_primary_release :: proc(dm: ^Debug_Mode) -> Edit_Result {
	if dm.dragging == .Object {
		debug_mode_end_drag(dm)
	}
	return edit_ok()
}

@(private)
edit_secondary_press :: proc(dm: ^Debug_Mode) -> Edit_Result {
	switch active_tool(dm) {
	case .Palette:
		return edit_palette_close(dm)
	case .Placement:
		debug_placement_cancel(dm)
		return edit_ok()
	case .None:
	}
	if dm.selection == .Object {
		debug_mode_clear_selection(dm)
	}
	return edit_ok()
}

@(private)
edit_drag_move :: proc(
	dm: ^Debug_Mode,
	sim: ^Simulation,
	look_delta: [2]f32,
	captured: bool,
) -> Edit_Result {
	if dm.dragging != .Object || !captured {
		return edit_no_change()
	}
	id, ok := debug_selected_object_id(dm, sim)
	if !ok || (look_delta.x == 0.0 && look_delta.y == 0.0) {
		return edit_no_change()
	}
	if !dm.drag_recorded {
		object_history_record(debug_history(dm), sim)
		dm.drag_recorded = true
	}

	forward := debug_camera_forward_horizontal(dm.camera)
	right := debug_camera_right(dm.camera)
	dm.drag_position +=
		right * (look_delta.x * OBJECT_DRAG_SCALE) + forward * (-look_delta.y * OBJECT_DRAG_SCALE)
	half := simulation_object_box(sim, id).half_extents
	dm.drag_position.y = max(dm.drag_position.y, half.y)
	if !simulation_move_object(sim, id, dm.drag_position) {
		return edit_fail(.Failed)
	}
	return edit_ok()
}

@(private)
edit_wheel :: proc(
	dm: ^Debug_Mode,
	sim: ^Simulation,
	steps: int,
	large: bool,
	captured: bool,
) -> Edit_Result {
	switch active_tool(dm) {
	case .Palette:
		return edit_no_change()
	case .Placement:
		if !captured {
			return edit_no_change()
		}
		debug_placement_raise(dm, steps, large)
		return edit_ok()
	case .None:
	}
	if !captured {
		return edit_no_change()
	}
	id, ok := debug_selected_object_id(dm, sim)
	if !ok {
		return edit_no_change()
	}
	if dm.dragging != .Object {
		dm.drag_position = simulation_object_box(sim, id).center
	}
	object_history_record(debug_history(dm), sim)
	half := simulation_object_box(sim, id).half_extents
	dm.drag_position.y = max(
		dm.drag_position.y + f32(steps) * OBJECT_WHEEL_STEP,
		half.y,
	)
	if !simulation_move_object(sim, id, dm.drag_position) {
		return edit_fail(.Failed)
	}
	return edit_ok()
}


@(private)
edit_cancel :: proc(dm: ^Debug_Mode) -> Edit_Result {
	switch active_tool(dm) {
	case .Palette:
		return edit_palette_close(dm)
	case .Placement:
		debug_placement_cancel(dm)
		return edit_ok()
	case .None:
	}
	return edit_no_change()
}
