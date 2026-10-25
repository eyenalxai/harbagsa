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
		if index == 0 || volume.min.y >= ROOM_HIGH.y {
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
