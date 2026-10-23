#+vet explicit-allocators
package game

import "core:math"

import b3 "libs:box3d"

CRATE_DRAG_SCALE :: 0.02
CRATE_WHEEL_STEP :: 0.5
CRATE_SELECTION_RAY_LENGTH :: 100.0
CRATE_ADD_GAP :: 0.01
CRATE_ADD_DISTANCE :: 3.0

debug_edit_crates :: proc(dm: ^Debug_Mode, sim: ^Simulation, input: Debug_Input) {
	clear_stale_crate_selection(dm, sim)

	if input.add_pressed {
		add_crate_at_crosshair(dm, sim)
	}
	if input.primary_pressed && input.captured && dm.dragging == .None {
		press_crate(dm, sim)
	}
	if input.primary_released && dm.dragging == .Crate {
		dm.dragging = .None
	}
	if dm.dragging == .Crate && input.captured {
		drag_crate(dm, sim, input.look_delta)
	}
	if dm.selection == .Crate && input.wheel_delta != 0.0 {
		wheel_crate(dm, sim, input.wheel_delta)
	}
	if input.delete_pressed && dm.selection == .Crate {
		delete_selected_crate(dm, sim)
	}
}

@(private)
clear_stale_crate_selection :: proc(dm: ^Debug_Mode, sim: ^Simulation) {
	if dm.selection != .Crate {
		return
	}
	if dm.selected_crate >= 0 && dm.selected_crate < simulation_crate_count(sim) {
		return
	}
	clear_crate_selection(dm)
}

@(private)
clear_crate_selection :: proc(dm: ^Debug_Mode) {
	dm.selection = .None
	dm.selected_crate = -1
	dm.dragging = .None
}

@(private)
press_crate :: proc(dm: ^Debug_Mode, sim: ^Simulation) {
	hit := cast_edit_ray(dm, sim)
	if hit.hit {
		index := crate_index_for_body(sim, b3.Shape_GetBody(hit.shapeId))
		if index >= 0 {
			dm.selection = .Crate
			dm.selected_crate = index
			dm.dragging = .Crate
			dm.drag_position = simulation_crate_box(sim, index).center
			return
		}
	}
	if dm.selection == .Crate {
		clear_crate_selection(dm)
	}
}

@(private)
drag_crate :: proc(dm: ^Debug_Mode, sim: ^Simulation, look_delta: [2]f32) {
	if dm.selected_crate < 0 || dm.selected_crate >= simulation_crate_count(sim) {
		return
	}

	yaw := dm.camera.yaw
	forward := b3.Vec3{-math.sin(yaw), 0.0, -math.cos(yaw)}
	right := b3.Vec3{math.cos(yaw), 0.0, -math.sin(yaw)}
	dm.drag_position +=
		right * (look_delta.x * CRATE_DRAG_SCALE) + forward * (-look_delta.y * CRATE_DRAG_SCALE)
	half := simulation_crate_box(sim, dm.selected_crate).half_extents
	dm.drag_position.y = max(dm.drag_position.y, half.y)
	simulation_move_crate(sim, dm.selected_crate, dm.drag_position)
}

@(private)
wheel_crate :: proc(dm: ^Debug_Mode, sim: ^Simulation, wheel_delta: f32) {
	if dm.selected_crate < 0 || dm.selected_crate >= simulation_crate_count(sim) {
		return
	}

	// Outside a drag the stored position can be stale after physics settling.
	if dm.dragging != .Crate {
		dm.drag_position = simulation_crate_box(sim, dm.selected_crate).center
	}
	half := simulation_crate_box(sim, dm.selected_crate).half_extents
	dm.drag_position.y = max(
		dm.drag_position.y + wheel_delta * CRATE_WHEEL_STEP,
		half.y,
	)
	simulation_move_crate(sim, dm.selected_crate, dm.drag_position)
}

@(private)
add_crate_at_crosshair :: proc(dm: ^Debug_Mode, sim: ^Simulation) {
	forward := camera_forward(dm.camera)
	center := dm.camera.position + forward * CRATE_ADD_DISTANCE

	hit := cast_edit_ray(dm, sim)
	if hit.hit {
		normal := hit.normal
		extent := box_extent_along(CRATE_HALF_EXTENTS, normal)
		center = b3.ToVec3(hit.point) + normal * (extent + CRATE_ADD_GAP)
	}

	index := simulation_add_default_crate(sim, center)
	if index < 0 {
		return
	}
	dm.selection = .Crate
	dm.selected_crate = index
	dm.dragging = .None
	dm.drag_position = center
}

@(private)
delete_selected_crate :: proc(dm: ^Debug_Mode, sim: ^Simulation) {
	if !simulation_remove_crate(sim, dm.selected_crate) {
		return
	}
	clear_crate_selection(dm)
}

@(private)
cast_edit_ray :: proc(dm: ^Debug_Mode, sim: ^Simulation) -> b3.RayResult {
	return b3.World_CastRayClosest(
		sim.world_id,
		b3.ToPos(dm.camera.position),
		camera_forward(dm.camera) * CRATE_SELECTION_RAY_LENGTH,
		b3.DefaultQueryFilter(),
	)
}

@(private)
camera_forward :: proc(camera: Debug_Camera) -> b3.Vec3 {
	cos_pitch := math.cos(camera.pitch)
	return {
		-math.sin(camera.yaw) * cos_pitch,
		math.sin(camera.pitch),
		-math.cos(camera.yaw) * cos_pitch,
	}
}

@(private)
crate_index_for_body :: proc(sim: ^Simulation, body: b3.BodyId) -> int {
	for index in 0 ..< simulation_crate_count(sim) {
		if simulation_crate_body(sim, index) == body {
			return index
		}
	}
	return -1
}

@(private)
box_extent_along :: proc(half_extents, direction: b3.Vec3) -> f32 {
	return half_extents.x * abs(direction.x) +
	       half_extents.y * abs(direction.y) +
	       half_extents.z * abs(direction.z)
}
