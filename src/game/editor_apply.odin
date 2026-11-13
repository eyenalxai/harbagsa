#+vet explicit-allocators
package game

editor_apply :: proc(
	editor: ^Editor,
	sim: ^Simulation,
	action: Edit_Action,
	ctx: Edit_Context,
) -> Edit_Result {
	if !ctx.active {
		return edit_fail(.Inactive)
	}
	if ctx.menu_open {
		return edit_fail(.Menu_Open)
	}

	editor_repair_selection(editor, sim)
	switch value in action {
	case Palette_Open:
		return editor_palette_open(editor)
	case Palette_Close:
		return editor_palette_close(editor)
	case Palette_Select:
		return editor_palette_select(editor, value.index)
	case Palette_Step:
		return editor_palette_step(editor, value.delta)
	case Palette_Flip_Body:
		return editor_palette_flip_body(editor)
	case Palette_Pick:
		return editor_palette_pick(editor, sim)
	case Select_Object:
		return editor_select_object(editor, sim, value.id)
	case Move_Selected:
		return editor_move_selected(editor, sim, value.center)
	case Rotate_Selected:
		return editor_rotate_selected(editor, sim, value.degrees)
	case Turn:
		return editor_turn(editor, sim, value.steps, value.large)
	case Set_Body:
		return editor_set_body(editor, sim, value.mode)
	case Flip_Body:
		return editor_flip_body(editor, sim)
	case Delete_Selected:
		return editor_delete_selected(editor, sim)
	case Duplicate_Selected:
		return editor_duplicate_selected(editor, sim)
	case Undo:
		return editor_undo(editor, sim)
	case Redo:
		return editor_redo(editor, sim)
	case Inspector_Open:
		return editor_set_inspector(editor, true)
	case Inspector_Close:
		return editor_set_inspector(editor, false)
	case Inspector_Toggle:
		return editor_set_inspector(editor, !editor.inspector_open)
	case Set_Selected_Yaw:
		return editor_set_yaw(editor, sim, value.degrees)
	case Primary_Press:
		return editor_primary_press(editor, sim, ctx)
	case Primary_Release:
		return editor_primary_release(editor)
	case Secondary_Press:
		return editor_secondary_press(editor)
	case Drag_Move:
		return editor_drag_move(editor, sim, value.look_delta, ctx)
	case Wheel:
		return editor_wheel(editor, sim, value.steps, value.large, ctx)
	case Placement_Arm:
		return editor_placement_arm(editor, sim, value.prefab)
	case Placement_Cancel:
		return editor_placement_cancel(editor)
	case Placement_Set_Height:
		return editor_placement_set_height(editor, value.height)
	case Placement_Raise:
		return editor_placement_raise(editor, value.steps, value.large)
	case Placement_Set_Yaw:
		return editor_placement_set_yaw(editor, value.yaw_deg)
	case Placement_Turn:
		return editor_placement_turn(editor, value.steps, value.large)
	case Placement_Set_Snap:
		return editor_placement_set_snap(editor, value.snap)
	case Placement_Toggle_Snap:
		return editor_placement_toggle_snap(editor)
	case Placement_Place:
		return editor_placement_place(editor, sim, ctx.camera)
	case Place_Object:
		return editor_place_object(editor, sim, value)
	case Light_Adjust:
		return editor_light_edit(editor, sim, Light_Edit_Adjust{change = value.change})
	case Light_Set_Color:
		return editor_light_edit(editor, sim, Light_Edit_Color{color = value.color})
	case Light_Set_Intensity:
		return editor_light_edit(editor, sim, Light_Edit_Intensity{intensity = value.intensity})
	case Light_Set_Range:
		return editor_light_edit(editor, sim, Light_Edit_Range{range = value.range})
	case Light_Set_Kind:
		return editor_light_edit(editor, sim, Light_Edit_Kind{kind = value.kind})
	case Light_Toggle_Kind:
		return editor_light_edit(editor, sim, Light_Edit_Toggle{})
	case Cancel:
		return editor_cancel(editor)
	}
	return edit_fail(.Failed)
}

// The open palette or the armed placement owns the next placement. A closed
// palette holds nothing, so the prefab default applies.
editor_next_light :: proc(editor: ^Editor, prefab_id: Prefab_Id) -> Light_Settings {
	switch tool in editor.tool {
	case Palette:
		if prefab_id == palette_selected(tool) {
			return palette_light(tool)
		}
	case Placement:
		if prefab_id == tool.prefab {
			return tool.light
		}
	case Tool_None:
	}
	return prefab_light(prefab_id)
}
