#+vet explicit-allocators
package game

GHOST_COLOR :: [4]f32{0.45, 0.85, 1.0, 1.0}
GHOST_FOOTPRINT_COLOR :: [4]f32{0.45, 0.85, 1.0, 0.55}

collect_placement_lines :: proc(
	editor: ^Editor,
	sim: ^Simulation,
	camera: Debug_Camera,
	collector: ^Debug_Lines,
) {
	ghost, ok := editor_placement_geometry(editor, sim, camera)
	if !ok {
		return
	}
	placement, _ := editor.tool.(Placement)

	color := placement_ghost_color(placement)
	footprint := [4]f32{color.x, color.y, color.z, GHOST_FOOTPRINT_COLOR.a}
	corners := oriented_box_corners(ghost.center, ghost.half_extents, ghost.rotation)
	append_box_edges(collector, corners, color, .Placement)

	extent := oriented_aabb_half_extents(ghost.half_extents, ghost.rotation)
	append_footprint(collector, ghost.bottom, extent, ghost.surface.y, footprint)

	if ghost.bottom.y > ghost.surface.y {
		guide := [3]f32{ghost.bottom.x, ghost.surface.y, ghost.bottom.z}
		append_debug_line(collector, guide, ghost.bottom, color, .Placement)
	}
}

@(private)
placement_ghost_color :: proc(placement: Placement) -> [4]f32 {
	if placement.light.active {
		return light_color4(placement.light.color)
	}
	return GHOST_COLOR
}

@(private)
append_footprint :: proc(
	collector: ^Debug_Lines,
	bottom, extent: [3]f32,
	height: f32,
	color: [4]f32,
) {
	corners := [4][3]f32 {
		{bottom.x - extent.x, height, bottom.z - extent.z},
		{bottom.x + extent.x, height, bottom.z - extent.z},
		{bottom.x + extent.x, height, bottom.z + extent.z},
		{bottom.x - extent.x, height, bottom.z + extent.z},
	}
	for corner, index in corners {
		append_debug_line(collector, corner, corners[(index + 1) % len(corners)], color, .Placement)
	}
}
