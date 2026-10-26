#+vet explicit-allocators
package game

import "src:geometry"

// The empty corner at positive x and positive z keeps the room out of the
// existing inspection views, so their image gates keep measuring the same scene.
ARENA_ROOM_X :: 12.0
ARENA_ROOM_Z :: 9.0
ARENA_ROOM_SIZE :: 11.0
ARENA_ROOM_HALF_SIZE :: ARENA_ROOM_SIZE * 0.5
ARENA_ROOM_WALL_THICKNESS :: 0.3
ARENA_ROOM_HEIGHT :: 3.0
ARENA_ROOM_CEILING_THICKNESS :: 0.3
ARENA_ROOM_DOOR_WIDTH :: 1.6
ARENA_ROOM_DOOR_HEIGHT :: 2.2
ARENA_ROOM_DOOR_Z :: 13.2

ARENA_ROOM_TUNNEL_HEIGHT :: 2.4
ARENA_ROOM_TUNNEL_WIDTH :: 2.0

ARENA_ROOM_INNER_LOW_X :: ARENA_ROOM_X - ARENA_ROOM_HALF_SIZE + ARENA_ROOM_WALL_THICKNESS
ARENA_ROOM_INNER_HIGH_X :: ARENA_ROOM_X + ARENA_ROOM_HALF_SIZE - ARENA_ROOM_WALL_THICKNESS
ARENA_ROOM_INNER_LOW_Z :: ARENA_ROOM_Z - ARENA_ROOM_HALF_SIZE + ARENA_ROOM_WALL_THICKNESS
ARENA_ROOM_INNER_HIGH_Z :: ARENA_ROOM_Z + ARENA_ROOM_HALF_SIZE - ARENA_ROOM_WALL_THICKNESS

// The entry is a light lock: door, east, south, west, south, east into the
// chamber. Four right-angle turns leave no straight line from the door, so no
// direct light reaches the chamber from outside.
ARENA_ROOM_WALL_A_LOW_Z :: 11.9
ARENA_ROOM_WALL_A_HIGH_Z :: 12.2
ARENA_ROOM_LANE_2_HIGH_Z :: 11.9
ARENA_ROOM_WALL_B_LOW_Z :: 9.6
ARENA_ROOM_WALL_B_HIGH_Z :: 9.9
ARENA_ROOM_LANE_3_LOW_Z :: 7.6
ARENA_ROOM_LANE_3_HIGH_Z :: 9.6
ARENA_ROOM_WALL_C_LOW_Z :: 7.3
ARENA_ROOM_WALL_C_HIGH_Z :: 7.6
ARENA_ROOM_CONNECTOR_1_LOW_X :: 10.5
ARENA_ROOM_CONNECTOR_1_HIGH_X :: 12.5
ARENA_ROOM_CONNECTOR_2_HIGH_X :: 8.7
ARENA_ROOM_CHAMBER_LOW_X :: 12.8

ARENA_ROOM_BOX_COUNT :: 12

ROOM_COLOR :: [4]f32{0.38, 0.60, 0.56, 1.0}

@(private)
room_box :: proc(center, half_extents: [3]f32) -> geometry.Box {
	return static_box(center, half_extents, ROOM_COLOR)
}

@(private)
build_arena_room :: proc(boxes: []geometry.Box) {
	assert(len(boxes) == ARENA_ROOM_BOX_COUNT)
	half_wall: f32 = ARENA_ROOM_WALL_THICKNESS * 0.5
	half_height: f32 = ARENA_ROOM_HEIGHT * 0.5
	low_wall_x: f32 = ARENA_ROOM_INNER_LOW_X - half_wall
	high_wall_x: f32 = ARENA_ROOM_INNER_HIGH_X + half_wall
	low_wall_z: f32 = ARENA_ROOM_INNER_LOW_Z - half_wall
	high_wall_z: f32 = ARENA_ROOM_INNER_HIGH_Z + half_wall
	sides := [2]f32{-1.0, 1.0}

	for side, index in sides {
		wall_z := ARENA_ROOM_Z + side * (ARENA_ROOM_HALF_SIZE - half_wall)
		boxes[index] = room_box(
			{ARENA_ROOM_X, half_height, wall_z},
			{ARENA_ROOM_HALF_SIZE, half_height, half_wall},
		)
	}
	boxes[2] = room_box(
		{high_wall_x, half_height, ARENA_ROOM_Z},
		{half_wall, half_height, ARENA_ROOM_HALF_SIZE},
	)

	door_low_z: f32 = ARENA_ROOM_DOOR_Z - ARENA_ROOM_DOOR_WIDTH * 0.5
	door_high_z: f32 = ARENA_ROOM_DOOR_Z + ARENA_ROOM_DOOR_WIDTH * 0.5
	south_half: f32 = (door_low_z - low_wall_z) * 0.5
	boxes[3] = room_box(
		{low_wall_x, half_height, low_wall_z + south_half},
		{half_wall, half_height, south_half},
	)
	north_half: f32 = (high_wall_z - door_high_z) * 0.5
	boxes[4] = room_box(
		{low_wall_x, half_height, door_high_z + north_half},
		{half_wall, half_height, north_half},
	)
	lintel_half: f32 = (ARENA_ROOM_HEIGHT - ARENA_ROOM_DOOR_HEIGHT) * 0.5
	boxes[5] = room_box(
		{low_wall_x, ARENA_ROOM_DOOR_HEIGHT + lintel_half, ARENA_ROOM_DOOR_Z},
		{half_wall, lintel_half, ARENA_ROOM_DOOR_WIDTH * 0.5},
	)
	boxes[6] = room_box(
		{
			ARENA_ROOM_X,
			ARENA_ROOM_HEIGHT + ARENA_ROOM_CEILING_THICKNESS * 0.5,
			ARENA_ROOM_Z,
		},
		{ARENA_ROOM_HALF_SIZE, ARENA_ROOM_CEILING_THICKNESS * 0.5, ARENA_ROOM_HALF_SIZE},
	)

	// Wall A separates lane 1 from lane 2, and ends at connector 1.
	wall_a_half_x: f32 = (ARENA_ROOM_CONNECTOR_1_LOW_X - ARENA_ROOM_INNER_LOW_X) * 0.5
	wall_a_half_z: f32 = (ARENA_ROOM_WALL_A_HIGH_Z - ARENA_ROOM_WALL_A_LOW_Z) * 0.5
	boxes[7] = room_box(
		{
			ARENA_ROOM_INNER_LOW_X + wall_a_half_x,
			half_height,
			ARENA_ROOM_WALL_A_LOW_Z + wall_a_half_z,
		},
		{wall_a_half_x, half_height, wall_a_half_z},
	)

	// Wall B separates lane 2 from lane 3, and ends at connector 2.
	wall_b_half_x: f32 = (ARENA_ROOM_CONNECTOR_1_HIGH_X - ARENA_ROOM_CONNECTOR_2_HIGH_X) * 0.5
	wall_b_half_z: f32 = (ARENA_ROOM_WALL_B_HIGH_Z - ARENA_ROOM_WALL_B_LOW_Z) * 0.5
	boxes[8] = room_box(
		{
			ARENA_ROOM_CONNECTOR_2_HIGH_X + wall_b_half_x,
			half_height,
			ARENA_ROOM_WALL_B_LOW_Z + wall_b_half_z,
		},
		{wall_b_half_x, half_height, wall_b_half_z},
	)

	// Wall C closes lane 3 to the south, so the chamber lies past the last turn.
	wall_c_half_x: f32 = (ARENA_ROOM_CONNECTOR_1_HIGH_X - ARENA_ROOM_INNER_LOW_X) * 0.5
	wall_c_half_z: f32 = (ARENA_ROOM_WALL_C_HIGH_Z - ARENA_ROOM_WALL_C_LOW_Z) * 0.5
	boxes[9] = room_box(
		{
			ARENA_ROOM_INNER_LOW_X + wall_c_half_x,
			half_height,
			ARENA_ROOM_WALL_C_LOW_Z + wall_c_half_z,
		},
		{wall_c_half_x, half_height, wall_c_half_z},
	)

	// Wall D closes the east side of the tunnel. The gap south of it is the
	// exit into the chamber.
	wall_d_half_z: f32 = (ARENA_ROOM_INNER_HIGH_Z - ARENA_ROOM_WALL_B_LOW_Z) * 0.5
	boxes[10] = room_box(
		{
			ARENA_ROOM_CONNECTOR_1_HIGH_X + half_wall,
			half_height,
			ARENA_ROOM_WALL_B_LOW_Z + wall_d_half_z,
		},
		{half_wall, half_height, wall_d_half_z},
	)

	tunnel_half_height: f32 = (ARENA_ROOM_HEIGHT - ARENA_ROOM_TUNNEL_HEIGHT) * 0.5
	tunnel_center_y: f32 = ARENA_ROOM_TUNNEL_HEIGHT + tunnel_half_height
	tunnel_half_x: f32 = (ARENA_ROOM_CONNECTOR_1_HIGH_X - ARENA_ROOM_INNER_LOW_X) * 0.5
	tunnel_half_z: f32 = (ARENA_ROOM_INNER_HIGH_Z - ARENA_ROOM_WALL_C_HIGH_Z) * 0.5
	boxes[11] = room_box(
		{
			ARENA_ROOM_INNER_LOW_X + tunnel_half_x,
			tunnel_center_y,
			ARENA_ROOM_WALL_C_HIGH_Z + tunnel_half_z,
		},
		{tunnel_half_x, tunnel_half_height, tunnel_half_z},
	)
}
