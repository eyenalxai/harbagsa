#+vet explicit-allocators
package game

import "src:geometry"

ARENA_SIZE :: 40.0
ARENA_HALF_SIZE :: ARENA_SIZE * 0.5
ARENA_WALL_HEIGHT :: 5.5
ARENA_WALL_THICKNESS :: 0.5
ARENA_FLOOR_THICKNESS :: 1.0
ARENA_CEILING_THICKNESS :: 0.5

// Floor, walls, and ceiling first, props next. Placed objects live in Simulation
// and render after this fixed set.
ARENA_BASE_BOX_COUNT :: 6
ARENA_STATIC_BOX_COUNT :: ARENA_BASE_BOX_COUNT + ARENA_PROP_COUNT

FLOOR_COLOR :: [4]f32{0.42, 0.43, 0.46, 1.0}
WALL_COLOR :: [4]f32{0.55, 0.34, 0.26, 1.0}
CEILING_COLOR :: [4]f32{0.20, 0.23, 0.27, 1.0}

arena_static_boxes :: proc() -> []geometry.Box {
	@(static) boxes: [ARENA_STATIC_BOX_COUNT]geometry.Box
	@(static) initialized := false
	if !initialized {
		boxes[0] = {
			center = {0, -ARENA_FLOOR_THICKNESS * 0.5, 0},
			half_extents = {ARENA_HALF_SIZE, ARENA_FLOOR_THICKNESS * 0.5, ARENA_HALF_SIZE},
			color = FLOOR_COLOR,
			rotation = geometry.IDENTITY_ROTATION,
		}
		boxes[1] = {
			center = {0, ARENA_WALL_HEIGHT * 0.5, -(ARENA_HALF_SIZE + ARENA_WALL_THICKNESS * 0.5)},
			half_extents = {
				ARENA_HALF_SIZE + ARENA_WALL_THICKNESS,
				ARENA_WALL_HEIGHT * 0.5,
				ARENA_WALL_THICKNESS * 0.5,
			},
			color = WALL_COLOR,
			rotation = geometry.IDENTITY_ROTATION,
		}
		boxes[2] = {
			center = {0, ARENA_WALL_HEIGHT * 0.5, ARENA_HALF_SIZE + ARENA_WALL_THICKNESS * 0.5},
			half_extents = {
				ARENA_HALF_SIZE + ARENA_WALL_THICKNESS,
				ARENA_WALL_HEIGHT * 0.5,
				ARENA_WALL_THICKNESS * 0.5,
			},
			color = WALL_COLOR,
			rotation = geometry.IDENTITY_ROTATION,
		}
		boxes[3] = {
			center = {-(ARENA_HALF_SIZE + ARENA_WALL_THICKNESS * 0.5), ARENA_WALL_HEIGHT * 0.5, 0},
			half_extents = {
				ARENA_WALL_THICKNESS * 0.5,
				ARENA_WALL_HEIGHT * 0.5,
				ARENA_HALF_SIZE,
			},
			color = WALL_COLOR,
			rotation = geometry.IDENTITY_ROTATION,
		}
		boxes[4] = {
			center = {ARENA_HALF_SIZE + ARENA_WALL_THICKNESS * 0.5, ARENA_WALL_HEIGHT * 0.5, 0},
			half_extents = {
				ARENA_WALL_THICKNESS * 0.5,
				ARENA_WALL_HEIGHT * 0.5,
				ARENA_HALF_SIZE,
			},
			color = WALL_COLOR,
			rotation = geometry.IDENTITY_ROTATION,
		}
		boxes[5] = {
			center = {
				0,
				ARENA_WALL_HEIGHT + ARENA_CEILING_THICKNESS * 0.5,
				0,
			},
			half_extents = {
				ARENA_HALF_SIZE + ARENA_WALL_THICKNESS,
				ARENA_CEILING_THICKNESS * 0.5,
				ARENA_HALF_SIZE + ARENA_WALL_THICKNESS,
			},
			color = CEILING_COLOR,
			rotation = geometry.IDENTITY_ROTATION,
		}

		build_arena_props(boxes[ARENA_BASE_BOX_COUNT:ARENA_STATIC_BOX_COUNT])
		initialized = true
	}
	return boxes[:]
}
