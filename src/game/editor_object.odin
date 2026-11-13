#+vet explicit-allocators
package game

import "core:math"

import b3 "libs:box3d"

@(private)
editor_tool_block_reason :: proc(editor: ^Editor) -> Edit_Reason {
	switch _ in editor.tool {
	case Palette:
		return .Palette_Open
	case Placement:
		return .Placement_Armed
	case Tool_None:
	}
	return .None
}

@(private)
editor_next_body :: proc(editor: ^Editor) -> (Body_Mode, bool) {
	switch tool in editor.tool {
	case Palette:
		return tool.body_mode, true
	case Placement:
		return tool.body_mode, true
	case Tool_None:
	}
	return {}, false
}

@(private)
editor_set_next_body :: proc(editor: ^Editor, mode: Body_Mode) -> Edit_Result {
	switch tool in editor.tool {
	case Palette:
		if prefab_has_light(palette_selected(tool)) {
			return edit_fail(.Lamp_Body_Follows_Kind)
		}
		palette := tool
		palette.body_mode = mode
		editor.tool = palette
		return edit_ok()
	case Placement:
		if prefab_has_light(tool.prefab) {
			return edit_fail(.Lamp_Body_Follows_Kind)
		}
		placement := tool
		placement.body_mode = mode
		editor.tool = placement
		return edit_ok()
	case Tool_None:
	}
	return edit_fail(.No_Selection)
}

@(private)
editor_commit_move :: proc(
	editor: ^Editor,
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
			editor_history(editor),
			sim,
			History_Move{id = object.id, center = resolved},
		)
		if !result.applied {
			return result
		}
	} else if !simulation_move_object(sim, object.id, resolved) {
		return edit_fail(.Failed)
	}
	if active, dragging := editor.drag.(Drag_Active); dragging {
		active.position = resolved
		editor.drag = active
	}
	return edit_ok()
}

@(private)
editor_select_object :: proc(editor: ^Editor, sim: ^Simulation, id: Object_Id) -> Edit_Result {
	editor_end_drag(editor)
	if id == INVALID_OBJECT_ID {
		editor_clear_selection(editor)
		return edit_ok()
	}
	if _, ok := simulation_object_find(sim, id); !ok {
		return edit_fail(.Unknown_Object)
	}
	editor_selection_set(editor, id)
	return edit_ok()
}

@(private)
editor_move_selected :: proc(
	editor: ^Editor,
	sim: ^Simulation,
	center: b3.Vec3,
) -> Edit_Result {
	if reason := editor_tool_block_reason(editor); reason != .None {
		return edit_fail(reason)
	}
	object, ok := editor_selected_object(editor, sim)
	if !ok {
		return edit_fail(.No_Selection)
	}
	return editor_commit_move(editor, sim, object, center, true)
}

@(private)
editor_rotate_selected :: proc(
	editor: ^Editor,
	sim: ^Simulation,
	degrees: f32,
) -> Edit_Result {
	if reason := editor_tool_block_reason(editor); reason != .None {
		return edit_fail(reason)
	}
	object, ok := editor_selected_object(editor, sim)
	if !ok {
		return edit_fail(.No_Selection)
	}
	if degrees == 0.0 {
		return edit_ok()
	}
	result, _ := object_history_apply(
		editor_history(editor),
		sim,
		History_Rotate{id = object.id, degrees = degrees},
	)
	if !result.applied {
		return result
	}
	return edit_ok()
}

@(private)
editor_set_yaw :: proc(editor: ^Editor, sim: ^Simulation, degrees: f32) -> Edit_Result {
	if reason := editor_tool_block_reason(editor); reason != .None {
		return edit_fail(reason)
	}
	object, ok := editor_selected_object(editor, sim)
	if !ok {
		return edit_fail(.No_Selection)
	}
	target := degrees - 360.0 * math.floor(degrees / 360.0)
	current := simulation_object_yaw(sim, object.id) * 180.0 / math.PI
	delta := target - current
	if delta > 180.0 {
		delta -= 360.0
	} else if delta < -180.0 {
		delta += 360.0
	}
	return editor_rotate_selected(editor, sim, delta)
}

@(private)
editor_turn :: proc(editor: ^Editor, sim: ^Simulation, steps: int, large: bool) -> Edit_Result {
	if _, armed := editor.tool.(Placement); armed {
		return editor_placement_turn(editor, steps, large)
	}
	step: f32 = large ? PLACEMENT_YAW_STEP_LARGE : PLACEMENT_YAW_STEP
	return editor_rotate_selected(editor, sim, f32(steps) * step)
}

@(private)
editor_convert_selected :: proc(
	editor: ^Editor,
	sim: ^Simulation,
	object: Placed_Object,
	mode: Body_Mode,
) -> Edit_Result {
	if object.light.active {
		return edit_fail(.Lamp_Body_Follows_Kind)
	}
	if object.body_mode == mode {
		return edit_ok()
	}
	result, _ := object_history_apply(
		editor_history(editor),
		sim,
		History_Convert{id = object.id, mode = mode},
	)
	if !result.applied {
		return result
	}
	return edit_ok()
}

@(private)
editor_set_body :: proc(editor: ^Editor, sim: ^Simulation, mode: Body_Mode) -> Edit_Result {
	if _, next := editor_next_body(editor); next {
		return editor_set_next_body(editor, mode)
	}
	object, ok := editor_selected_object(editor, sim)
	if !ok {
		return edit_fail(.No_Selection)
	}
	return editor_convert_selected(editor, sim, object, mode)
}

@(private)
editor_flip_body :: proc(editor: ^Editor, sim: ^Simulation) -> Edit_Result {
	if current, next := editor_next_body(editor); next {
		mode: Body_Mode = current == .Static ? .Dynamic : .Static
		return editor_set_next_body(editor, mode)
	}
	object, ok := editor_selected_object(editor, sim)
	if !ok {
		return edit_fail(.No_Selection)
	}
	mode: Body_Mode = object.body_mode == .Static ? .Dynamic : .Static
	return editor_convert_selected(editor, sim, object, mode)
}

@(private)
editor_delete_selected :: proc(editor: ^Editor, sim: ^Simulation) -> Edit_Result {
	if reason := editor_tool_block_reason(editor); reason != .None {
		return edit_fail(reason)
	}
	object, ok := editor_selected_object(editor, sim)
	if !ok {
		return edit_fail(.No_Selection)
	}
	result, _ := object_history_apply(
		editor_history(editor),
		sim,
		History_Delete{id = object.id},
	)
	if !result.applied {
		return result
	}
	editor_clear_selection(editor)
	return edit_ok()
}

@(private)
editor_duplicate_selected :: proc(editor: ^Editor, sim: ^Simulation) -> Edit_Result {
	if reason := editor_tool_block_reason(editor); reason != .None {
		return edit_fail(reason)
	}
	object, ok := editor_selected_object(editor, sim)
	if !ok {
		return edit_fail(.No_Selection)
	}
	result, id := object_history_apply(
		editor_history(editor),
		sim,
		History_Duplicate{id = object.id},
	)
	if !result.applied {
		return result
	}
	editor_selection_set(editor, id)
	return edit_ok()
}

@(private)
editor_undo :: proc(editor: ^Editor, sim: ^Simulation) -> Edit_Result {
	if reason := editor_tool_block_reason(editor); reason != .None {
		return edit_fail(reason)
	}
	result := object_history_undo(editor_history(editor), sim)
	if !result.applied {
		return result
	}
	editor_end_drag(editor)
	editor_repair_selection(editor, sim)
	return edit_ok()
}

@(private)
editor_redo :: proc(editor: ^Editor, sim: ^Simulation) -> Edit_Result {
	if reason := editor_tool_block_reason(editor); reason != .None {
		return edit_fail(reason)
	}
	result := object_history_redo(editor_history(editor), sim)
	if !result.applied {
		return result
	}
	editor_end_drag(editor)
	editor_repair_selection(editor, sim)
	return edit_ok()
}
