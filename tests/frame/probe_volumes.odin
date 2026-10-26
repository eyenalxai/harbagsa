#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package frame_test

import "core:testing"

import "src:frame"
import "src:game"

ROOM_LOW :: [3]f32{
	game.ARENA_ROOM_INNER_LOW_X,
	0,
	game.ARENA_ROOM_INNER_LOW_Z,
}
ROOM_HIGH :: [3]f32{
	game.ARENA_ROOM_INNER_HIGH_X,
	game.ARENA_ROOM_HEIGHT,
	game.ARENA_ROOM_INNER_HIGH_Z,
}
ROOM_OUTER_LOW :: [2]f32{
	game.ARENA_ROOM_X - game.ARENA_ROOM_HALF_SIZE,
	game.ARENA_ROOM_Z - game.ARENA_ROOM_HALF_SIZE,
}
ROOM_OUTER_HIGH :: [2]f32{
	game.ARENA_ROOM_X + game.ARENA_ROOM_HALF_SIZE,
	game.ARENA_ROOM_Z + game.ARENA_ROOM_HALF_SIZE,
}
ROOM_TOP :: f32(game.ARENA_ROOM_HEIGHT + game.ARENA_ROOM_CEILING_THICKNESS)

DEFAULT_PROBE_COUNT :: 537

@(private)
inside_room_footprint :: proc(point: [3]f32) -> bool {
	return(
		point.x > ROOM_OUTER_LOW.x &&
		point.x < ROOM_OUTER_HIGH.x &&
		point.z > ROOM_OUTER_LOW.y &&
		point.z < ROOM_OUTER_HIGH.y \
	)
}

@(test)
room_volume_is_first :: proc(t: ^testing.T) {
	testing.expect_value(t, len(frame.PROBE_VOLUMES), 6)
	room := frame.PROBE_VOLUMES[0]
	testing.expect_value(t, room.min, ROOM_LOW)
	testing.expect_value(t, room.counts, [3]u32{10, 3, 10})
	testing.expect_value(t, room.spacing, f32(1.04))
	testing.expect_value(t, frame.PROBE_VOLUME_NAMES[0], "room")
	testing.expect_value(t, frame.PROBE_VOLUME_NAMES[5], "north")
}

@(test)
default_probe_count_matches_the_atlas :: proc(t: ^testing.T) {
	total := 0
	for volume in frame.PROBE_VOLUMES {
		total += frame.probe_volume_probe_count(volume)
	}
	testing.expect_value(t, total, DEFAULT_PROBE_COUNT)
}

@(test)
probe_centre_and_high_agree :: proc(t: ^testing.T) {
	volume := frame.PROBE_VOLUMES[0]
	high := frame.probe_volume_high(volume)
	testing.expect_value(t, high, [3]f32{ROOM_LOW.x + 10 * 1.04, ROOM_LOW.y + 3 * 1.04, ROOM_LOW.z + 10 * 1.04})
	centre := frame.probe_volume_centre(volume, 0, 0, 0)
	testing.expect_value(t, centre, ROOM_LOW + [3]f32{0.5, 0.5, 0.5} * 1.04)
	testing.expect(t, frame.probe_volume_contains(volume, centre))
	testing.expect(t, !frame.probe_volume_contains(volume, high + {0.01, 0, 0}))
}

@(test)
ownership_picks_the_first_matching_volume :: proc(t: ^testing.T) {
	room_point := [3]f32{(ROOM_LOW.x + ROOM_HIGH.x) * 0.5, 1.5, (ROOM_LOW.z + ROOM_HIGH.z) * 0.5}
	testing.expect_value(t, frame.probe_volume_owner(frame.PROBE_VOLUMES[:], room_point), 0)

	roof_point := [3]f32{game.ARENA_ROOM_X, game.ARENA_ROOM_HEIGHT + 1.0, game.ARENA_ROOM_Z}
	testing.expect_value(t, frame.probe_volume_owner(frame.PROBE_VOLUMES[:], roof_point), 1)

	north_point := [3]f32{0, 1.5, game.ARENA_ROOM_Z + 10}
	testing.expect_value(t, frame.probe_volume_owner(frame.PROBE_VOLUMES[:], north_point), 5)

	outside := [3]f32{0, 1.5, game.ARENA_HALF_SIZE * 2}
	testing.expect_value(t, frame.probe_volume_owner(frame.PROBE_VOLUMES[:], outside), -1)
}

@(test)
arena_probe_centres_stay_out_of_the_room :: proc(t: ^testing.T) {
	for volume, index in frame.PROBE_VOLUMES {
		if index == 0 {
			continue
		}
		for z in 0 ..< int(volume.counts.z) {
			for y in 0 ..< int(volume.counts.y) {
				for x in 0 ..< int(volume.counts.x) {
					centre := frame.probe_volume_centre(volume, x, y, z)
					inside_room := centre.y < ROOM_TOP && inside_room_footprint(centre)
					testing.expectf(
						t,
						!inside_room,
						"volume %d centre %v is inside the room footprint",
						index,
						centre,
					)
				}
			}
		}
	}
}

@(test)
arena_bounds_stop_before_the_room_interior :: proc(t: ^testing.T) {
	for volume, index in frame.PROBE_VOLUMES {
		if index == 0 || volume.min.y >= ROOM_HIGH.y {
			continue
		}
		high := frame.probe_volume_high(volume)
		overlaps :=
			high.x > ROOM_LOW.x &&
			volume.min.x < ROOM_HIGH.x &&
			high.z > ROOM_LOW.z &&
			volume.min.z < ROOM_HIGH.z
		testing.expectf(
			t,
			!overlaps,
			"volume %d bounds reach the room interior at or below the ceiling",
			index,
		)
	}
}

@(test)
open_arena_is_covered :: proc(t: ^testing.T) {
	step: f32 = 0.5
	for y in ([2]f32{1.0, 3.9}) {
		z: f32 = -game.ARENA_HALF_SIZE
		for z <= game.ARENA_HALF_SIZE {
			x: f32 = -game.ARENA_HALF_SIZE
			for x <= game.ARENA_HALF_SIZE {
				point := [3]f32{x, y, z}
				index := frame.probe_volume_owner(frame.PROBE_VOLUMES[:], point)
				room_interior :=
					x >= ROOM_LOW.x &&
					x <= ROOM_HIGH.x &&
					z >= ROOM_LOW.z &&
					z <= ROOM_HIGH.z &&
					y <= ROOM_HIGH.y
				if room_interior {
					testing.expectf(
						t,
						index == 0,
						"room point %v selected volume %d",
						point,
						index,
					)
				} else if !inside_room_footprint(point) || y > ROOM_TOP {
					testing.expectf(t, index >= 0, "no volume covers arena point %v", point)
				}
				x += step
			}
			z += step
		}
	}
}
