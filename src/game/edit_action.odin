#+vet explicit-allocators
#+vet !unused-procedures // the agent harness calls this API; the game binary does not
package game

edit_apply :: proc(
	dm: ^Debug_Mode,
	sim: ^Simulation,
	action: Edit_Action,
	ctx: Edit_Context,
) -> Edit_Result {
	if !dm.active {
		return edit_fail(.Inactive)
	}
	if ctx.menu_open {
		return edit_fail(.Menu_Open)
	}

	switch value in action {
	case Palette_Open:
		return edit_palette_open(dm)
	case Palette_Close:
		return edit_palette_close(dm)
	case Palette_Select:
		return edit_palette_select(dm, value.index)
	case Palette_Step:
		return edit_palette_step(dm, value.delta)
	case Palette_Flip_Body:
		return edit_palette_flip_body(dm)
	case Palette_Pick:
		return edit_palette_pick(dm, sim)
	case Select_Object:
		return edit_select_object(dm, sim, value.id)
	case Move_Selected:
		return edit_move_selected(dm, sim, value.center)
	case Rotate_Selected:
		return edit_rotate_selected(dm, sim, value.degrees)
	case Turn:
		return edit_turn(dm, sim, value.steps, value.large)
	case Set_Body:
		return edit_set_body(dm, sim, value.mode)
	case Flip_Body:
		return edit_flip_body(dm, sim)
	case Delete_Selected:
		return edit_delete_selected(dm, sim)
	case Duplicate_Selected:
		return edit_duplicate_selected(dm, sim)
	case Undo:
		return edit_undo(dm, sim)
	case Redo:
		return edit_redo(dm, sim)
	case Primary_Press:
		return edit_primary_press(dm, sim, ctx.captured)
	case Primary_Release:
		return edit_primary_release(dm)
	case Secondary_Press:
		return edit_secondary_press(dm)
	case Drag_Move:
		return edit_drag_move(dm, sim, value.look_delta, ctx.captured)
	case Wheel:
		return edit_wheel(dm, sim, value.steps, value.large, ctx.captured)
	case Placement_Arm:
		return edit_placement_arm(dm, sim, value.prefab)
	case Placement_Cancel:
		debug_placement_cancel(dm)
		return edit_ok()
	case Placement_Set_Height:
		debug_placement_set_height(dm, value.height)
		return edit_ok()
	case Placement_Raise:
		debug_placement_raise(dm, value.steps, value.large)
		return edit_ok()
	case Placement_Set_Yaw:
		debug_placement_set_yaw(dm, value.yaw_deg)
		return edit_ok()
	case Placement_Turn:
		debug_placement_turn(dm, value.steps, value.large)
		return edit_ok()
	case Placement_Set_Snap:
		debug_placement_set_snap(dm, value.snap)
		return edit_ok()
	case Placement_Toggle_Snap:
		debug_placement_toggle_snap(dm)
		return edit_ok()
	case Placement_Place:
		return edit_placement_place(dm, sim)
	case Place_Object:
		return edit_place_object(dm, sim, value)
	case Light_Adjust:
		return edit_light_change(dm, sim, value.change)
	case Light_Set_Color:
		return edit_light_set_color(dm, sim, value.color)
	case Light_Set_Intensity:
		return edit_light_set_intensity(dm, sim, value.intensity)
	case Light_Set_Range:
		return edit_light_set_range(dm, sim, value.range)
	case Light_Set_Kind:
		return edit_light_set_kind(dm, sim, value.kind)
	case Light_Toggle_Kind:
		return edit_light_toggle_kind(dm, sim)
	case Cancel:
		return edit_cancel(dm)
	}
	return edit_fail(.Failed)
}

// The open palette or the armed tool owns the next placement; a selection owns
// itself only when neither tool is active.
next_placement_light :: proc(dm: ^Debug_Mode) -> Light_Settings {
	prefab := palette_selected(dm.palette)
	if dm.placement.armed {
		prefab = dm.placement.prefab
	}
	return placement_light_for(dm, prefab)
}

placement_light_for :: proc(dm: ^Debug_Mode, prefab_id: Prefab_Id) -> Light_Settings {
	if !prefab_has_light(prefab_id) {
		return {}
	}
	if prefab_id == palette_selected(dm.palette) {
		return palette_light(dm)
	}
	return prefab_light(prefab_id)
}
