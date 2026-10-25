#+vet explicit-allocators
package game

import "src:geometry"

// The empty corner at positive x and positive z keeps the room out of the
// existing inspection views, so their image gates keep measuring the same scene.
ARENA_ROOM_X :: 13.5
ARENA_ROOM_Z :: 10.5
ARENA_ROOM_SIZE :: 7.0
ARENA_ROOM_HALF_SIZE :: ARENA_ROOM_SIZE * 0.5
ARENA_ROOM_WALL_THICKNESS :: 0.3
ARENA_ROOM_HEIGHT :: 3.0
ARENA_ROOM_CEILING_THICKNESS :: 0.3
ARENA_ROOM_DOOR_WIDTH :: 1.6
ARENA_ROOM_DOOR_HEIGHT :: 2.2

ARENA_ROOM_BOX_COUNT :: 7

ROOM_COLOR :: [4]f32{0.38, 0.60, 0.56, 1.0}

@(private)
build_arena_room :: proc(boxes: []geometry.Box) {
	assert(len(boxes) == ARENA_ROOM_BOX_COUNT)
	half_wall: f32 = ARENA_ROOM_WALL_THICKNESS * 0.5
	half_height: f32 = ARENA_ROOM_HEIGHT * 0.5
	low_x: f32 = ARENA_ROOM_X - ARENA_ROOM_HALF_SIZE + half_wall
	high_x: f32 = ARENA_ROOM_X + ARENA_ROOM_HALF_SIZE - half_wall
	sides := [2]f32{-1.0, 1.0}

	for side, index in sides {
		wall_z := ARENA_ROOM_Z + side * (ARENA_ROOM_HALF_SIZE - half_wall)
		boxes[index] = static_box(
			{ARENA_ROOM_X, half_height, wall_z},
			{ARENA_ROOM_HALF_SIZE, half_height, half_wall},
			ROOM_COLOR,
		)
	}
	boxes[2] = static_box(
		{high_x, half_height, ARENA_ROOM_Z},
		{half_wall, half_height, ARENA_ROOM_HALF_SIZE},
		ROOM_COLOR,
	)

	door_half: f32 = ARENA_ROOM_DOOR_WIDTH * 0.5
	segment_half: f32 = (ARENA_ROOM_SIZE - ARENA_ROOM_DOOR_WIDTH) * 0.25
	segment_offset: f32 = door_half + segment_half
	for side, index in sides {
		segment_z := ARENA_ROOM_Z + side * segment_offset
		boxes[3 + index] = static_box(
			{low_x, half_height, segment_z},
			{half_wall, half_height, segment_half},
			ROOM_COLOR,
		)
	}
	lintel_half: f32 = (ARENA_ROOM_HEIGHT - ARENA_ROOM_DOOR_HEIGHT) * 0.5
	boxes[5] = static_box(
		{low_x, ARENA_ROOM_DOOR_HEIGHT + lintel_half, ARENA_ROOM_Z},
		{half_wall, lintel_half, door_half},
		ROOM_COLOR,
	)

	boxes[6] = static_box(
		{
			ARENA_ROOM_X,
			ARENA_ROOM_HEIGHT + ARENA_ROOM_CEILING_THICKNESS * 0.5,
			ARENA_ROOM_Z,
		},
		{ARENA_ROOM_HALF_SIZE, ARENA_ROOM_CEILING_THICKNESS * 0.5, ARENA_ROOM_HALF_SIZE},
		ROOM_COLOR,
	)
}
