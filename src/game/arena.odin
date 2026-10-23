#+vet explicit-allocators
package game

import "src:geometry"

ARENA_SIZE :: 40.0
ARENA_HALF_SIZE :: ARENA_SIZE * 0.5
ARENA_WALL_HEIGHT :: 4.0
ARENA_WALL_THICKNESS :: 0.5
ARENA_CRATE_SIZE :: 1.0
ARENA_CRATE_HALF_SIZE :: ARENA_CRATE_SIZE * 0.5

// Floor and walls first, props next, crates last. The simulation and the
// renderer slice the list.
ARENA_BASE_BOX_COUNT :: 5
ARENA_STATIC_BOX_COUNT :: ARENA_BASE_BOX_COUNT + ARENA_PROP_COUNT
ARENA_CRATE_COUNT :: 3
ARENA_BOX_COUNT :: ARENA_STATIC_BOX_COUNT + ARENA_CRATE_COUNT

ARENA_CRATE_POSITIONS :: [ARENA_CRATE_COUNT][3]f32 {
	{0, ARENA_CRATE_HALF_SIZE, 8},
	{-3, ARENA_CRATE_HALF_SIZE, 6},
	{3, ARENA_CRATE_HALF_SIZE, 6},
}

FLOOR_COLOR :: [4]f32{0.42, 0.43, 0.46, 1.0}
WALL_COLOR :: [4]f32{0.55, 0.34, 0.26, 1.0}
CRATE_COLORS :: [ARENA_CRATE_COUNT][4]f32 {
	{0.30, 0.68, 0.38, 1.0},
	{0.86, 0.56, 0.20, 1.0},
	{0.26, 0.48, 0.84, 1.0},
}

@(private)
arena_data: [ARENA_BOX_COUNT]geometry.Box

@(private)
arena_initialized: bool

arena_boxes :: proc() -> []geometry.Box {
	if !arena_initialized {
		arena_data[0] = {
			center = {0, -0.5, 0},
			half_extents = {ARENA_HALF_SIZE, 0.5, ARENA_HALF_SIZE},
			color = FLOOR_COLOR,
			rotation = geometry.IDENTITY_ROTATION,
		}
		arena_data[1] = {
			center = {0, ARENA_WALL_HEIGHT * 0.5, -(ARENA_HALF_SIZE + ARENA_WALL_THICKNESS * 0.5)},
			half_extents = {
				ARENA_HALF_SIZE + ARENA_WALL_THICKNESS,
				ARENA_WALL_HEIGHT * 0.5,
				ARENA_WALL_THICKNESS * 0.5,
			},
			color = WALL_COLOR,
			rotation = geometry.IDENTITY_ROTATION,
		}
		arena_data[2] = {
			center = {0, ARENA_WALL_HEIGHT * 0.5, ARENA_HALF_SIZE + ARENA_WALL_THICKNESS * 0.5},
			half_extents = {
				ARENA_HALF_SIZE + ARENA_WALL_THICKNESS,
				ARENA_WALL_HEIGHT * 0.5,
				ARENA_WALL_THICKNESS * 0.5,
			},
			color = WALL_COLOR,
			rotation = geometry.IDENTITY_ROTATION,
		}
		arena_data[3] = {
			center = {-(ARENA_HALF_SIZE + ARENA_WALL_THICKNESS * 0.5), ARENA_WALL_HEIGHT * 0.5, 0},
			half_extents = {
				ARENA_WALL_THICKNESS * 0.5,
				ARENA_WALL_HEIGHT * 0.5,
				ARENA_HALF_SIZE,
			},
			color = WALL_COLOR,
			rotation = geometry.IDENTITY_ROTATION,
		}
		arena_data[4] = {
			center = {ARENA_HALF_SIZE + ARENA_WALL_THICKNESS * 0.5, ARENA_WALL_HEIGHT * 0.5, 0},
			half_extents = {
				ARENA_WALL_THICKNESS * 0.5,
				ARENA_WALL_HEIGHT * 0.5,
				ARENA_HALF_SIZE,
			},
			color = WALL_COLOR,
			rotation = geometry.IDENTITY_ROTATION,
		}

		build_arena_props(arena_data[ARENA_BASE_BOX_COUNT:ARENA_STATIC_BOX_COUNT])

		crate_positions := ARENA_CRATE_POSITIONS
		crate_colors := CRATE_COLORS
		for index in 0 ..< ARENA_CRATE_COUNT {
			arena_data[ARENA_STATIC_BOX_COUNT + index] = {
				center = crate_positions[index],
				half_extents = {ARENA_CRATE_HALF_SIZE, ARENA_CRATE_HALF_SIZE, ARENA_CRATE_HALF_SIZE},
				color = crate_colors[index],
				rotation = geometry.IDENTITY_ROTATION,
			}
		}
		arena_initialized = true
	}
	return arena_data[:]
}

arena_static_boxes :: proc() -> []geometry.Box {
	return arena_boxes()[:ARENA_STATIC_BOX_COUNT]
}

// The center is the resting position; the simulation owns the live position and rotation.
arena_crates :: proc() -> []geometry.Box {
	return arena_boxes()[ARENA_STATIC_BOX_COUNT:]
}
