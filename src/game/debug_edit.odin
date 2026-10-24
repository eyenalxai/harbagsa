#+vet explicit-allocators
package game

import b3 "libs:box3d"

OBJECT_DRAG_SCALE :: 0.02
OBJECT_WHEEL_STEP :: 0.5

debug_edit_objects :: proc(dm: ^Debug_Mode, sim: ^Simulation, input: Debug_Input) {
	if dm.palette.open {
		return
	}
	if dm.placement.armed {
		debug_placement_input(dm, sim, input)
		return
	}

	clear_stale_object_selection(dm, sim)
	if input.undo_pressed {
		_ = debug_undo(dm, sim)
		return
	}
	if input.redo_pressed {
		_ = debug_redo(dm, sim)
		return
	}
	if input.secondary_pressed {
		debug_mode_clear_selection(dm)
	}
	if input.primary_pressed && input.captured && dm.dragging == .None {
		press_object(dm, sim)
	}
	if input.primary_released && dm.dragging == .Object {
		debug_mode_end_drag(dm)
	}
	if dm.dragging == .Object && input.captured {
		drag_object(dm, sim, input.look_delta)
	}
	if dm.selection == .Object && input.wheel_delta != 0.0 {
		wheel_object(dm, sim, input.wheel_delta)
	}
	if dm.selection == .Object {
		if input.rotate_left {
			_ = debug_turn_selected(dm, sim, -1, input.large_step)
		}
		if input.rotate_right {
			_ = debug_turn_selected(dm, sim, 1, input.large_step)
		}
		if input.duplicate_pressed {
			_ = debug_duplicate_selected(dm, sim)
		}
		if input.delete_pressed {
			_ = debug_delete_selected(dm, sim)
		}
	}
}

@(private)
clear_stale_object_selection :: proc(dm: ^Debug_Mode, sim: ^Simulation) {
	if dm.selection != .Object {
		return
	}
	if _, ok := debug_selected_object_id(dm, sim); !ok {
		debug_mode_clear_selection(dm)
	}
}

@(private)
press_object :: proc(dm: ^Debug_Mode, sim: ^Simulation) {
	hit := debug_aim_ray(dm, sim)
	if hit.hit {
		id := simulation_object_id_for_body(sim, b3.Shape_GetBody(hit.shapeId))
		if id != INVALID_OBJECT_ID {
			dm.selection = .Object
			dm.selected_object_id = id
			dm.dragging = .Object
			dm.drag_recorded = false
			dm.drag_position = simulation_object_box(sim, id).center
		}
		return
	}
	if dm.selection == .Object {
		debug_mode_clear_selection(dm)
	}
}

@(private)
drag_object :: proc(dm: ^Debug_Mode, sim: ^Simulation, look_delta: [2]f32) {
	id, ok := debug_selected_object_id(dm, sim)
	if !ok || (look_delta.x == 0.0 && look_delta.y == 0.0) {
		return
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
	_ = simulation_move_object(sim, id, dm.drag_position)
}

@(private)
wheel_object :: proc(dm: ^Debug_Mode, sim: ^Simulation, wheel_delta: f32) {
	id, ok := debug_selected_object_id(dm, sim)
	if !ok {
		return
	}

	// Outside a drag the stored position can be stale after physics settling.
	if dm.dragging != .Object {
		dm.drag_position = simulation_object_box(sim, id).center
	}
	object_history_record(debug_history(dm), sim)
	half := simulation_object_box(sim, id).half_extents
	dm.drag_position.y = max(
		dm.drag_position.y + wheel_delta * OBJECT_WHEEL_STEP,
		half.y,
	)
	_ = simulation_move_object(sim, id, dm.drag_position)
}
