#+vet explicit-allocators
package game

// The static arena from the walking-demo spec. This file is the single source
// of arena geometry and colors: the simulation builds bodies from these boxes
// and the main loop hands them to the renderer.
//
// The floor's top face is at y = 0. Walls stand on the floor and enclose the
// 40 m x 40 m play area. Crate placeholders are 1 m cubes that rest on the
// floor.

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
CRATE_COLORS :: [3][4]f32 {
	{0.30, 0.68, 0.38, 1.0},
	{0.86, 0.56, 0.20, 1.0},
	{0.26, 0.48, 0.84, 1.0},
}

// Arena_Box is one axis-aligned box in the arena. Center is the box center and
// half_extents is half its size on each axis. Color belongs to presentation
// only; the simulation can ignore it.
Arena_Box :: struct {
	center:       [3]f32,
	half_extents: [3]f32,
	color:        [4]f32,
}

arena_boxes :: proc() -> []Arena_Box {
	@(static) boxes := [ARENA_BOX_COUNT]Arena_Box {
		{
			center = {0, -0.5, 0},
			half_extents = {ARENA_HALF_SIZE, 0.5, ARENA_HALF_SIZE},
			color = FLOOR_COLOR,
		},
		{
			center = {0, ARENA_WALL_HEIGHT * 0.5, -(ARENA_HALF_SIZE + ARENA_WALL_THICKNESS * 0.5)},
			half_extents = {
				ARENA_HALF_SIZE + ARENA_WALL_THICKNESS,
				ARENA_WALL_HEIGHT * 0.5,
				ARENA_WALL_THICKNESS * 0.5,
			},
			color = WALL_COLOR,
		},
		{
			center = {0, ARENA_WALL_HEIGHT * 0.5, ARENA_HALF_SIZE + ARENA_WALL_THICKNESS * 0.5},
			half_extents = {
				ARENA_HALF_SIZE + ARENA_WALL_THICKNESS,
				ARENA_WALL_HEIGHT * 0.5,
				ARENA_WALL_THICKNESS * 0.5,
			},
			color = WALL_COLOR,
		},
		{
			center = {-(ARENA_HALF_SIZE + ARENA_WALL_THICKNESS * 0.5), ARENA_WALL_HEIGHT * 0.5, 0},
			half_extents = {
				ARENA_WALL_THICKNESS * 0.5,
				ARENA_WALL_HEIGHT * 0.5,
				ARENA_HALF_SIZE,
			},
			color = WALL_COLOR,
		},
		{
			center = {ARENA_HALF_SIZE + ARENA_WALL_THICKNESS * 0.5, ARENA_WALL_HEIGHT * 0.5, 0},
			half_extents = {
				ARENA_WALL_THICKNESS * 0.5,
				ARENA_WALL_HEIGHT * 0.5,
				ARENA_HALF_SIZE,
			},
			color = WALL_COLOR,
		},
		{
			center = ARENA_CRATE_POSITIONS[0],
			half_extents = {ARENA_CRATE_HALF_SIZE, ARENA_CRATE_HALF_SIZE, ARENA_CRATE_HALF_SIZE},
			color = CRATE_COLORS[0],
		},
		{
			center = ARENA_CRATE_POSITIONS[1],
			half_extents = {ARENA_CRATE_HALF_SIZE, ARENA_CRATE_HALF_SIZE, ARENA_CRATE_HALF_SIZE},
			color = CRATE_COLORS[1],
		},
		{
			center = ARENA_CRATE_POSITIONS[2],
			half_extents = {ARENA_CRATE_HALF_SIZE, ARENA_CRATE_HALF_SIZE, ARENA_CRATE_HALF_SIZE},
			color = CRATE_COLORS[2],
		},
	}
	return boxes[:]
}

// arena_static_boxes returns the floor and wall boxes.
arena_static_boxes :: proc() -> []Arena_Box {
	return arena_boxes()[:ARENA_STATIC_BOX_COUNT]
}

// arena_crates returns the crate boxes. Their center is the resting position;
// the simulation owns the live position once the world starts.
arena_crates :: proc() -> []Arena_Box {
	return arena_boxes()[ARENA_STATIC_BOX_COUNT:]
}
