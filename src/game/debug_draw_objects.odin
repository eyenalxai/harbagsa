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

	box := simulation_object_box(sim, id)
	corners := oriented_box_corners(
		box.center,
		box.half_extents,
		transmute(b3.Quat)box.rotation,
	)
	append_box_edges(collector, corners, OBJECT_OUTLINE_COLOR)
}
