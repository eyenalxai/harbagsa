#+vet explicit-allocators
package game

import b3 "libs:box3d"

OBJECT_DRAG_SCALE :: 0.02
OBJECT_WHEEL_STEP :: 0.5

@(private)
editor_primary_press :: proc(editor: ^Editor, sim: ^Simulation, ctx: Edit_Context) -> Edit_Result {
	switch _ in editor.tool {
	case Palette:
		return edit_no_change()
	case Placement:
		if !ctx.captured {
			return edit_no_change()
		}
		return editor_placement_place(editor, sim, ctx.camera)
	case Tool_None:
	}
	if !ctx.captured {
		return edit_no_change()
	}

	hit := debug_aim_ray(sim, ctx.camera)
	if hit.hit {
		id := simulation_object_id_for_body(sim, b3.Shape_GetBody(hit.shapeId))
		if id != INVALID_OBJECT_ID {
			editor_selection_set(editor, sim, id)
			editor.dragging = true
			editor.drag_recorded = false
			return edit_ok()
		}
	}
	editor_clear_selection(editor)
	return edit_ok()
}

@(private)
editor_primary_release :: proc(editor: ^Editor) -> Edit_Result {
	if editor.dragging {
		editor_end_drag(editor)
	}
	return edit_ok()
}

@(private)
editor_secondary_press :: proc(editor: ^Editor) -> Edit_Result {
	switch _ in editor.tool {
	case Palette:
		return editor_palette_close(editor)
	case Placement:
		return editor_placement_cancel(editor)
	case Tool_None:
	}
	editor_clear_selection(editor)
	return edit_ok()
}

@(private)
editor_drag_move :: proc(
	editor: ^Editor,
	sim: ^Simulation,
	look_delta: [2]f32,
	ctx: Edit_Context,
) -> Edit_Result {
	if !editor.dragging || !ctx.captured {
		return edit_no_change()
	}
	object, ok := editor_selected_object(editor, sim)
	if !ok || (look_delta.x == 0.0 && look_delta.y == 0.0) {
		return edit_no_change()
	}

	forward := debug_camera_forward_horizontal(ctx.camera)
	right := debug_camera_right(ctx.camera)
	target := editor.drag_position +
		right * (look_delta.x * OBJECT_DRAG_SCALE) + forward * (-look_delta.y * OBJECT_DRAG_SCALE)
	result := editor_commit_move(editor, sim, object, target, !editor.drag_recorded)
	if !result.applied {
		return result
	}
	if !editor.drag_recorded {
		editor.drag_recorded = true
	}
	return edit_ok()
}

@(private)
editor_wheel :: proc(
	editor: ^Editor,
	sim: ^Simulation,
	steps: int,
	large: bool,
	ctx: Edit_Context,
) -> Edit_Result {
	if steps == 0 {
		return edit_no_change()
	}
	switch _ in editor.tool {
	case Palette:
		return edit_no_change()
	case Placement:
		if !ctx.captured {
			return edit_no_change()
		}
		return editor_placement_raise(editor, steps, large)
	case Tool_None:
	}
	if !ctx.captured {
		return edit_no_change()
	}
	object, ok := editor_selected_object(editor, sim)
	if !ok {
		return edit_no_change()
	}
	if !editor.dragging {
		editor.drag_position = b3.Body_GetPosition(object.body)
	}
	target := editor.drag_position
	target.y += f32(steps) * OBJECT_WHEEL_STEP
	return editor_commit_move(editor, sim, object, target, true)
}

@(private)
editor_cancel :: proc(editor: ^Editor) -> Edit_Result {
	switch _ in editor.tool {
	case Palette:
		return editor_palette_close(editor)
	case Placement:
		return editor_placement_cancel(editor)
	case Tool_None:
	}
	return edit_no_change()
}
