#+vet explicit-allocators
package game

import "src:geometry"

// The static arena from the walking-demo spec. This file is the single source
// of arena geometry and colors: the simulation builds bodies from these boxes
// and the main loop hands them to the renderer.
//
// The floor's top face is at y = 0. Walls stand on the floor and enclose the
// 40 m x 40 m play area. The crate boxes start at their resting positions and
// the simulation owns their live positions.

ARENA_SIZE :: 40.0
ARENA_HALF_SIZE :: ARENA_SIZE * 0.5
ARENA_WALL_HEIGHT :: 4.0
ARENA_WALL_THICKNESS :: 0.5
ARENA_CRATE_SIZE :: 1.0
ARENA_CRATE_HALF_SIZE :: ARENA_CRATE_SIZE * 0.5

// The arena list is split in two: the floor and walls are static bodies, and
// the crates are dynamic bodies that the player can push. Keep the static
// boxes first so both the simulation and the renderer can slice the list.
ARENA_STATIC_BOX_COUNT :: 5
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

arena_boxes :: proc() -> []geometry.Box {
	@(static) boxes := [ARENA_BOX_COUNT]geometry.Box {
		{
			center = {0, -0.5, 0},
			half_extents = {ARENA_HALF_SIZE, 0.5, ARENA_HALF_SIZE},
			color = FLOOR_COLOR,
			rotation = geometry.IDENTITY_ROTATION,
		},
		{
			center = {0, ARENA_WALL_HEIGHT * 0.5, -(ARENA_HALF_SIZE + ARENA_WALL_THICKNESS * 0.5)},
			half_extents = {
				ARENA_HALF_SIZE + ARENA_WALL_THICKNESS,
				ARENA_WALL_HEIGHT * 0.5,
				ARENA_WALL_THICKNESS * 0.5,
			},
			color = WALL_COLOR,
			rotation = geometry.IDENTITY_ROTATION,
		},
		{
			center = {0, ARENA_WALL_HEIGHT * 0.5, ARENA_HALF_SIZE + ARENA_WALL_THICKNESS * 0.5},
			half_extents = {
				ARENA_HALF_SIZE + ARENA_WALL_THICKNESS,
				ARENA_WALL_HEIGHT * 0.5,
				ARENA_WALL_THICKNESS * 0.5,
			},
			color = WALL_COLOR,
			rotation = geometry.IDENTITY_ROTATION,
		},
		{
			center = {-(ARENA_HALF_SIZE + ARENA_WALL_THICKNESS * 0.5), ARENA_WALL_HEIGHT * 0.5, 0},
			half_extents = {
				ARENA_WALL_THICKNESS * 0.5,
				ARENA_WALL_HEIGHT * 0.5,
				ARENA_HALF_SIZE,
			},
			color = WALL_COLOR,
			rotation = geometry.IDENTITY_ROTATION,
		},
		{
			center = {ARENA_HALF_SIZE + ARENA_WALL_THICKNESS * 0.5, ARENA_WALL_HEIGHT * 0.5, 0},
			half_extents = {
				ARENA_WALL_THICKNESS * 0.5,
				ARENA_WALL_HEIGHT * 0.5,
				ARENA_HALF_SIZE,
			},
			color = WALL_COLOR,
			rotation = geometry.IDENTITY_ROTATION,
		},
		{
			center = ARENA_CRATE_POSITIONS[0],
			half_extents = {ARENA_CRATE_HALF_SIZE, ARENA_CRATE_HALF_SIZE, ARENA_CRATE_HALF_SIZE},
			color = CRATE_COLORS[0],
			rotation = geometry.IDENTITY_ROTATION,
		},
		{
			center = ARENA_CRATE_POSITIONS[1],
			half_extents = {ARENA_CRATE_HALF_SIZE, ARENA_CRATE_HALF_SIZE, ARENA_CRATE_HALF_SIZE},
			color = CRATE_COLORS[1],
			rotation = geometry.IDENTITY_ROTATION,
		},
		{
			center = ARENA_CRATE_POSITIONS[2],
			half_extents = {ARENA_CRATE_HALF_SIZE, ARENA_CRATE_HALF_SIZE, ARENA_CRATE_HALF_SIZE},
			color = CRATE_COLORS[2],
			rotation = geometry.IDENTITY_ROTATION,
		},
	}
	return boxes[:]
}

// arena_static_boxes returns the floor and wall boxes.
arena_static_boxes :: proc() -> []geometry.Box {
	return arena_boxes()[:ARENA_STATIC_BOX_COUNT]
}

// arena_crates returns the crate boxes. Their center is the resting position;
// the simulation owns the live position and rotation once the world starts.
arena_crates :: proc() -> []geometry.Box {
	return arena_boxes()[ARENA_STATIC_BOX_COUNT:]
}
