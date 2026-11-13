#+vet explicit-allocators
package game

import "core:math"

import b3 "libs:box3d"

PLACEMENT_HEIGHT_STEP :: 0.25
PLACEMENT_HEIGHT_STEP_LARGE :: 1.0
PLACEMENT_YAW_STEP :: 15.0
PLACEMENT_YAW_STEP_LARGE :: 45.0
PLACEMENT_SNAP_STEP :: 0.25
PLACEMENT_FALLBACK_DISTANCE :: 3.0

Placement_Geometry :: struct {
	center:       [3]f32,
	half_extents: [3]f32,
	rotation:     b3.Quat,
	bottom:       [3]f32,
	surface:      [3]f32,
}

placement_geometry :: proc(placement: Placement, anchor: [3]f32) -> Placement_Geometry {
	info := prefab(placement.prefab)
	rotation := object_rotation(placement.prefab, placement.yaw_degrees * math.PI / 180.0)
	bottom := anchor + {0.0, placement.height, 0.0}
	if placement.snap {
		bottom.x = placement_snap(bottom.x)
		bottom.z = placement_snap(bottom.z)
	}
	extent := oriented_aabb_half_extents(info.half_extents, rotation)
	return {
		center = bottom + {0.0, extent.y, 0.0},
		half_extents = info.half_extents,
		rotation = rotation,
		bottom = bottom,
		surface = anchor,
	}
}

@(private)
editor_placement_geometry :: proc(
	editor: ^Editor,
	sim: ^Simulation,
	camera: Debug_Camera,
) -> (
	Placement_Geometry,
	bool,
) {
	placement, armed := editor.tool.(Placement)
	if !armed {
		return {}, false
	}
	anchor := debug_aim_point(sim, camera, PLACEMENT_FALLBACK_DISTANCE)
	return placement_geometry(placement, anchor), true
}

@(private)
editor_placement_arm :: proc(
	editor: ^Editor,
	sim: ^Simulation,
	prefab_id: Prefab_Id,
) -> Edit_Result {
	if !simulation_is_valid(sim) {
		return edit_fail(.Failed)
	}

	body_mode := prefab(prefab_id).body_mode
	light := prefab_light(prefab_id)
	if palette, open := editor.tool.(Palette); open {
		if palette_selected(palette) == prefab_id {
			body_mode = palette.body_mode
			light = palette_light(palette)
		}
	}

	placement := Placement {
		prefab = prefab_id,
		body_mode = body_mode,
		light = light,
	}
	editor.inspector_open = false
	// Re-arming the same placement keeps its height, yaw, and snap; arming from
	// the palette uses the last cancelled placement settings.
	if current, armed := editor.tool.(Placement); armed {
		placement.height = current.height
		placement.yaw_degrees = current.yaw_degrees
		placement.snap = current.snap
	} else {
		placement.height = editor.placement_defaults.height
		placement.yaw_degrees = editor.placement_defaults.yaw_degrees
		placement.snap = editor.placement_defaults.snap
	}
	editor_end_drag(editor)
	editor.tool = placement
	return edit_ok()
}

@(private)
editor_tool_cancel :: proc(editor: ^Editor) {
	if placement, armed := editor.tool.(Placement); armed {
		editor.placement_defaults = {
			prefab = placement.prefab,
			height = placement.height,
			yaw_degrees = placement.yaw_degrees,
			snap = placement.snap,
		}
	}
	editor.tool = Tool_None{}
}

@(private)
editor_placement_place :: proc(
	editor: ^Editor,
	sim: ^Simulation,
	camera: Debug_Camera,
) -> Edit_Result {
	placement, armed := editor.tool.(Placement)
	if !armed {
		return edit_fail(.Not_Armed)
	}
	ghost, ok := editor_placement_geometry(editor, sim, camera)
	if !ok {
		return edit_fail(.Failed)
	}
	spawn := Object_Spawn {
		prefab    = placement.prefab,
		body_mode = placement.body_mode,
		center    = ghost.center,
		yaw_rad   = placement.yaw_degrees * math.PI / 180.0,
		light     = placement.light,
	}
	return editor_place_spawn(editor, sim, spawn)
}

@(private)
editor_place_object :: proc(editor: ^Editor, sim: ^Simulation, place: Place_Object) -> Edit_Result {
	spawn := Object_Spawn {
		prefab    = place.prefab,
		body_mode = place.body_mode,
		center    = place.center,
		yaw_rad   = place.yaw_rad,
		light     = editor_next_light(editor, place.prefab),
	}
	return editor_place_spawn(editor, sim, spawn)
}

@(private)
editor_place_spawn :: proc(
	editor: ^Editor,
	sim: ^Simulation,
	spawn: Object_Spawn,
) -> Edit_Result {
	result, id := object_history_apply(editor_history(editor), sim, History_Place{spawn = spawn})
	if !result.applied {
		return result
	}
	editor_selection_set(editor, id)
	return edit_ok()
}

@(private)
editor_placement_cancel :: proc(editor: ^Editor) -> Edit_Result {
	if _, armed := editor.tool.(Placement); !armed {
		return edit_no_change()
	}
	editor_tool_cancel(editor)
	return edit_ok()
}

@(private)
editor_placement_set_height :: proc(editor: ^Editor, height: f32) -> Edit_Result {
	placement, armed := editor.tool.(Placement)
	if !armed {
		return edit_fail(.Not_Armed)
	}
	placement.height = max(height, 0.0)
	editor.tool = placement
	return edit_ok()
}

@(private)
editor_placement_raise :: proc(editor: ^Editor, steps: int, large: bool) -> Edit_Result {
	placement, armed := editor.tool.(Placement)
	if !armed {
		return edit_fail(.Not_Armed)
	}
	step: f32 = large ? PLACEMENT_HEIGHT_STEP_LARGE : PLACEMENT_HEIGHT_STEP
	placement.height = max(placement.height + f32(steps) * step, 0.0)
	editor.tool = placement
	return edit_ok()
}

@(private)
editor_placement_set_yaw :: proc(editor: ^Editor, degrees: f32) -> Edit_Result {
	placement, armed := editor.tool.(Placement)
	if !armed {
		return edit_fail(.Not_Armed)
	}
	placement.yaw_degrees = yaw_degrees_normalized(degrees)
	editor.tool = placement
	return edit_ok()
}

@(private)
editor_placement_turn :: proc(editor: ^Editor, steps: int, large: bool) -> Edit_Result {
	placement, armed := editor.tool.(Placement)
	if !armed {
		return edit_fail(.Not_Armed)
	}
	step: f32 = large ? PLACEMENT_YAW_STEP_LARGE : PLACEMENT_YAW_STEP
	return editor_placement_set_yaw(editor, placement.yaw_degrees + f32(steps) * step)
}

@(private)
editor_placement_set_snap :: proc(editor: ^Editor, snap: bool) -> Edit_Result {
	placement, armed := editor.tool.(Placement)
	if !armed {
		return edit_fail(.Not_Armed)
	}
	placement.snap = snap
	editor.tool = placement
	return edit_ok()
}

@(private)
editor_placement_toggle_snap :: proc(editor: ^Editor) -> Edit_Result {
	placement, armed := editor.tool.(Placement)
	if !armed {
		return edit_fail(.Not_Armed)
	}
	return editor_placement_set_snap(editor, !placement.snap)
}

@(private)
placement_snap :: proc(value: f32) -> f32 {
	return math.round(value / PLACEMENT_SNAP_STEP) * PLACEMENT_SNAP_STEP
}
