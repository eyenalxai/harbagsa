#+vet explicit-allocators
package game

import b3 "libs:box3d"

CRATE_OUTLINE_COLOR :: [4]f32{1.0, 0.8, 0.2, 1.0}

collect_crate_editor_lines :: proc(dm: ^Debug_Mode, sim: ^Simulation, collector: ^Debug_Lines) {
	if dm.selection != .Crate {
		return
	}
	if dm.selected_crate < 0 || dm.selected_crate >= simulation_crate_count(sim) {
		return
	}

	body := simulation_crate_body(sim, dm.selected_crate)
	if !b3.Body_IsValid(body) {
		return
	}

	half := simulation_crate_box(sim, dm.selected_crate).half_extents
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
	for corner, index in local_corners {
		world_corners[index] = b3.ToVec3(b3.Body_GetWorldPoint(body, corner))
	}

	edges := [12][2]int {
		{0, 1}, {1, 2}, {2, 3}, {3, 0},
		{4, 5}, {5, 6}, {6, 7}, {7, 4},
		{0, 4}, {1, 5}, {2, 6}, {3, 7},
	}
	for edge in edges {
		append_debug_line(collector, world_corners[edge.x], world_corners[edge.y], CRATE_OUTLINE_COLOR)
	}
}
