#+vet explicit-allocators
package game

import b3 "libs:box3d"

OBJECT_DRAG_SCALE :: 0.02
OBJECT_WHEEL_STEP :: 0.5
OBJECT_RAY_LENGTH :: 100.0
OBJECT_ADD_GAP :: 0.01
OBJECT_ADD_DISTANCE :: 3.0

debug_edit_objects :: proc(dm: ^Debug_Mode, sim: ^Simulation, input: Debug_Input) {
	clear_stale_object_selection(dm, sim)

	if input.add_pressed {
		add_crate_at_crosshair(dm, sim)
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
	if input.delete_pressed && dm.selection == .Object {
		delete_selected_object(dm, sim)
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
	hit := cast_edit_ray(dm, sim)
	if hit.hit {
		id := simulation_object_id_for_body(sim, b3.Shape_GetBody(hit.shapeId))
		if id != INVALID_OBJECT_ID {
			dm.selection = .Object
			dm.selected_object_id = id
			dm.dragging = .Object
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
	if !ok {
		return
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
	half := simulation_object_box(sim, id).half_extents
	dm.drag_position.y = max(
		dm.drag_position.y + wheel_delta * OBJECT_WHEEL_STEP,
		half.y,
	)
	_ = simulation_move_object(sim, id, dm.drag_position)
}

@(private)
add_crate_at_crosshair :: proc(dm: ^Debug_Mode, sim: ^Simulation) {
	forward := debug_camera_forward(dm.camera)
	center := dm.camera.position + forward * OBJECT_ADD_DISTANCE

	hit := cast_edit_ray(dm, sim)
	if hit.hit {
		normal := hit.normal
		extent := box_extent_along(prefab(.Crate).half_extents, normal)
		center = b3.ToVec3(hit.point) + normal * (extent + OBJECT_ADD_GAP)
	}

	id := simulation_create_object(
		sim,
		{
			prefab = .Crate,
			body_mode = .Dynamic,
			center = center,
			yaw = 0.0,
		},
	)
	if id == INVALID_OBJECT_ID {
		return
	}
	dm.selection = .Object
	dm.selected_object_id = id
	dm.dragging = .None
	dm.drag_position = center
}

@(private)
delete_selected_object :: proc(dm: ^Debug_Mode, sim: ^Simulation) {
	id, ok := debug_selected_object_id(dm, sim)
	if !ok {
		return
	}
	if !simulation_remove_object(sim, id) {
		return
	}
	debug_mode_clear_selection(dm)
}

@(private)
cast_edit_ray :: proc(dm: ^Debug_Mode, sim: ^Simulation) -> b3.RayResult {
	return b3.World_CastRayClosest(
		sim.world_id,
		b3.ToPos(dm.camera.position),
		debug_camera_forward(dm.camera) * OBJECT_RAY_LENGTH,
		b3.DefaultQueryFilter(),
	)
}

@(private)
box_extent_along :: proc(half_extents, direction: b3.Vec3) -> f32 {
	return half_extents.x * abs(direction.x) +
	       half_extents.y * abs(direction.y) +
	       half_extents.z * abs(direction.z)
}
