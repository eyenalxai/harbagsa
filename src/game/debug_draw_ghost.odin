#+vet explicit-allocators
package game

GHOST_COLOR :: [4]f32{0.45, 0.85, 1.0, 1.0}
GHOST_FOOTPRINT_COLOR :: [4]f32{0.45, 0.85, 1.0, 0.55}

collect_placement_lines :: proc(dm: ^Debug_Mode, collector: ^Debug_Lines) {
	ghost, ok := debug_ghost_geometry(dm)
	if !ok {
		return
	}

	corners := oriented_box_corners(ghost.center, ghost.half_extents, ghost.rotation)
	append_box_edges(collector, corners, GHOST_COLOR)

	extent := oriented_aabb_half_extents(ghost.half_extents, ghost.rotation)
	append_footprint(collector, ghost.bottom, extent, ghost.surface.y, GHOST_FOOTPRINT_COLOR)

	if ghost.bottom.y > ghost.surface.y {
		guide := [3]f32{ghost.bottom.x, ghost.surface.y, ghost.bottom.z}
		append_debug_line(collector, guide, ghost.bottom, GHOST_COLOR)
	}
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
		append_debug_line(collector, corner, corners[(index + 1) % len(corners)], color)
	}
}
