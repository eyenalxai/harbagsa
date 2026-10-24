#+vet explicit-allocators
package game

import b3 "libs:box3d"

OBJECT_OUTLINE_COLOR :: [4]f32{1.0, 0.8, 0.2, 1.0}

collect_object_editor_lines :: proc(dm: ^Debug_Mode, sim: ^Simulation, collector: ^Debug_Lines) {
	id, ok := debug_selected_object_id(dm, sim)
	if !ok {
		return
	}

	body := simulation_object_body(sim, id)
	if !b3.Body_IsValid(body) {
		return
	}

	half := simulation_object_box(sim, id).half_extents
	local_corners := [8][3]f32 {
		{-half.x, -half.y, -half.z},
		{half.x, -half.y, -half.z},
		{half.x, half.y, -half.z},
		{-half.x, half.y, -half.z},
		{-half.x, -half.y, half.z},
		{half.x, -half.y, half.z},
		{half.x, half.y, half.z},
		{-half.x, half.y, half.z},
	}
	world_corners: [8][3]f32
	for corner, corner_index in local_corners {
		world_corners[corner_index] = b3.ToVec3(b3.Body_GetWorldPoint(body, corner))
	}

	append_box_edges(collector, world_corners, OBJECT_OUTLINE_COLOR)
}
