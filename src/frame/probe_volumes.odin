#+vet explicit-allocators
package frame

import "src:game"
import "src:renderer"

// The sampler picks the first volume that contains the surface point, so the
// room volume stays first. It owns every interior surface, and an arena volume
// can add sky to the room's exterior without reaching the room.
ROOM_PROBE_SPACING :: 1.04
ROOM_PROBE_COUNTS :: [3]u32{10, 3, 10}

// The sealed-pair scenario builds two placed rooms around (-10, -8). One
// volume per room owns that room's interior before the 4 m arena strips, so a
// surface inside either room never samples a probe across the shared wall. The
// 0.05 m edge offset keeps every probe centre in air and still covers each
// inner wall face.
SEALED_PAIR_X :: f32(-10.0)
SEALED_PAIR_Z :: f32(-8.0)
SEALED_PAIR_PROBE_MIN_A :: [3]f32{SEALED_PAIR_X - 3.8, 0.0, SEALED_PAIR_Z - 1.8}
SEALED_PAIR_PROBE_MIN_B :: [3]f32{SEALED_PAIR_X + 0.2, 0.0, SEALED_PAIR_Z - 1.8}
SEALED_PAIR_PROBE_SPACING :: f32(1.0)
SEALED_PAIR_PROBE_COUNTS :: [3]u32{4, 3, 4}

// Sky fill is low frequency, so the open arena uses a 4 m cell. The north strip
// is 5.5 m deep and needs two rows that both stay outside the room, which fixes
// its spacing at 2.775 m.
ARENA_PROBE_SPACING :: f32(4.0)
NORTH_PROBE_SPACING :: f32(2.775)

// The room's outer wall face. An arena bound sits 0.05 m inside it, so a face
// fragment that rounds outward still lands in the arena volume. The 0.3 m wall
// keeps the arena grid at least 0.25 m from the room's inner face.
ROOM_OUTER_LOW_X :: f32(game.ARENA_ROOM_X - game.ARENA_ROOM_HALF_SIZE)
ROOM_OUTER_HIGH_X :: f32(game.ARENA_ROOM_X + game.ARENA_ROOM_HALF_SIZE)
ROOM_OUTER_LOW_Z :: f32(game.ARENA_ROOM_Z - game.ARENA_ROOM_HALF_SIZE)
ROOM_OUTER_HIGH_Z :: f32(game.ARENA_ROOM_Z + game.ARENA_ROOM_HALF_SIZE)

ARENA_PROBE_EDGE :: f32(0.05)

ARENA_LOW :: f32(-game.ARENA_HALF_SIZE)

ROOF_PROBE_COUNTS :: [3]u32{3, 1, 3}
WEST_PROBE_COUNTS :: [3]u32{7, 2, 3}
EAST_PROBE_COUNTS :: [3]u32{1, 2, 3}
SOUTH_PROBE_COUNTS :: [3]u32{10, 2, 6}
NORTH_PROBE_COUNTS :: [3]u32{15, 2, 2}

// The four perimeter volumes tile the open floor and stop at the room
// footprint. Each centre is outside the footprint: a south centre at z <= 1.55,
// a north centre at z >= 15.84, and a side centre at x <= 4.55 or x >= 19.45.
// The boundaries overlap where a strip meets a side, and every one of those
// cells is open sky.
//
// The roof volume lights the room's exterior roof. Its floor is the room
// ceiling height, and its probes sit above the roof; none of them is inside
// the room.
PROBE_VOLUMES := [8]renderer.Probe_Volume {
	{
		min = {game.ARENA_ROOM_INNER_LOW_X, 0.0, game.ARENA_ROOM_INNER_LOW_Z},
		spacing = ROOM_PROBE_SPACING,
		counts = ROOM_PROBE_COUNTS,
		probe_offset = 0,
	},
	{
		min = SEALED_PAIR_PROBE_MIN_A,
		spacing = SEALED_PAIR_PROBE_SPACING,
		counts = SEALED_PAIR_PROBE_COUNTS,
		probe_offset = 0,
	},
	{
		min = SEALED_PAIR_PROBE_MIN_B,
		spacing = SEALED_PAIR_PROBE_SPACING,
		counts = SEALED_PAIR_PROBE_COUNTS,
		probe_offset = 0,
	},
	{
		min = {
			ROOM_OUTER_LOW_X - ARENA_PROBE_EDGE,
			game.ARENA_ROOM_HEIGHT,
			ROOM_OUTER_LOW_Z - ARENA_PROBE_EDGE,
		},
		spacing = ARENA_PROBE_SPACING,
		counts = ROOF_PROBE_COUNTS,
		probe_offset = 0,
	},
	{
		min = {
			ROOM_OUTER_LOW_X +
			ARENA_PROBE_EDGE -
			f32(WEST_PROBE_COUNTS.x) * ARENA_PROBE_SPACING,
			0.0,
			ROOM_OUTER_LOW_Z - ARENA_PROBE_EDGE,
		},
		spacing = ARENA_PROBE_SPACING,
		counts = WEST_PROBE_COUNTS,
		probe_offset = 0,
	},
	{
		min = {
			ROOM_OUTER_HIGH_X - ARENA_PROBE_EDGE,
			0.0,
			ROOM_OUTER_LOW_Z - ARENA_PROBE_EDGE,
		},
		spacing = ARENA_PROBE_SPACING,
		counts = EAST_PROBE_COUNTS,
		probe_offset = 0,
	},
	{
		min = {
			ARENA_LOW,
			0.0,
			ROOM_OUTER_LOW_Z +
			ARENA_PROBE_EDGE -
			f32(SOUTH_PROBE_COUNTS.z) * ARENA_PROBE_SPACING,
		},
		spacing = ARENA_PROBE_SPACING,
		counts = SOUTH_PROBE_COUNTS,
		probe_offset = 0,
	},
	{
		min = {ARENA_LOW, 0.0, ROOM_OUTER_HIGH_Z - ARENA_PROBE_EDGE},
		spacing = NORTH_PROBE_SPACING,
		counts = NORTH_PROBE_COUNTS,
		probe_offset = 0,
	},
}
