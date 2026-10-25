#+vet explicit-allocators
#+vet !unused-procedures // the agent harness and tests call this API; the game binary does not
package game

import "core:math"

@(private)
edit_placement_arm :: proc(dm: ^Debug_Mode, sim: ^Simulation, prefab_id: Prefab_Id) -> Edit_Result {
	if !simulation_is_valid(sim) {
		return edit_fail(.Failed)
	}
	debug_sun_cancel(dm)
	// The palette is the one place that holds the next placement's body and
	// light, so arming by prefab also selects it there.
	_ = palette_select(&dm.palette, int(prefab_id))
	dm.placement.armed = true
	dm.placement.prefab = prefab_id
	debug_placement_refresh(dm, sim)
	return edit_ok()
}

@(private)
edit_placement_cancel :: proc(dm: ^Debug_Mode) -> Edit_Result {
	debug_placement_cancel(dm)
	return edit_ok()
}

@(private)
edit_placement_set_height :: proc(dm: ^Debug_Mode, height: f32) -> Edit_Result {
	debug_placement_set_height(dm, height)
	return edit_ok()
}

@(private)
edit_placement_raise :: proc(dm: ^Debug_Mode, steps: int, large: bool) -> Edit_Result {
	debug_placement_raise(dm, steps, large)
	return edit_ok()
}

@(private)
edit_placement_set_yaw :: proc(dm: ^Debug_Mode, yaw: f32) -> Edit_Result {
	debug_placement_set_yaw(dm, yaw)
	return edit_ok()
}

@(private)
edit_placement_turn :: proc(dm: ^Debug_Mode, steps: int, large: bool) -> Edit_Result {
	debug_placement_turn(dm, steps, large)
	return edit_ok()
}

@(private)
edit_placement_set_snap :: proc(dm: ^Debug_Mode, snap: bool) -> Edit_Result {
	debug_placement_set_snap(dm, snap)
	return edit_ok()
}

@(private)
edit_placement_toggle_snap :: proc(dm: ^Debug_Mode) -> Edit_Result {
	debug_placement_toggle_snap(dm)
	return edit_ok()
}

@(private)
edit_placement_place :: proc(dm: ^Debug_Mode, sim: ^Simulation) -> Edit_Result {
	if !dm.placement.armed {
		return edit_fail(.Not_Armed)
	}
	ghost, ok := debug_ghost_geometry(dm)
	if !ok {
		return edit_fail(.Failed)
	}
	spawn := Object_Spawn {
		prefab    = dm.placement.prefab,
		body_mode = dm.palette.body_mode,
		center    = ghost.center,
		yaw       = dm.placement.yaw_degrees * math.PI / 180.0,
		light     = placement_light_for(dm, dm.placement.prefab),
	}
	return place_object(dm, sim, spawn)
}

@(private)
edit_place_object :: proc(dm: ^Debug_Mode, sim: ^Simulation, place: Place_Object) -> Edit_Result {
	spawn := Object_Spawn {
		prefab    = place.prefab,
		body_mode = place.body_mode,
		center    = place.center,
		yaw       = place.yaw,
		light     = placement_light_for(dm, place.prefab),
	}
	return place_object(dm, sim, spawn)
}

@(private)
place_object :: proc(dm: ^Debug_Mode, sim: ^Simulation, spawn: Object_Spawn) -> Edit_Result {
	if simulation_object_count(sim) >= MAX_PLACED_OBJECTS {
		return edit_fail(.Scene_Full)
	}
	history := debug_history(dm)
	snapshot := object_snapshot_capture(sim, history.allocator)
	id := simulation_create_object(sim, spawn)
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

