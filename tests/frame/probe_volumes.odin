#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package frame_test

import "core:testing"

import "src:frame"
import "src:game"
import "src:renderer"

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

PAIR_VOLUME_A_INDEX :: 1
PAIR_VOLUME_B_INDEX :: 2
PAIR_ROOM_AIR_LOW := [2][3]f32 {
	{frame.SEALED_PAIR_X - 3.75, 0, frame.SEALED_PAIR_Z - 1.75},
	{frame.SEALED_PAIR_X + 0.25, 0, frame.SEALED_PAIR_Z - 1.75},
}
PAIR_ROOM_AIR_HIGH := [2][3]f32 {
	{frame.SEALED_PAIR_X - 0.25, game.ARENA_ROOM_HEIGHT, frame.SEALED_PAIR_Z + 1.75},
	{frame.SEALED_PAIR_X + 3.75, game.ARENA_ROOM_HEIGHT, frame.SEALED_PAIR_Z + 1.75},
}

@(private)
volume_high :: proc(volume: renderer.Probe_Volume) -> [3]f32 {
	counts := [3]f32 {
		f32(volume.counts.x),
		f32(volume.counts.y),
		f32(volume.counts.z),
	}
	return volume.min + counts * volume.spacing
}

@(private)
volume_contains :: proc(volume: renderer.Probe_Volume, point: [3]f32) -> bool {
	high := volume_high(volume)
	return(
		point.x >= volume.min.x &&
		point.x <= high.x &&
		point.y >= volume.min.y &&
		point.y <= high.y &&
		point.z >= volume.min.z &&
		point.z <= high.z \
	)
}

@(private)
first_volume :: proc(point: [3]f32) -> int {
	for volume, index in frame.PROBE_VOLUMES {
		if volume_contains(volume, point) {
			return index
		}
	}
	return -1
}

@(private)
inside_pair_air :: proc(point: [3]f32) -> bool {
	for room in 0 ..< 2 {
		low := PAIR_ROOM_AIR_LOW[room]
		high := PAIR_ROOM_AIR_HIGH[room]
		if point.x > low.x &&
		   point.x < high.x &&
		   point.y > low.y &&
		   point.y < high.y &&
		   point.z > low.z &&
		   point.z < high.z {
			return true
		}
	}
	return false
}

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
	testing.expect(t, len(frame.PROBE_VOLUMES) > 1, "the scene must supply arena volumes")
	room := frame.PROBE_VOLUMES[0]
	testing.expect_value(t, room.min, ROOM_LOW)
	testing.expect_value(t, room.counts, [3]u32{10, 3, 10})
	testing.expect_value(t, room.spacing, f32(1.04))

	pair_a := frame.PROBE_VOLUMES[PAIR_VOLUME_A_INDEX]
	testing.expect_value(t, pair_a.min, frame.SEALED_PAIR_PROBE_MIN_A)
	testing.expect_value(t, pair_a.counts, [3]u32{4, 3, 4})
	testing.expect_value(t, pair_a.spacing, f32(1.0))
	pair_b := frame.PROBE_VOLUMES[PAIR_VOLUME_B_INDEX]
	testing.expect_value(t, pair_b.min, frame.SEALED_PAIR_PROBE_MIN_B)
	testing.expect_value(t, pair_b.counts, [3]u32{4, 3, 4})
	testing.expect_value(t, pair_b.spacing, f32(1.0))
}

@(test)
sealed_pair_probes_sit_in_room_air :: proc(t: ^testing.T) {
	probe_count := 0
	for pair_index in PAIR_VOLUME_A_INDEX ..= PAIR_VOLUME_B_INDEX {
		pair := frame.PROBE_VOLUMES[pair_index]
		for z in 0 ..< int(pair.counts.z) {
			for y in 0 ..< int(pair.counts.y) {
				for x in 0 ..< int(pair.counts.x) {
					centre :=
						pair.min +
						([3]f32{f32(x), f32(y), f32(z)} + 0.5) * pair.spacing
					probe_count += 1
					testing.expectf(
						t,
						inside_pair_air(centre),
						"pair probe %v is not in room air",
						centre,
					)
					testing.expectf(
						t,
						abs(centre.x - frame.SEALED_PAIR_X) > 0.25,
						"pair probe %v is inside the shared wall",
						centre,
					)
				}
			}
		}
	}
	testing.expect_value(t, probe_count, 96)
}

@(test)
sealed_pair_interior_selects_the_pair_volume :: proc(t: ^testing.T) {
	points := [2][3]f32 {
		{(PAIR_ROOM_AIR_LOW[0].x + PAIR_ROOM_AIR_HIGH[0].x) * 0.5, 1.5, frame.SEALED_PAIR_Z},
		{(PAIR_ROOM_AIR_LOW[1].x + PAIR_ROOM_AIR_HIGH[1].x) * 0.5, 1.5, frame.SEALED_PAIR_Z},
	}
	testing.expect_value(t, first_volume(points[0]), PAIR_VOLUME_A_INDEX)
	testing.expect_value(t, first_volume(points[1]), PAIR_VOLUME_B_INDEX)

	faces := [8][3]f32 {
		{frame.SEALED_PAIR_X - 3.75, 1.5, frame.SEALED_PAIR_Z},
		{frame.SEALED_PAIR_X - 0.25, 1.5, frame.SEALED_PAIR_Z},
		{frame.SEALED_PAIR_X + 0.25, 1.5, frame.SEALED_PAIR_Z},
		{frame.SEALED_PAIR_X + 3.75, 1.5, frame.SEALED_PAIR_Z},
		{frame.SEALED_PAIR_X - 2.0, 1.5, frame.SEALED_PAIR_Z - 1.75},
		{frame.SEALED_PAIR_X + 2.0, 1.5, frame.SEALED_PAIR_Z + 1.75},
		{frame.SEALED_PAIR_X - 2.0, 0.0, frame.SEALED_PAIR_Z},
		{frame.SEALED_PAIR_X + 2.0, game.ARENA_ROOM_HEIGHT, frame.SEALED_PAIR_Z},
	}
	for point, index in faces {
		expected := index == 2 || index == 3 || index == 5 || index == 7 ? PAIR_VOLUME_B_INDEX : PAIR_VOLUME_A_INDEX
		testing.expect_value(t, first_volume(point), expected)
	}
}

@(test)
arena_probe_centres_stay_out_of_the_room :: proc(t: ^testing.T) {
	for volume, index in frame.PROBE_VOLUMES {
		if index <= PAIR_VOLUME_B_INDEX {
			continue
		}
		for z in 0 ..< int(volume.counts.z) {
			for y in 0 ..< int(volume.counts.y) {
				for x in 0 ..< int(volume.counts.x) {
					centre :=
						volume.min +
						([3]f32{f32(x), f32(y), f32(z)} + 0.5) * volume.spacing
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
		if index <= PAIR_VOLUME_B_INDEX || volume.min.y >= ROOM_HIGH.y {
			continue
		}
		high := volume_high(volume)
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
				index := first_volume(point)
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
