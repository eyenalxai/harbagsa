#+vet explicit-allocators
package game

import "src:geometry"

ARENA_SIZE :: 40.0
ARENA_HALF_SIZE :: ARENA_SIZE * 0.5
ARENA_WALL_HEIGHT :: 4.0
ARENA_WALL_THICKNESS :: 0.5
ARENA_FLOOR_THICKNESS :: 1.0
ARENA_CRATE_SIZE :: 1.0
ARENA_CRATE_HALF_SIZE :: ARENA_CRATE_SIZE * 0.5

// Floor and walls first, props next. Crates are dynamic and live in Simulation.
ARENA_BASE_BOX_COUNT :: 5
ARENA_STATIC_BOX_COUNT :: ARENA_BASE_BOX_COUNT + ARENA_PROP_COUNT
INITIAL_CRATE_COUNT :: 3
MAX_CRATES :: 64
MAX_SCENE_BOXES :: ARENA_STATIC_BOX_COUNT + MAX_CRATES

INITIAL_CRATE_POSITIONS :: [INITIAL_CRATE_COUNT][3]f32 {
	{0, ARENA_CRATE_HALF_SIZE, 8},
	{-3, ARENA_CRATE_HALF_SIZE, 6},
	{3, ARENA_CRATE_HALF_SIZE, 6},
}

CRATE_HALF_EXTENTS :: [3]f32{ARENA_CRATE_HALF_SIZE, ARENA_CRATE_HALF_SIZE, ARENA_CRATE_HALF_SIZE}

FLOOR_COLOR :: [4]f32{0.42, 0.43, 0.46, 1.0}
WALL_COLOR :: [4]f32{0.55, 0.34, 0.26, 1.0}
INITIAL_CRATE_COLORS :: [INITIAL_CRATE_COUNT][4]f32 {
	{0.30, 0.68, 0.38, 1.0},
	{0.86, 0.56, 0.20, 1.0},
	{0.26, 0.48, 0.84, 1.0},
}

initial_crate_colors :: proc() -> [][4]f32 {
	@(static) colors := INITIAL_CRATE_COLORS
	return colors[:]
}

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

		build_arena_props(boxes[ARENA_BASE_BOX_COUNT:ARENA_STATIC_BOX_COUNT])
		initialized = true
	}
	return boxes[:]
}
